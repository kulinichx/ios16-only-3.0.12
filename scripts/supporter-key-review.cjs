'use strict';

const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const binding = require('./supporter-binding.cjs');
const reviewsName = 'supporter-device-key-reviews.json';
const need = (condition, message) => { if (!condition) throw new Error(message); };
const upperHex = (value, length) => typeof value === 'string' && new RegExp(`^[0-9A-F]{${length}}$`).test(value);
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);

function decode(value) {
  need(typeof value === 'string' && /^[A-Za-z0-9_-]+$/.test(value), 'invalid-proof-base64url');
  const bytes = Buffer.from(value, 'base64url');
  need(bytes.toString('base64url') === value, 'noncanonical-proof-base64url');
  return bytes;
}

function verifyProof(wire, canonicalChallenge) {
  need(typeof wire === 'string' && Buffer.byteLength(wire) <= 4096, 'invalid-proof-size');
  need(typeof canonicalChallenge === 'string' && Buffer.byteLength(canonicalChallenge) <= 2048, 'invalid-challenge-size');
  const proof = JSON.parse(wire);
  const challenge = JSON.parse(canonicalChallenge);
  need(proof.type === 'RHP1' && proof.version === 1 && upperHex(proof.challenge_id, 32) &&
    upperHex(proof.challenge_hash, 64) && proof.hardware_protocol === 'rh-hw-v1' &&
    upperHex(proof.hardware_hash, 64) && upperHex(proof.key_fingerprint, 64) &&
    proof.signature_algorithm === 'ecdsa-p256-sha256-x962', 'invalid-proof-fields');
  need(challenge.type === 'RHC1' && challenge.version === 1 && challenge.challenge_id === proof.challenge_id &&
    upperHex(challenge.nonce, 64) && challenge.audience === 'com.dopaminerh.supporter.device-proof' &&
    Number.isSafeInteger(challenge.issued_at) && Number.isSafeInteger(challenge.expires_at) &&
    challenge.expires_at > challenge.issued_at && challenge.expires_at - challenge.issued_at <= 900,
  'invalid-challenge-fields');
  need(JSON.stringify({ type: challenge.type, version: challenge.version, challenge_id: challenge.challenge_id,
    nonce: challenge.nonce, issued_at: challenge.issued_at, expires_at: challenge.expires_at,
    audience: challenge.audience }) === canonicalChallenge, 'noncanonical-challenge');
  need(binding.sha256(canonicalChallenge) === proof.challenge_hash, 'proof-challenge-mismatch');
  const unsigned = { type: proof.type, version: proof.version, challenge_id: proof.challenge_id,
    challenge_hash: proof.challenge_hash, hardware_protocol: proof.hardware_protocol, hardware_hash: proof.hardware_hash,
    key_fingerprint: proof.key_fingerprint, public_key: proof.public_key, signature_algorithm: proof.signature_algorithm };
  need(JSON.stringify({ ...unsigned, signature: proof.signature }) === wire, 'noncanonical-proof');
  const point = decode(proof.public_key);
  const key = binding.publicKeyFromPoint(point);
  need(binding.sha256(point) === proof.key_fingerprint, 'proof-fingerprint-mismatch');
  const message = Buffer.concat([Buffer.from('DopamineRH-RHP1-Sign-v1\0', 'ascii'), Buffer.from(JSON.stringify(unsigned))]);
  need(crypto.verify('sha256', message, key, decode(proof.signature)), 'invalid-device-proof-signature');
  return { proof, challenge };
}

function readReviews(directory) {
  const filename = path.join(directory, reviewsName);
  if (!fs.existsSync(filename)) return [];
  const reviews = binding.readArray(filename);
  const devices = new Set();
  for (const review of reviews) {
    need(review && typeof review.DeviceCode === 'string' && /^(?:[0-9A-F]{4}-){7}[0-9A-F]{4}$/.test(review.DeviceCode) &&
      typeof review.SupporterId === 'string' && /^\d{1,8}$/.test(review.SupporterId) &&
      !devices.has(review.DeviceCode), 'invalid-or-duplicate-review');
    devices.add(review.DeviceCode);
    need(['REVERIFY_REQUIRED', 'VERIFIED_PROOF'].includes(review.Kind), 'invalid-review-kind');
  }
  return reviews;
}

