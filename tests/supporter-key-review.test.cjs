'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const crypto = require('node:crypto');
const test = require('node:test');
const binding = require('../scripts/supporter-binding.cjs');
const review = require('../scripts/supporter-key-review.cjs');
const issuer = crypto.generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
const keys = [0, 1].map(() => crypto.generateKeyPairSync('ec', { namedCurve: 'prime256v1' }));
const points = keys.map(key => {
  const jwk = key.publicKey.export({ format: 'jwk' });
  return Buffer.concat([Buffer.from([4]), Buffer.from(jwk.x, 'base64url'), Buffer.from(jwk.y, 'base64url')]);
});
const device = '0123-4567-89AB-CDEF-0123-4567-89AB-CDEF';
const other = 'FFFF-FFFF-FFFF-FFFF-FFFF-FFFF-FFFF-FFFF';
const hw = binding.sha256('synthetic iPad hardware');
const now = Math.floor(Date.now() / 1000);
const challenge = JSON.stringify({ type: 'RHC1', version: 1, challenge_id: 'A'.repeat(32), nonce: 'B'.repeat(64),
  issued_at: now - 10, expires_at: now + 290, audience: 'com.dopaminerh.supporter.device-proof' });

function proof(hardware = hw, keyIndex = 1, override = {}) {
  const unsigned = { type: 'RHP1', version: 1, challenge_id: 'A'.repeat(32), challenge_hash: binding.sha256(challenge),
    hardware_protocol: 'rh-hw-v1', hardware_hash: hardware, key_fingerprint: binding.sha256(points[keyIndex]),
    public_key: points[keyIndex].toString('base64url'), signature_algorithm: 'ecdsa-p256-sha256-x962', ...override };
  const signature = crypto.sign('sha256', Buffer.concat([Buffer.from('DopamineRH-RHP1-Sign-v1\0'),
    Buffer.from(JSON.stringify(unsigned))]), keys[keyIndex].privateKey).toString('base64url');
  return JSON.stringify({ ...unsigned, signature });
}

function license(id, code) {
  const body = Buffer.from(JSON.stringify({ v: 1, product: 'DopamineRH', sid: id, device: code, ent: ['custom_glass'] }));
  return `RH1.${body.toString('base64url')}.${crypto.sign('sha256', body, issuer.privateKey).toString('base64url')}`;
}

function fixture(run) {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'rh-key-review-'));
  const files = Object.fromEntries(['supporters.json', 'supporter-device-proof-bindings.json',
    'supporter-device-proof-challenges.json', review.reviewsName].map(name => [name, path.join(directory, name)]));
  const records = [['0029', device], ['0030', other]].map(([id, code]) => ({ SupporterId: id, DeviceCode: code,
    License: license(id, code), DisplayName: `Synthetic ${id}`, Note: 'TEST ONLY' }));
  const bindings = [device, other].map(code => ({ DeviceCode: code, HardwareHash: hw,
    PublicKey: points[0].toString('base64url'), KeyFingerprint: binding.sha256(points[0]), FirstVerifiedAt: 'preserve-this' }));
  const challenges = [{ ChallengeId: 'A'.repeat(32), State: 'CONSUMED', DeviceCode: device,
    IssuedAt: now - 10, ExpiresAt: now + 290, Canonical: challenge, ChallengeHash: binding.sha256(challenge) }];
  for (const [name, value] of [['supporters.json', records], ['supporter-device-proof-bindings.json', bindings],
    ['supporter-device-proof-challenges.json', challenges]]) fs.writeFileSync(files[name], JSON.stringify(value));
  try { run({ directory, files, records, bindings, challenges }); }
  finally { fs.rmSync(directory, { recursive: true, force: true }); }
}

function cli(directory, command, ...args) {
  const log = console.log;
  let value;
  console.log = text => { value = JSON.parse(text); };
  try { binding.main([command, '--issuer-dir', directory, ...args], issuer.publicKey); return value; }
  finally { console.log = log; }
}

test('proof review independently verifies canonical challenge, signature, public key and fingerprint', () => {
  assert.equal(review.verifyProof(proof(), challenge).proof.hardware_hash, hw);
  for (const wire of [proof() + '\n', proof().replace('"version":1', '"version":2'),
    proof(hw, 1, { key_fingerprint: 'F'.repeat(64) }),
    proof(hw, 1, { challenge_hash: 'F'.repeat(64) }),
    JSON.stringify({ ...JSON.parse(proof()), signature: 'AAAA' }), ' '.repeat(4097)]) {
    assert.throws(() => review.verifyProof(wire, challenge));
  }
  assert.throws(() => review.verifyProof(proof(), challenge + ' '), /noncanonical-challenge/);
});

