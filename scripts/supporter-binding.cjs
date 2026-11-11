'use strict';

const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');

const issuerPoint = 'BCmHM/nGP4wG1hJ4mOedvUeRutsHgL+qGAAWpjTO/bD0qY4QraFv/hzsQTV0jxx7fod1yu9iAC0LHiVxW39cRBg=';
const bindingDomain = Buffer.from('DopamineRH-RHB1-Sign-v1\0', 'ascii');
const codePattern = /^(?:[0-9A-F]{4}-){7}[0-9A-F]{4}$/;
const hashPattern = /^[0-9A-F]{64}$/;
const sha256 = value => crypto.createHash('sha256').update(value).digest('hex').toUpperCase();

function requireValue(condition, message) {
  if (!condition) throw new Error(message);
}

function publicKeyFromPoint(point) {
  requireValue(Buffer.isBuffer(point) && point.length === 65 && point[0] === 4, 'invalid-device-public-key');
  return crypto.createPublicKey({ format: 'jwk', key: {
    kty: 'EC', crv: 'P-256',
    x: point.subarray(1, 33).toString('base64url'),
    y: point.subarray(33).toString('base64url'),
  } });
}

const issuerPublicKey = publicKeyFromPoint(Buffer.from(issuerPoint, 'base64'));

function decode(value) {
  requireValue(typeof value === 'string' && /^[A-Za-z0-9_-]+$/.test(value), 'invalid-base64url');
  const bytes = Buffer.from(value, 'base64url');
  requireValue(bytes.toString('base64url') === value, 'noncanonical-base64url');
  return bytes;
}

function verifyWire(wire, prefix, domain, publicKey) {
  requireValue(typeof wire === 'string' && Buffer.byteLength(wire) <= 4096, 'invalid-wire-size');
  const parts = wire.split('.');
  requireValue(parts.length === 3 && parts[0] === prefix, 'invalid-wire-format');
  const payload = decode(parts[1]);
  const signature = decode(parts[2]);
  requireValue(crypto.verify('sha256', Buffer.concat([domain, payload]), publicKey, signature), 'invalid-issuer-signature');
  const info = JSON.parse(payload.toString('utf8'));
  requireValue(info && typeof info === 'object' && !Array.isArray(info), 'invalid-payload');
  return info;
}

function verifyLicense(license, publicKey = issuerPublicKey) {
  const info = verifyWire(license, 'RH1', Buffer.alloc(0), publicKey);
  requireValue(info.v === 1 && info.product === 'DopamineRH', 'invalid-license-product');
  requireValue(typeof info.sid === 'string' && /^\d{1,8}$/.test(info.sid), 'invalid-supporter-id');
  requireValue(typeof info.device === 'string' && codePattern.test(info.device), 'invalid-device-code');
  requireValue(Array.isArray(info.ent) && info.ent.includes('custom_glass'), 'missing-entitlement');
  return info;
}

function validateBinding(binding) {
  requireValue(binding && codePattern.test(binding.DeviceCode), 'invalid-binding-device');
  requireValue(typeof binding.HardwareHash === 'string' && hashPattern.test(binding.HardwareHash), 'invalid-hardware-hash');
  requireValue(typeof binding.KeyFingerprint === 'string' && hashPattern.test(binding.KeyFingerprint), 'invalid-key-fingerprint');
  const point = decode(binding.PublicKey);
  publicKeyFromPoint(point);
  requireValue(sha256(point) === binding.KeyFingerprint, 'binding-key-fingerprint-mismatch');
}

function plan(records, bindings, publicKey = issuerPublicKey) {
  requireValue(Array.isArray(records) && Array.isArray(bindings), 'databases-must-be-arrays');
  const byDevice = new Map();
  for (const binding of bindings) {
    validateBinding(binding);
    requireValue(!byDevice.has(binding.DeviceCode), 'duplicate-binding-device');
    byDevice.set(binding.DeviceCode, binding);
  }
  const ids = new Set();
  const devices = new Set();
  const rows = records.map(record => {
    requireValue(record && typeof record.License === 'string', 'record-license-missing');
    const license = record.License.trim();
    const info = verifyLicense(license, publicKey);
    requireValue(info.sid === record.SupporterId && info.device === record.DeviceCode, 'record-license-identity-mismatch');
    requireValue(!ids.has(info.sid) && !devices.has(info.device), 'duplicate-supporter-or-device');
    ids.add(info.sid);
    devices.add(info.device);
    return { id: info.sid, license, binding: byDevice.get(info.device) || null };
  });
  return { rows, orphanBindings: bindings.filter(binding => !devices.has(binding.DeviceCode)).length };
}

function verifyCertificate(certificate, license, publicKey = issuerPublicKey) {
  const info = verifyWire(certificate, 'RHB1', bindingDomain, publicKey);
  const old = verifyLicense(license, publicKey);
  requireValue(Object.keys(info).sort().join(',') ===
    'device,hardware_hash,hardware_protocol,issued_at,key_fingerprint,license_sha256,product,sid,v', 'invalid-binding-fields');
  requireValue(info.v === 1 && info.product === 'DopamineRH' && info.hardware_protocol === 'rh-hw-v1', 'invalid-binding-protocol');
  requireValue(info.sid === old.sid && info.device === old.device, 'binding-license-identity-mismatch');
  requireValue(info.license_sha256 === sha256(license), 'binding-license-digest-mismatch');
  requireValue(hashPattern.test(info.hardware_hash) && hashPattern.test(info.key_fingerprint), 'invalid-binding-hashes');
  requireValue(Number.isSafeInteger(info.issued_at) && info.issued_at > 0, 'invalid-binding-time');
  return info;
}