function reviewStatus(row, review) {
  if (!review) return row.binding ? 'READY_FOR_REVIEW' : 'LEGACY_UNBOUND';
  if (review.Kind === 'REVERIFY_REQUIRED') return 'REVERIFY_REQUIRED';
  try {
    const { proof, challenge } = verifyProof(review.Proof, review.Challenge);
    need(review.SupporterId === row.id && review.DeviceCode === row.deviceCode &&
      review.LicenseSha256 === binding.sha256(row.license), 'review-license-changed');
    need(Number.isSafeInteger(review.VerifiedAt) && review.VerifiedAt >= challenge.issued_at - 30 &&
      review.VerifiedAt < challenge.expires_at, 'invalid-review-time');
    need(row.binding, 'review-binding-missing');
    if (row.binding.HardwareHash !== proof.hardware_hash) return 'HARDWARE_MISMATCH';
    if (row.binding.KeyFingerprint !== proof.key_fingerprint) return 'REVIEW_KEY_MISMATCH';
    return 'READY_FOR_REVIEW';
  } catch { return 'REVERIFY_REQUIRED'; }
}

function applyReviews(result, directory) {
  const reviews = readReviews(directory);
  for (const row of result.rows) {
    row.keyReview = reviews.find(review => review.DeviceCode === row.deviceCode) || null;
    row.status = reviewStatus(row, row.keyReview);
  }
  return result;
}

function load(directory, publicKey) {
  return applyReviews(binding.plan(binding.readArray(path.join(directory, 'supporters.json')),
    binding.readArray(path.join(directory, 'supporter-device-proof-bindings.json')), publicKey), directory);
}

function replaceWithBackup(filename, value, before, manifest, io = fs) {
  const parent = path.dirname(filename);
  const backup = path.join(parent, 'binding-backups', `${Date.now()}-${crypto.randomBytes(8).toString('hex')}`);
  io.mkdirSync(backup, { recursive: true });
  if (before !== null) io.writeFileSync(path.join(backup, path.basename(filename)), before, { flag: 'wx', mode: 0o600 });
  io.writeFileSync(path.join(backup, 'change.json'), JSON.stringify(manifest, null, 2) + '\n', { flag: 'wx', mode: 0o600 });
  const temporary = path.join(parent, `.rh-key-review-${crypto.randomBytes(8).toString('hex')}.tmp`);
  try {
    const fd = io.openSync(temporary, 'wx', 0o600);
    try { io.writeFileSync(fd, JSON.stringify(value, null, 2) + '\n'); io.fsyncSync(fd); }
    finally { io.closeSync(fd); }
    const current = io.existsSync(filename) ? io.readFileSync(filename) : null;
    need(before === null ? current === null : current && current.equals(before), 'database-changed-before-replace');
    io.renameSync(temporary, filename);
  } finally { if (io.existsSync(temporary)) io.unlinkSync(temporary); }
  return backup;
}

function storeReview(directory, row, review) {
  const filename = path.join(directory, reviewsName);
  const before = fs.existsSync(filename) ? fs.readFileSync(filename) : null;
  const reviews = readReviews(directory);
  const index = reviews.findIndex(item => item.DeviceCode === row.deviceCode);
  if (index < 0) reviews.push(review);
  else reviews[index] = review;
  return replaceWithBackup(filename, reviews, before,
    { action: 'device-key-review', supporterId: row.id, kind: review.Kind, time: new Date().toISOString() });
}