test('key mismatch is durable across reload and blocks single or all-user issuance before opening a private key', () => fixture(({ directory, files }) => {
  const before = fs.readFileSync(files['supporter-device-proof-bindings.json']);
  const initial = cli(directory, 'plan');
  const saved = review.recordProof(directory, proof(), issuer.publicKey, now);
  assert.equal(saved.status, 'REVIEW_KEY_MISMATCH');
  const plan = cli(directory, 'plan');
  assert.equal(plan.eligible, 1);
  assert.equal(plan.records[0].status, 'REVIEW_KEY_MISMATCH');
  assert.notEqual(plan.records[0].reviewSha256, initial.records[0].reviewSha256);
  assert.throws(() => cli(directory, 'issue', '--id', '0029', '--out', path.join(directory, 'out.txt'),
    '--review-sha256', initial.records[0].reviewSha256), /review-blocked/);
  assert.throws(() => cli(directory, 'issue-all', '--out-dir', path.join(directory, 'batch'),
    '--review-sha256', initial.reviewSha256), /review-stale/);
  assert.deepEqual(fs.readFileSync(files['supporter-device-proof-bindings.json']), before);
  assert.equal(fs.existsSync(path.join(directory, 'DopamineRH-supporter-private.pem')), false);
}));

test('owner-reported mismatch marks only the selected user pending fresh proof without changing old binding or RH1', () => fixture(({ directory, files }) => {
  const snapshots = ['supporters.json', 'supporter-device-proof-bindings.json'].map(name => fs.readFileSync(files[name]));
  assert.equal(cli(directory, 'block-key-review', '--id', '0029').status, 'REVERIFY_REQUIRED');
  const plan = cli(directory, 'plan');
  assert.deepEqual(plan.records.map(row => row.status), ['REVERIFY_REQUIRED', 'READY_FOR_REVIEW']);
  assert.throws(() => review.migrationPlan(directory, '0029', issuer.publicKey, now), /review-required/);
  assert.deepEqual(['supporters.json', 'supporter-device-proof-bindings.json'].map(name => fs.readFileSync(files[name])), snapshots);
  review.recordProof(directory, proof(), issuer.publicKey, now);
  assert.equal(cli(directory, 'plan').records[0].status, 'REVIEW_KEY_MISMATCH');
}));

test('same-hardware migration requires exact typed ID, fresh receipt and exact reviewed snapshot', () => fixture(({ directory, files }) => {
  review.recordProof(directory, proof(), issuer.publicKey, now);
  const before = fs.readFileSync(files['supporter-device-proof-bindings.json']);
  const plan = review.migrationPlan(directory, '0029', issuer.publicKey, now);
  for (const id of ['', '29', '0030', '0029 ']) {
    assert.throws(() => review.migrate(directory, '0029', plan.reviewSha256, id, issuer.publicKey, now), /confirmation/);
  }
  assert.throws(() => review.migrate(directory, '0029', 'F'.repeat(64), '0029', issuer.publicKey, now), /stale/);
  assert.throws(() => review.migrationPlan(directory, '0029', issuer.publicKey, now + 900), /expired/);
  assert.deepEqual(fs.readFileSync(files['supporter-device-proof-bindings.json']), before);
}));

test('explicit rekey preserves RH1, other users, hardware and first verification, with a full old-binding backup', () => fixture(({ directory, files, bindings }) => {
  const supporters = fs.readFileSync(files['supporters.json']);
  const before = fs.readFileSync(files['supporter-device-proof-bindings.json']);
  review.recordProof(directory, proof(), issuer.publicKey, now);
  const plan = review.migrationPlan(directory, '0029', issuer.publicKey, now);
  const result = review.migrate(directory, '0029', plan.reviewSha256, '0029', issuer.publicKey, now);
  assert.equal(result.signingPerformed, false);
  assert.equal(result.licenseChanged, false);
  assert.deepEqual(fs.readFileSync(files['supporters.json']), supporters);
  assert.deepEqual(fs.readFileSync(path.join(result.backup, 'supporter-device-proof-bindings.json')), before);
  const updated = binding.readArray(files['supporter-device-proof-bindings.json']);
  assert.deepEqual(updated[1], bindings[1]);
  assert.equal(updated[0].FirstVerifiedAt, bindings[0].FirstVerifiedAt);
  assert.equal(updated[0].HardwareHash, hw);
  assert.equal(updated[0].KeyFingerprint, binding.sha256(points[1]));
  assert.equal(updated[0].PublicKey, points[1].toString('base64url'));
  assert.equal(cli(directory, 'plan').records[0].status, 'READY_FOR_REVIEW');
  assert.throws(() => review.migrate(directory, '0029', plan.reviewSha256, '0029', issuer.publicKey, now), /review-required/);
  const rows = review.applyReviews(binding.plan(binding.readArray(files['supporters.json']), updated, issuer.publicKey), directory).rows;
  const [old, certificate] = binding.issue(rows[0], issuer.privateKey, issuer.publicKey, now).trim().split('\n');
  assert.equal(binding.verifyCertificate(certificate, old, issuer.publicKey).key_fingerprint, binding.sha256(points[1]));
}));