function issue(row, privateKey, publicKey = issuerPublicKey, now = Math.floor(Date.now() / 1000)) {
  requireValue(row.binding, 'legacy-unbound-needs-reviewed-device-proof');
  validateBinding(row.binding);
  const old = verifyLicense(row.license, publicKey);
  requireValue(row.id === old.sid && row.binding.DeviceCode === old.device, 'record-binding-identity-mismatch');
  requireValue(crypto.createPublicKey(privateKey).export({ format: 'der', type: 'spki' }).equals(
    publicKey.export({ format: 'der', type: 'spki' })), 'wrong-issuer-private-key');
  const payload = Buffer.from(JSON.stringify({
    v: 1, product: 'DopamineRH', sid: old.sid, device: old.device,
    license_sha256: sha256(row.license), hardware_protocol: 'rh-hw-v1',
    hardware_hash: row.binding.HardwareHash, key_fingerprint: row.binding.KeyFingerprint,
    issued_at: now,
  }));
  const signature = crypto.sign('sha256', Buffer.concat([bindingDomain, payload]), privateKey);
  const certificate = `RHB1.${payload.toString('base64url')}.${signature.toString('base64url')}`;
  verifyCertificate(certificate, row.license, publicKey);
  return `${row.license}\n${certificate}\n`;
}

function readArray(filename) {
  const bytes = fs.readFileSync(filename);
  requireValue(bytes.length <= 16 * 1024 * 1024, 'database-too-large');
  const parsed = JSON.parse(bytes.toString('utf8').replace(/^\uFEFF/, ''));
  requireValue(Array.isArray(parsed), 'database-must-be-array');
  return parsed;
}

function main(argv) {
  const command = argv.shift();
  requireValue(['plan', 'issue', 'issue-all'].includes(command),
    'Usage: node supporter-binding.cjs plan|issue|issue-all --issuer-dir DIR [--id ID --out FILE | --out-dir DIR]');
  const options = {};
  while (argv.length) {
    const key = argv.shift();
    const value = argv.shift();
    requireValue(['--issuer-dir', '--id', '--out', '--out-dir'].includes(key) && value && !options[key], 'invalid-or-duplicate-option');
    options[key] = value;
  }
  requireValue(options['--issuer-dir'], 'issuer-directory-required');
  const directory = path.resolve(options['--issuer-dir']);
  const result = plan(readArray(path.join(directory, 'supporters.json')),
    readArray(path.join(directory, 'supporter-device-proof-bindings.json')));
  const eligible = result.rows.filter(row => row.binding);
  if (command === 'plan') {
    requireValue(Object.keys(options).length === 1, 'plan-does-not-accept-output-options');
    console.log(JSON.stringify({ total: result.rows.length, eligible: eligible.length,
      needsProof: result.rows.length - eligible.length, orphanBindings: result.orphanBindings,
      records: result.rows.map(row => ({ id: row.id, status: row.binding ? 'READY_FOR_REVIEW' : 'LEGACY_UNBOUND' })),
    }, null, 2));
    return;
  }
  let selected;
  if (command === 'issue') {
    requireValue(options['--id'] && options['--out'] && !options['--out-dir'], 'issue-requires-id-and-out');
    selected = result.rows.filter(row => row.id === options['--id']);
    requireValue(selected.length === 1 && selected[0].binding, 'selected-supporter-missing-or-unbound');
  } else {
    requireValue(options['--out-dir'] && !options['--id'] && !options['--out'], 'issue-all-requires-out-dir');
    selected = eligible;
    requireValue(selected.length > 0, 'no-reviewed-bindings');
  }
  // Only explicit issue commands open the private key. Never update the source databases.
  const privateKey = crypto.createPrivateKey(fs.readFileSync(path.join(directory, 'DopamineRH-supporter-private.pem')));
  const outputs = selected.map(row => ({
    filename: command === 'issue' ? path.resolve(options['--out']) :
      path.resolve(options['--out-dir'], `supporter-${row.id}-bound.txt`),
    content: issue(row, privateKey),
  }));
  const sourceFiles = ['supporters.json', 'supporters.backup.json', 'supporter-device-proof-bindings.json',
    'supporter-device-proof-challenges.json', 'DopamineRH-supporter-private.pem'];
  const excluded = new Set(sourceFiles.map(name => path.join(directory, name).toLowerCase()));
  for (const output of outputs) {
    requireValue(!excluded.has(output.filename.toLowerCase()) && !fs.existsSync(output.filename), 'output-exists-or-is-source-data');
  }
  for (const output of outputs) {
    fs.mkdirSync(path.dirname(output.filename), { recursive: true });
    fs.writeFileSync(output.filename, output.content, { flag: 'wx', mode: 0o600 });
  }
  console.log(JSON.stringify({ issued: outputs.length, needsProof: result.rows.length - eligible.length,
    orphanBindings: result.orphanBindings, sourceDatabasesChanged: false }));
}

module.exports = { sha256, publicKeyFromPoint, issuerPublicKey, bindingDomain, plan, issue, verifyLicense, verifyCertificate, main };
if (require.main === module) {
  try { main(process.argv.slice(2)); }
  catch (error) { console.error(`Binding operation failed: ${error.message}`); process.exitCode = 1; }
}