function recordProof(directory, wire, publicKey, now = Math.floor(Date.now() / 1000)) {
  need(typeof wire === 'string' && Buffer.byteLength(wire) <= 4096, 'invalid-proof-size');
  const preview = JSON.parse(wire);
  const challenges = binding.readArray(path.join(directory, 'supporter-device-proof-challenges.json'));
  const matches = challenges.filter(item => item.ChallengeId === preview.challenge_id);
  need(matches.length === 1, 'review-challenge-not-found-or-duplicate');
  const saved = matches[0];
  need(saved.State === 'CONSUMED' && (!saved.Mode || saved.Mode === 'NORMAL'), 'review-requires-consumed-normal-challenge');
  const { proof, challenge } = verifyProof(wire, saved.Canonical);
  need(saved.ChallengeHash === proof.challenge_hash && saved.IssuedAt === challenge.issued_at &&
    saved.ExpiresAt === challenge.expires_at && now >= challenge.issued_at - 30 && now < challenge.expires_at,
  'review-proof-expired-or-challenge-changed');
  const result = load(directory, publicKey);
  const row = result.rows.find(item => item.deviceCode === saved.DeviceCode);
  // A new user can prove their device before the first RH1 is issued.
  if (!row) {
    const baseline = binding.readArray(path.join(directory, 'supporter-device-proof-bindings.json'))
      .find(item => item.DeviceCode === saved.DeviceCode);
    need(baseline && baseline.HardwareHash === proof.hardware_hash && baseline.KeyFingerprint === proof.key_fingerprint,
      'unassigned-proof-does-not-match-binding');
    return { status: 'UNASSIGNED_PROOF', signingPerformed: false };
  }
  need(row && row.binding, 'review-supporter-binding-missing');
  if (row.keyReview && row.keyReview.Kind === 'VERIFIED_PROOF' && row.keyReview.Challenge === saved.Canonical) {
    need(row.keyReview.Proof === wire, 'review-challenge-already-recorded');
    return { id: row.id, status: reviewStatus(row, row.keyReview), duplicate: true };
  }
  const review = { Kind: 'VERIFIED_PROOF', SupporterId: row.id, DeviceCode: row.deviceCode,
    LicenseSha256: binding.sha256(row.license), Proof: wire, Challenge: saved.Canonical, VerifiedAt: now };
  const backup = storeReview(directory, row, review);
  return { id: row.id, status: reviewStatus(row, review), backup };
}

function migrationPlan(directory, id, publicKey, now = Math.floor(Date.now() / 1000)) {
  const result = load(directory, publicKey);
  const row = result.rows.find(item => item.id === id);
  need(row && row.binding && row.status === 'REVIEW_KEY_MISMATCH', 'fresh-same-hardware-key-review-required');
  need(Number.isSafeInteger(row.keyReview.VerifiedAt) && now >= row.keyReview.VerifiedAt - 30 &&
    now - row.keyReview.VerifiedAt < 900, 'key-review-expired-generate-new-proof');
  const { proof } = verifyProof(row.keyReview.Proof, row.keyReview.Challenge);
  return { id: row.id, displayName: row.displayName, deviceCode: row.deviceCode, note: row.note,
    hardwareHash: row.binding.HardwareHash, oldKeyFingerprint: row.binding.KeyFingerprint,
    newKeyFingerprint: proof.key_fingerprint, reviewSha256: binding.reviewSha256([row]) };
}