test('different hardware is recorded but never eligible for the same-device migration', () => fixture(({ directory }) => {
  assert.equal(review.recordProof(directory, proof('F'.repeat(64)), issuer.publicKey, now).status, 'HARDWARE_MISMATCH');
  assert.equal(cli(directory, 'plan').records[0].status, 'HARDWARE_MISMATCH');
  assert.throws(() => review.migrationPlan(directory, '0029', issuer.publicKey, now), /review-required/);
}));

test('only consumed, unexpired NORMAL proof challenges can become review receipts', () => {
  for (const patch of [{ State: 'ISSUED' }, { Mode: 'DEVICE_CODE_MIGRATION' }, { ExpiresAt: now - 1 },
    { ChallengeHash: 'F'.repeat(64) }, { DeviceCode: other }]) fixture(({ directory, files, challenges }) => {
    fs.writeFileSync(files['supporter-device-proof-challenges.json'], JSON.stringify([{ ...challenges[0], ...patch }]));
    if (patch.DeviceCode) {
      // A challenge to another account cannot authorize migration of 0029.
      review.recordProof(directory, proof(), issuer.publicKey, now);
      assert.throws(() => review.migrationPlan(directory, '0029', issuer.publicKey, now), /review-required/);
    } else {
      assert.throws(() => review.recordProof(directory, proof(), issuer.publicKey, now));
      assert.equal(fs.existsSync(files[review.reviewsName]), false);
    }
  });
});

test('duplicate proof cannot renew its approval window, and receipt times outside the challenge are blocked', () => fixture(({ directory, files }) => {
  const wire = proof();
  review.recordProof(directory, wire, issuer.publicKey, now);
  const before = fs.readFileSync(files[review.reviewsName]);
  assert.equal(review.recordProof(directory, wire, issuer.publicKey, now + 30).duplicate, true);
  assert.deepEqual(fs.readFileSync(files[review.reviewsName]), before);
  const reviews = binding.readArray(files[review.reviewsName]);
  reviews[0].VerifiedAt = now + 500;
  fs.writeFileSync(files[review.reviewsName], JSON.stringify(reviews));
  assert.equal(cli(directory, 'plan').records[0].status, 'REVERIFY_REQUIRED');
}));

test('corrupt, duplicate and changed-license review records fail closed', () => fixture(({ directory, files, records }) => {
  review.recordProof(directory, proof(), issuer.publicKey, now);
  const reviews = binding.readArray(files[review.reviewsName]);
  fs.writeFileSync(files[review.reviewsName], JSON.stringify([reviews[0], reviews[0]]));
  assert.throws(() => cli(directory, 'plan'), /duplicate-review/);
  fs.writeFileSync(files[review.reviewsName], JSON.stringify([{ ...reviews[0], Proof: '{}' }]));
  assert.equal(cli(directory, 'plan').records[0].status, 'REVERIFY_REQUIRED');
  fs.writeFileSync(files[review.reviewsName], JSON.stringify(reviews));
  records[0].License = license('0029', device);
  fs.writeFileSync(files['supporters.json'], JSON.stringify(records));
  assert.equal(cli(directory, 'plan').records[0].status, 'REVERIFY_REQUIRED');
}));

test('write failure or concurrent replacement leaves old bindings intact and retains the backup', () => {
  for (const mode of ['write', 'concurrent']) fixture(({ directory, files }) => {
    review.recordProof(directory, proof(), issuer.publicKey, now);
    const filename = files['supporter-device-proof-bindings.json'];
    const before = fs.readFileSync(filename);
    const plan = review.migrationPlan(directory, '0029', issuer.publicKey, now);
    const io = { ...fs, writeFileSync(target, ...args) {
      if (mode === 'write' && typeof target === 'number') throw new Error('injected-write-failure');
      fs.writeFileSync(target, ...args);
      if (mode === 'concurrent' && typeof target === 'number') fs.writeFileSync(filename, before.toString() + '\n');
    } };
    assert.throws(() => review.migrate(directory, '0029', plan.reviewSha256, '0029', issuer.publicKey, now, io),
      /injected-write-failure|database-changed-before-replace/);
    assert.equal(fs.readFileSync(filename, 'utf8'), before.toString() + (mode === 'concurrent' ? '\n' : ''));
    assert.equal(fs.readdirSync(directory).some(name => name.endsWith('.tmp')), false);
    assert.equal(fs.readdirSync(path.join(directory, 'binding-backups')).length, 2);
  });
});

test('proof before initial RH1 issuance remains supported without automatically issuing a credential', () => fixture(({ directory, files }) => {
  fs.writeFileSync(files['supporters.json'], '[]');
  assert.equal(review.recordProof(directory, proof(hw, 0), issuer.publicKey, now).status, 'UNASSIGNED_PROOF');
  assert.equal(fs.existsSync(files[review.reviewsName]), false);
}));