function migrate(directory, id, digest, confirmId, publicKey, now = Math.floor(Date.now() / 1000), io = fs) {
  const plan = migrationPlan(directory, id, publicKey, now);
  need(confirmId === id && /^\d{1,8}$/.test(id), 'explicit-supporter-id-confirmation-required');
  need(plan.reviewSha256 === digest, 'review-stale-reload-plan');
  const filename = path.join(directory, 'supporter-device-proof-bindings.json');
  const before = io.readFileSync(filename);
  const bindings = JSON.parse(before.toString('utf8').replace(/^\uFEFF/, ''));
  need(Array.isArray(bindings), 'database-must-be-array');
  const indices = bindings.map((item, index) => item.DeviceCode === plan.deviceCode ? index : -1).filter(index => index >= 0);
  need(indices.length === 1, 'migration-binding-missing-or-duplicate');
  const index = indices[0];
  const baseline = bindings[index];
  need(baseline.HardwareHash === plan.hardwareHash && baseline.KeyFingerprint === plan.oldKeyFingerprint,
    'binding-changed-before-migration');
  const result = load(directory, publicKey);
  const row = result.rows.find(item => item.id === id);
  need(row && binding.reviewSha256([row]) === digest, 'review-stale-reload-plan');
  const { proof } = verifyProof(row.keyReview.Proof, row.keyReview.Challenge);
  const updated = { ...baseline, PublicKey: proof.public_key, KeyFingerprint: proof.key_fingerprint,
    LastVerifiedAt: new Date(now * 1000).toISOString(), LastKeyMigrationAt: new Date(now * 1000).toISOString() };
  const output = [...bindings];
  output[index] = updated;
  need(output.every((item, position) => position === index || same(item, bindings[position])), 'unrelated-binding-changed');
  const backup = replaceWithBackup(filename, output, before,
    { action: 'same-hardware-device-key-migration', supporterId: id, deviceCode: row.deviceCode,
      hardwareHash: plan.hardwareHash, oldKeyFingerprint: plan.oldKeyFingerprint,
      newKeyFingerprint: plan.newKeyFingerprint, reviewedSha256: digest, time: new Date(now * 1000).toISOString() }, io);
  return { migrated: true, id, backup, licenseChanged: false, signingPerformed: false };
}

function readProofInput() {
  const data = Buffer.alloc(4097);
  let length = 0;
  while (length < data.length) {
    const size = fs.readSync(0, data, length, data.length - length, null);
    if (!size) break;
    length += size;
  }
  need(length <= 4096, 'invalid-proof-size');
  return data.subarray(0, length).toString('utf8');
}

function main(argv, publicKey = binding.issuerPublicKey) {
  const [command, ...args] = argv;
  const options = {};
  while (args.length) {
    const key = args.shift(), value = args.shift();
    need(['--issuer-dir', '--id', '--device-code', '--review-sha256', '--confirm-id'].includes(key) && value && !options[key],
      'invalid-or-duplicate-option');
    options[key] = value;
  }
  need(options['--issuer-dir'], 'issuer-directory-required');
  const directory = path.resolve(options['--issuer-dir']);
  let result;
  if (command === 'review-proof') {
    need(Object.keys(options).length === 1, 'review-proof-options-invalid');
    result = recordProof(directory, readProofInput(), publicKey);
  } else if (command === 'block-key-review') {
    need(Object.keys(options).length === 2 && (options['--id'] || options['--device-code']), 'block-review-identity-required');
    const rows = load(directory, publicKey).rows;
    const row = rows.find(item => options['--id'] ? item.id === options['--id'] : item.deviceCode === options['--device-code']);
    need(row && row.binding, 'review-supporter-binding-missing');
    const backup = storeReview(directory, row, { Kind: 'REVERIFY_REQUIRED', SupporterId: row.id,
      DeviceCode: row.deviceCode, Reason: 'owner-reported-key-mismatch', RecordedAt: new Date().toISOString() });
    result = { id: row.id, status: 'REVERIFY_REQUIRED', backup, signingPerformed: false };
  } else if (command === 'rekey-plan') {
    need(Object.keys(options).length === 2 && options['--id'], 'rekey-plan-id-required');
    result = migrationPlan(directory, options['--id'], publicKey);
  } else if (command === 'rekey') {
    need(Object.keys(options).length === 4, 'rekey-confirmation-options-required');
    result = migrate(directory, options['--id'], options['--review-sha256'], options['--confirm-id'], publicKey);
  } else throw new Error('invalid-key-review-command');
  console.log(JSON.stringify(result, null, 2));
}

module.exports = { reviewsName, verifyProof, applyReviews, recordProof, migrationPlan, migrate, replaceWithBackup, main };
