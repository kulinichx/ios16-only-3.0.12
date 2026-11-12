const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const crypto = require('node:crypto');
const test = require('node:test');
const { execFileSync } = require('node:child_process');
const binding = require('../scripts/supporter-binding.cjs');

const root = path.resolve(__dirname, '..');
const read = relative => fs.readFileSync(path.join(root, relative), 'utf8');
const app = read('Application/Dopamine/UI/DOSupporterBinding.h');
const licenseSource = read('Application/Dopamine/UI/DOSupporterLicense.h');
const device = '0123-4567-89AB-CDEF-0123-4567-89AB-CDEF';
const issuer = crypto.generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
const deviceKey = crypto.generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
const jwk = deviceKey.publicKey.export({ format: 'jwk' });
const point = Buffer.concat([Buffer.from([4]), Buffer.from(jwk.x, 'base64url'), Buffer.from(jwk.y, 'base64url')]);
const hardwareHash = binding.sha256('test-hardware-only');

function signedWire(prefix, info, key = issuer.privateKey, domain = Buffer.alloc(0)) {
  const payload = Buffer.from(JSON.stringify(info));
  const signature = crypto.sign('sha256', Buffer.concat([domain, payload]), key);
  return `${prefix}.${payload.toString('base64url')}.${signature.toString('base64url')}`;
}

function fixture() {
  const license = signedWire('RH1', { v: 1, product: 'DopamineRH', sid: '0027', device, ent: ['custom_glass'] });
  const proof = { DeviceCode: device, HardwareHash: hardwareHash,
    KeyFingerprint: binding.sha256(point), PublicKey: point.toString('base64url') };
  const records = [{ SupporterId: '0027', DeviceCode: device, License: license }];
  const row = binding.plan(records, [proof], issuer.publicKey).rows[0];
  return { license, proof, records, row };
}

function body(source, name) {
  const signature = new RegExp(`(?:static inline|static) [^{;]+\\b${name}\\([^;]*?\\)\\s*\\{`, 'm');
  const match = signature.exec(source);
  assert.ok(match, name);
  let depth = 1;
  for (let i = match.index + match[0].length; i < source.length; i++) {
    if (source[i] === '{') depth++;
    if (source[i] === '}' && --depth === 0) return source.slice(match.index, i + 1);
  }
  assert.fail(`Unclosed ${name}`);
}

test('RHB1 issuance binds the exact existing RH1, device hardware and key without changing its supporter ID', () => {
  const { row, license, proof } = fixture();
  const output = binding.issue(row, issuer.privateKey, issuer.publicKey);
  const [old, certificate] = output.trim().split('\n');
  assert.equal(old, license);
  const info = binding.verifyCertificate(certificate, old, issuer.publicKey);
  assert.equal(info.sid, '0027');
  assert.equal(info.device, device);
  assert.equal(info.hardware_hash, proof.HardwareHash);
  assert.equal(info.key_fingerprint, proof.KeyFingerprint);
  assert.equal(info.license_sha256, binding.sha256(license));
});

test('binding issuance refuses unbound, duplicate, corrupt and mismatched records', () => {
  const { row, records, proof } = fixture();
  const plan = binding.plan(records, [], issuer.publicKey);
  assert.equal(plan.rows[0].binding, null);
  assert.throws(() => binding.issue(plan.rows[0], issuer.privateKey, issuer.publicKey), /unbound/);
  assert.throws(() => binding.plan(records, [proof, proof], issuer.publicKey), /duplicate/);
  assert.throws(() => binding.plan(records, [{ ...proof, KeyFingerprint: 'A'.repeat(64) }], issuer.publicKey), /fingerprint/);
  assert.throws(() => binding.plan([{ ...records[0], SupporterId: '0028' }], [proof], issuer.publicKey), /identity/);
  const stranger = crypto.generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
  assert.throws(() => binding.issue(row, stranger.privateKey, issuer.publicKey), /wrong-issuer/);
});

test('binding verification rejects altered payloads, an unrelated issuer, replay onto another license and wrong signing domain', () => {
  const { row, license } = fixture();
  const certificate = binding.issue(row, issuer.privateKey, issuer.publicKey).trim().split('\n')[1];
  const info = binding.verifyCertificate(certificate, license, issuer.publicKey);
  const parts = certificate.split('.');
  parts[1] = Buffer.from(JSON.stringify({ ...info, device: 'FFFF-FFFF-FFFF-FFFF-FFFF-FFFF-FFFF-FFFF' })).toString('base64url');
  assert.throws(() => binding.verifyCertificate(parts.join('.'), license, issuer.publicKey), /signature/);
  const stranger = crypto.generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
  assert.throws(() => binding.verifyCertificate(certificate, license, stranger.publicKey), /signature/);
  const differentLicense = signedWire('RH1', { v: 1, product: 'DopamineRH', sid: '0027', device, ent: ['custom_glass'], extra: true });
  assert.throws(() => binding.verifyCertificate(certificate, differentLicense, issuer.publicKey), /digest/);
  assert.throws(() => binding.verifyCertificate(signedWire('RHB1', info), license, issuer.publicKey), /signature/);
  assert.throws(() => binding.verifyCertificate(signedWire('RHB1', { ...info, extra: true }, issuer.privateKey,
    binding.bindingDomain), license, issuer.publicKey), /fields/);
});

test('issuer planning opens only records and bindings, never the private key or challenge store', () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'rh-binding-plan-'));
  try {
    fs.writeFileSync(path.join(directory, 'supporters.json'), '[]');
    fs.writeFileSync(path.join(directory, 'supporter-device-proof-bindings.json'), '[]');
    const result = JSON.parse(execFileSync(process.execPath, [path.join(root, 'scripts/supporter-binding.cjs'),
      'plan', '--issuer-dir', directory], { encoding: 'utf8' }));
    assert.equal(result.total, 0);
    assert.deepEqual(fs.readdirSync(directory).sort(), ['supporter-device-proof-bindings.json', 'supporters.json']);
  } finally { fs.rmSync(directory, { recursive: true, force: true }); }
});

function captureMain(argv) {
  const original = console.log;
  let output;
  console.log = value => { output = value; };
  try { binding.main([...argv], issuer.publicKey); return JSON.parse(output); }
  finally { console.log = original; }
}

function issuerFixture(run) {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'rh-binding-issuer-'));
  const { records, proof } = fixture();
  const recordsFile = path.join(directory, 'supporters.json');
  const bindingsFile = path.join(directory, 'supporter-device-proof-bindings.json');
  fs.writeFileSync(recordsFile, JSON.stringify(records));
  fs.writeFileSync(bindingsFile, JSON.stringify([proof]));
  try { run({ directory, recordsFile, bindingsFile, records, proof }); }
  finally { fs.rmSync(directory, { recursive: true, force: true }); }
}

test('review digests bind selected signed licenses and exact device bindings, independent of record order', () => {
  const { row } = fixture();
  const digest = binding.reviewSha256([row]);
  assert.match(digest, /^[0-9A-F]{64}$/);
  assert.notEqual(binding.reviewSha256([{ ...row, binding: null }]), digest);
  assert.notEqual(binding.reviewSha256([{ ...row, binding: { ...row.binding, HardwareHash: 'B'.repeat(64) } }]), digest);
  assert.notEqual(binding.reviewSha256([{ ...row, license: row.license + 'x' }]), digest);
  const other = { ...row, id: '0028' };
  assert.equal(binding.reviewSha256([row, other]), binding.reviewSha256([other, row]));
});

test('issuance requires the reviewed snapshot and rejects stale bindings before opening any private key', () => {
  issuerFixture(({ directory, bindingsFile, proof }) => {
    const plan = captureMain(['plan', '--issuer-dir', directory]);
    const argv = ['issue', '--issuer-dir', directory, '--id', '0027', '--out', path.join(directory, 'out.txt')];
    assert.throws(() => captureMain([...argv]), /review-sha256-required/);
    assert.throws(() => captureMain([...argv, '--review-sha256', 'A'.repeat(64)]), /review-stale/);
    fs.writeFileSync(bindingsFile, JSON.stringify([{ ...proof, HardwareHash: 'B'.repeat(64) }]));
    assert.throws(() => captureMain([...argv, '--review-sha256', plan.records[0].reviewSha256]), /review-stale/);
    assert.equal(fs.existsSync(path.join(directory, 'out.txt')), false);
  });
});

test('existing and source outputs are rejected before reading the issuer key', () => {
  issuerFixture(({ directory, recordsFile }) => {
    const plan = captureMain(['plan', '--issuer-dir', directory]);
    const filename = path.join(directory, 'existing.txt');
    fs.writeFileSync(filename, 'keep');
    for (const output of [filename, recordsFile, path.join(directory, 'DopamineRH-supporter-private.pem')])
      assert.throws(() => captureMain(['issue', '--issuer-dir', directory, '--id', '0027', '--out', output,
        '--review-sha256', plan.records[0].reviewSha256]), /output-exists-or-is-source-data/);
    assert.equal(fs.readFileSync(filename, 'utf8'), 'keep');
  });
});

test('oversized databases are refused without parsing or opening an issuer key', () => {
  issuerFixture(({ directory, recordsFile }) => {
    fs.truncateSync(recordsFile, 16 * 1024 * 1024 + 1);
    assert.throws(() => captureMain(['plan', '--issuer-dir', directory]), /database-too-large/);
  });
});

test('reviewed single and batch issuance use only disposable issuer data and leave databases unchanged', () => {
  issuerFixture(({ directory, recordsFile, bindingsFile, records, proof }) => {
    const otherDevice = 'FFFF-FFFF-FFFF-FFFF-FFFF-FFFF-FFFF-FFFF';
    const otherLicense = signedWire('RH1', { v: 1, product: 'DopamineRH', sid: '0028', device: otherDevice, ent: ['custom_glass'] });
    fs.writeFileSync(recordsFile, JSON.stringify([...records, { SupporterId: '0028', DeviceCode: otherDevice, License: otherLicense }]));
    fs.writeFileSync(bindingsFile, JSON.stringify([proof, { ...proof, DeviceCode: otherDevice }]));
    const before = [fs.readFileSync(recordsFile), fs.readFileSync(bindingsFile)];
    fs.writeFileSync(path.join(directory, 'DopamineRH-supporter-private.pem'),
      issuer.privateKey.export({ type: 'pkcs8', format: 'pem' }));
    const plan = captureMain(['plan', '--issuer-dir', directory]);
    const single = path.join(directory, 'single', 'bound.txt');
    const batch = path.join(directory, 'batch');
    for (const argv of [
      ['issue', '--issuer-dir', directory, '--id', '0027', '--out', single, '--review-sha256', plan.records[0].reviewSha256],
      ['issue-all', '--issuer-dir', directory, '--out-dir', batch, '--review-sha256', plan.reviewSha256],
    ]) {
      const result = captureMain(argv);
      assert.equal(result.issued, argv[0] === 'issue' ? 1 : 2);
      assert.equal(result.sourceDatabasesChanged, false);
      assert.deepEqual(result.cleanupWarnings, []);
    }
    for (const filename of [single, path.join(batch, 'supporter-0027-bound.txt'), path.join(batch, 'supporter-0028-bound.txt')]) {
      const [license, certificate] = fs.readFileSync(filename, 'utf8').trim().split('\n');
      binding.verifyCertificate(certificate, license, issuer.publicKey);
      if (process.platform !== 'win32') assert.equal(fs.statSync(filename).mode & 0o777, 0o600);
    }
    assert.deepEqual(fs.readdirSync(path.dirname(single)), ['bound.txt']);
    assert.deepEqual(fs.readdirSync(batch).sort(), ['supporter-0027-bound.txt', 'supporter-0028-bound.txt']);
    assert.deepEqual([fs.readFileSync(recordsFile), fs.readFileSync(bindingsFile)], before);
  });
});

function publicationFixture(run) {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'rh-binding-publish-'));
  const outputs = ['one', 'two'].map(name => ({ filename: path.join(directory, `${name}.txt`), content: name }));
  try { run(directory, outputs); }
  finally { fs.rmSync(directory, { recursive: true, force: true }); }
}

test('publication writes and syncs all files before exposing outputs; write failures leave no partial batch', () => {
  publicationFixture((directory, outputs) => {
    let writes = 0;
    const io = { ...fs, writeFileSync(...args) {
      assert.equal(outputs.some(output => fs.existsSync(output.filename)), false);
      fs.writeFileSync(...args);
      if (++writes === 2) throw new Error('injected-write-failure');
    } };
    assert.throws(() => binding.publishOutputs(outputs, io), /injected-write-failure/);
    assert.deepEqual(fs.readdirSync(directory), []);
  });
});

test('publication failure rolls back its own outputs without overwriting a concurrent file', () => {
  publicationFixture((directory, outputs) => {
    let links = 0;
    const io = { ...fs, linkSync(source, target) {
      if (++links === 2) fs.writeFileSync(target, 'concurrent-user-file', { flag: 'wx' });
      fs.linkSync(source, target);
    } };
    assert.throws(() => binding.publishOutputs(outputs, io), /EEXIST/);
    assert.deepEqual(fs.readdirSync(directory), ['two.txt']);
    assert.equal(fs.readFileSync(outputs[1].filename, 'utf8'), 'concurrent-user-file');
  });
});

test('publication refuses pre-existing targets including dangling links and unsupported hard-link filesystems', () => {
  publicationFixture((directory, outputs) => {
    fs.writeFileSync(outputs[0].filename, 'keep');
    assert.throws(() => binding.publishOutputs(outputs), /output-already-exists/);
    assert.equal(fs.readFileSync(outputs[0].filename, 'utf8'), 'keep');
    fs.unlinkSync(outputs[0].filename);
    if (process.platform !== 'win32') {
      fs.symlinkSync(path.join(directory, 'missing'), outputs[0].filename);
      assert.throws(() => binding.publishOutputs(outputs), /output-already-exists/);
      assert.equal(fs.lstatSync(outputs[0].filename).isSymbolicLink(), true);
      fs.unlinkSync(outputs[0].filename);
    }
    const io = { ...fs, linkSync() { throw new Error('injected-links-unsupported'); } };
    assert.throws(() => binding.publishOutputs(outputs, io), /injected-links-unsupported/);
    assert.deepEqual(fs.readdirSync(directory), []);
  });
});

test('rollback preserves replaced outputs and reports incomplete cleanup rather than claiming success', () => {
  publicationFixture((directory, outputs) => {
    let links = 0;
    const io = { ...fs, linkSync(source, target) {
      if (++links === 2) {
        fs.unlinkSync(outputs[0].filename);
        fs.writeFileSync(outputs[0].filename, 'replacement', { flag: 'wx' });
        throw new Error('injected-publish-failure');
      }
      fs.linkSync(source, target);
    } };
    assert.throws(() => binding.publishOutputs(outputs, io), /injected-publish-failure; cleanup-incomplete:/);
    assert.deepEqual(fs.readdirSync(directory), ['one.txt']);
    assert.equal(fs.readFileSync(outputs[0].filename, 'utf8'), 'replacement');
  });
});

test('successful publication reports staging cleanup warnings without inviting duplicate issuance', () => {
  publicationFixture((directory, outputs) => {
    const io = { ...fs, rmdirSync() { throw new Error('injected-cleanup-failure'); } };
    const warnings = binding.publishOutputs(outputs, io);
    assert.equal(warnings.length, 1);
    assert.equal(path.dirname(warnings[0]), directory);
    for (const output of outputs) assert.equal(fs.readFileSync(output.filename, 'utf8'), output.content);
  });
});

test('migration UI passes review digests, clears failed previews and distinguishes clipboard failure from issuance failure', () => {
  const ui = read('scripts/SupporterBindingTool.ps1');
  assert.equal((ui.match(/'--review-sha256'/g) || []).length, 2);
  assert.ok(ui.indexOf('$grid.Rows.Clear()') < ui.indexOf("$plan = Invoke-BindingHelper @('plan'"));
  assert.match(ui, /review-stale-reload-plan/);
  assert.match(ui, /catch \{ \$message \+=/);
  assert.match(ui, /cleanupWarnings/);
});

test('Windows migration preview smoke test uses empty temporary databases and never opens an issuer key', {
  skip: process.platform !== 'win32' ? 'Requires Windows Forms; macOS runs the native app binding tests instead.' : false,
}, () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'rh-binding-ui-'));
  try {
    fs.writeFileSync(path.join(directory, 'supporters.json'), '[]');
    fs.writeFileSync(path.join(directory, 'supporter-device-proof-bindings.json'), '[]');
    const result = JSON.parse(execFileSync('powershell.exe', ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
      '-File', path.join(root, 'scripts/SupporterBindingTool.ps1'), '-IssuerDirectory', directory, '-SmokeTest'],
    { encoding: 'utf8', timeout: 30000 }));
    assert.equal(result.Rows, 0);
    assert.equal(result.CanIssue, false);
    assert.equal(result.CanBatch, false);
    assert.deepEqual(fs.readdirSync(directory).sort(), ['supporter-device-proof-bindings.json', 'supporters.json']);
  } finally { fs.rmSync(directory, { recursive: true, force: true }); }
});

test('Windows VBS launcher displays an actual visible main window and propagates smoke-test failures', {
  skip: process.platform !== 'win32' ? 'Requires the Windows script host and an interactive desktop.' : false,
}, () => {
  const launcher = read('scripts/SupporterBindingTool.vbs');
  assert.match(launcher, /shell\.Run\(command, 1, True\)/);
  assert.match(launcher, /-WindowStyle Hidden/);
  assert.match(launcher, /WScript\.Quit status/);
  execFileSync('cscript.exe', ['//Nologo', path.join(root, 'scripts/SupporterBindingTool.vbs'), '--smoke-test'],
    { encoding: 'utf8', timeout: 30000 });
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'rh-binding-launcher-'));
  try {
    const filename = path.join(directory, 'SupporterBindingTool.vbs');
    fs.writeFileSync(filename, launcher);
    fs.writeFileSync(path.join(directory, 'SupporterBindingTool.ps1'),
      'param([switch]$SmokeTest, [switch]$VerifyVisible)\nexit 23\n');
    assert.throws(() => execFileSync('cscript.exe', ['//Nologo', filename, '--smoke-test'],
      { encoding: 'utf8', timeout: 30000 }), error => error.status === 23);
  } finally { fs.rmSync(directory, { recursive: true, force: true }); }
});

test('App validates issuer signature before payload parsing, hardware and fresh device-key possession', () => {
  const parser = body(app, 'DORHSupporterBindingCertificateInfo');
  assert.ok(parser.indexOf('SecKeyVerifySignature(') < parser.indexOf('JSONObjectWithData:payload'));
  assert.match(parser, /DopamineRH-RHB1-Sign-v1/);
  const verify = body(app, 'DORHSupporterVerifyBoundLicense');
  assert.match(verify, /DORHSupporterVerifyLicenseCodeForDevice\(license, binding\[@"device"\]/);
  assert.match(verify, /hardware\[@"hardware_hash"\]/);
  assert.match(verify, /DORHSupporterProveBoundDeviceKey/);
  const proof = body(app, 'DORHSupporterProveBoundDeviceKey');
  assert.match(proof, /SecRandomCopyBytes/);
  assert.match(proof, /DORHSupporterSignWithDeviceKey/);
  assert.match(proof, /DORHSupporterVerifyDeviceKeySignature/);
  const lookup = body(app, 'DORHSupporterCopyExistingDevicePrivateKey');
  assert.match(lookup, /SecItemCopyMatching/);
  assert.doesNotMatch(lookup, /SecKeyCreateRandomKey|SecItemDelete/);
  assert.match(lookup, /DORHSupporterDeviceKeyIsSecureEnclaveP256PrivateKey/);
});

test('binding activation is atomic, deletion preserves the binding-required flag and malformed bound state cannot fall back', () => {
  const store = body(licenseSource, 'DORHSupporterStoreActivationText');
  assert.ok(store.indexOf('DORHSupporterVerifyBoundLicense(') < store.indexOf('DORHSupporterWritePersistentState(state)'));
  assert.ok(store.indexOf('DORHSupporterWritePersistentState(state)') < store.indexOf('setObject:license'));
  assert.match(store, /state\[DORHSupporterBindingRequiredKey\] = @YES/);
  const remove = body(licenseSource, 'DORHSupporterRemoveLicense');
  assert.match(remove, /removeObjectForKey:DORHSupporterBindingCertificateKey/);
  assert.doesNotMatch(remove, /removeObjectForKey:DORHSupporterBindingRequiredKey/);
  const verify = body(licenseSource, 'DORHSupporterVerifyLicenseCode');
  assert.ok(verify.indexOf('DORHSupporterVerifyBoundLicense') < verify.indexOf('DORHSupporterDeviceCode()'));
  assert.match(verify, /if \(DORHSupporterBindingIsRequired\(\)\)/);
  assert.match(app, /#define DORH_SUPPORTER_REQUIRE_BINDING 0/);
  const required = body(app, 'DORHSupporterBindingIsRequired');
  assert.match(required, /state\[DORHSupporterBindingCertificateKey\] != nil/);
});

test('native Security verifies production binding parser and device-possession code using mock hardware and disposable software keys', {
  skip: process.platform !== 'darwin' ? 'Requires macOS Foundation/Security; not a Secure Enclave device test.' : false,
}, () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'rh-binding-native-'));
  try {
    const helperNames = ['DORHSupporterLicenseError', 'DORHSupporterBase64URLToBase64', 'DORHSupporterDecodeBase64URL',
      'DORHSupporterIsUppercaseHexString', 'DORHSupporterCopyDevicePublicKeyData',
      'DORHSupporterDeviceKeyFingerprint', 'DORHSupporterSignWithDeviceKey',
      'DORHSupporterVerifyDeviceKeySignature', 'DORHSupporterVerifyLicenseCodeForDevice'];
    const issuerJwk = issuer.publicKey.export({ format: 'jwk' });
    const issuerData = Buffer.concat([Buffer.from([4]), Buffer.from(issuerJwk.x, 'base64url'), Buffer.from(issuerJwk.y, 'base64url')]);
    const source = `#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <CommonCrypto/CommonDigest.h>
static NSString * const DORHSupporterLicenseErrorDomain = @"BindingTest";
static NSString * const DORHSupporterDeviceKeyTag = @"test-only";
static NSString *scenario;
static SecKeyRef devicePrivate;
static inline SecKeyRef DORHSupporterCreatePublicKey(void);
static NSDictionary *DORHSupporterReadPersistentState(void) { return @{}; }
${helperNames.map(name => body(licenseSource, name)).join('\n')}
static inline SecKeyRef DORHSupporterCreatePublicKey(void) {
  NSData *point = [[NSData alloc] initWithBase64EncodedString:@"${issuerData.toString('base64')}" options:0];
  return SecKeyCreateWithData((__bridge CFDataRef)point, (__bridge CFDictionaryRef)@{
    (__bridge id)kSecAttrKeyType:(__bridge id)kSecAttrKeyTypeECSECPrimeRandom,
    (__bridge id)kSecAttrKeyClass:(__bridge id)kSecAttrKeyClassPublic,
    (__bridge id)kSecAttrKeySizeInBits:@256}, NULL);
}
static inline NSDictionary *DORHSupporterHardwareIdentityProbe(void) {
  return @{@"available":@YES, @"algorithm":@"rh-hw-v1", @"hardware_hash":
    [scenario isEqual:@"hardware-mismatch"] ? @"${'F'.repeat(64)}" : @"${hardwareHash}"};
}
static inline BOOL DORHSupporterDeviceKeyIsSecureEnclaveP256PrivateKey(SecKeyRef key) { return key != NULL; }
static OSStatus testLookup(CFDictionaryRef query, CFTypeRef *result) {
  if ([scenario isEqual:@"missing-key"]) return errSecItemNotFound;
  *result = CFRetain(devicePrivate); return errSecSuccess;
}
#define SecItemCopyMatching testLookup
${app}
#undef SecItemCopyMatching
int main(int argc, char **argv) { @autoreleasepool {
  scenario = [NSString stringWithUTF8String:argv[1]];
  NSDictionary *attributes = @{(__bridge id)kSecAttrKeyType:(__bridge id)kSecAttrKeyTypeECSECPrimeRandom,
    (__bridge id)kSecAttrKeySizeInBits:@256};
  if ([scenario isEqual:@"keygen"]) {
    SecKeyRef key = SecKeyCreateRandomKey((__bridge CFDictionaryRef)attributes, NULL);
    if (!key) return 10;
    CFDataRef bytes = SecKeyCopyExternalRepresentation(key, NULL);
    if (!bytes) return 11;
    puts([[(__bridge NSData *)bytes base64EncodedStringWithOptions:0] UTF8String]);
    CFRelease(bytes); CFRelease(key); return 0;
  }
  NSData *raw = [[NSData alloc] initWithBase64EncodedString:[NSString stringWithUTF8String:argv[2]] options:0];
  NSMutableDictionary *privateAttributes = [attributes mutableCopy];
  privateAttributes[(__bridge id)kSecAttrKeyClass] = (__bridge id)kSecAttrKeyClassPrivate;
  devicePrivate = SecKeyCreateWithData((__bridge CFDataRef)raw, (__bridge CFDictionaryRef)privateAttributes, NULL);
  if (!devicePrivate) return 12;
  if ([scenario isEqual:@"key-mismatch"]) {
    CFRelease(devicePrivate); devicePrivate = SecKeyCreateRandomKey((__bridge CFDictionaryRef)attributes, NULL);
  }
  NSError *error = nil;
  NSString *license = [NSString stringWithUTF8String:argv[3]];
  NSString *certificate = [NSString stringWithUTF8String:argv[4]];
  NSDictionary *info = DORHSupporterVerifyBoundLicense(license, certificate, &error);
  CFRelease(devicePrivate);
  BOOL expected = [scenario isEqual:@"valid"];
  return ((info != nil) == expected) ? 0 : 13;
} }
`;
    const file = path.join(directory, 'binding.m');
    const binary = path.join(directory, 'binding-test');
    fs.writeFileSync(file, source);
    execFileSync('xcrun', ['clang', '-fobjc-arc', '-Wno-deprecated-declarations', '-framework', 'Foundation', '-framework', 'Security', file, '-o', binary]);
    const keyData = execFileSync(binary, ['keygen'], { encoding: 'utf8' }).trim();
    const raw = Buffer.from(keyData, 'base64');
    assert.equal(raw.length, 97, 'P-256 X9.63 private representation');
    const { records, proof } = fixture();
    const nativePoint = raw.subarray(0, 65);
    const nativeProof = { ...proof, PublicKey: nativePoint.toString('base64url'), KeyFingerprint: binding.sha256(nativePoint) };
    const row = binding.plan(records, [nativeProof], issuer.publicKey).rows[0];
    const [license, certificate] = binding.issue(row, issuer.privateKey, issuer.publicKey).trim().split('\n');
    for (const scenario of ['valid', 'hardware-mismatch', 'key-mismatch', 'missing-key'])
      execFileSync(binary, [scenario, keyData, license, certificate]);
    execFileSync(binary, ['tampered', keyData, license, certificate.slice(0, -2)]);
    const otherLicense = signedWire('RH1', { v: 1, product: 'DopamineRH', sid: '0028', device, ent: ['custom_glass'] });
    execFileSync(binary, ['wrong-license', keyData, otherLicense, certificate]);
  } finally { fs.rmSync(directory, { recursive: true, force: true }); }
});

test('mount addition matches ZQBB save-before-mount and never deletes a reused copy on failure', () => {
  const settings = read('Application/Dopamine/UI/Settings/DOSettingsController.m');
  const add = settings.slice(settings.indexOf('- (void)mountCustomDirectoryPressed'), settings.indexOf('- (void)manageCustomMountsPressed'));
  assert.ok(add.indexOf('saveCustomMountPaths:updatedPaths') < add.indexOf('mountCustomDirectory:path'));
  assert.match(add, /saveCustomMountPaths:existingPaths/);
  assert.doesNotMatch(add, /removeCustomMountCopyAtPath|unmountCustomDirectory:/);
  const jbctl = read('BaseBin/jbctl/src/internal.m');
  const prepare = body(jbctl, 'prepare_mount_copy');
  assert.match(prepare, /mkdtemp\(template\)/);
  assert.match(prepare, /JBROOT_PATH\(@"\/var\/tmp"\)/);
  assert.doesNotMatch(prepare, /stringByAppendingString:@"_tmp"/);
  assert.match(prepare, /removeItemAtPath:stagingPath/);
});

test('native Foundation executes the production mount-copy routine without mounts and preserves A_tmp', {
  skip: process.platform !== 'darwin' ? 'Requires macOS Foundation; no real mounts are performed.' : false,
}, () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'rh-mount-copy-'));
  try {
    const source = `#import <Foundation/Foundation.h>
#import <stdlib.h>
#import <errno.h>
#import <string.h>
${read('BaseBin/libjailbreak/src/custom_mount.h')}
static NSString *root;
#define JBROOT_PATH(p) [root stringByAppendingString:p]
${body(read('BaseBin/jbctl/src/internal.m'), 'prepare_mount_copy')}
int main(int argc, char **argv) { @autoreleasepool {
  root = [NSString stringWithUTF8String:argv[1]];
  NSFileManager *fm = NSFileManager.defaultManager;
  NSString *src = [root stringByAppendingPathComponent:@"source/A"];
  [fm createDirectoryAtPath:src withIntermediateDirectories:YES attributes:nil error:nil];
  [@"source" writeToFile:[src stringByAppendingPathComponent:@"font"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
  NSString *copy = [JBROOT_PATH(@"/mnt") stringByAppendingString:src];
  NSString *other = [copy stringByAppendingString:@"_tmp"];
  [fm createDirectoryAtPath:other withIntermediateDirectories:YES attributes:nil error:nil];
  NSString *marker = [other stringByAppendingPathComponent:@"user-font"];
  [@"custom" writeToFile:marker atomically:YES encoding:NSUTF8StringEncoding error:nil];
  if (prepare_mount_copy(src.fileSystemRepresentation) != 0) return 1;
  if (![[NSString stringWithContentsOfFile:marker encoding:NSUTF8StringEncoding error:nil] isEqual:@"custom"]) return 2;
  if (![fm fileExistsAtPath:[copy stringByAppendingPathComponent:@"font"]]) return 3;
  [@"edited" writeToFile:[copy stringByAppendingPathComponent:@"font"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
  if (prepare_mount_copy(src.fileSystemRepresentation) != 0) return 4;
  if (![[NSString stringWithContentsOfFile:[copy stringByAppendingPathComponent:@"font"] encoding:NSUTF8StringEncoding error:nil] isEqual:@"edited"]) return 5;
  if ([fm contentsOfDirectoryAtPath:JBROOT_PATH(@"/var/tmp") error:nil].count != 0) return 6;
  NSString *child = [src stringByAppendingPathComponent:@"child"];
  [fm createDirectoryAtPath:child withIntermediateDirectories:YES attributes:nil error:nil];
  [@"source-child" writeToFile:[child stringByAppendingPathComponent:@"font"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
  NSString *childCopy = [copy stringByAppendingPathComponent:@"child"];
  [fm createDirectoryAtPath:childCopy withIntermediateDirectories:YES attributes:nil error:nil];
  NSString *custom = [childCopy stringByAppendingPathComponent:@"font"];
  [@"custom-child" writeToFile:custom atomically:YES encoding:NSUTF8StringEncoding error:nil];
  if (![@{@"path": @[child, src]} writeToFile:JBROOT_PATH(@"/mnt/newFakePath.plist") atomically:YES]) return 7;
  if (prepare_mount_copy(src.fileSystemRepresentation) != EBUSY) return 8;
  if (![[NSString stringWithContentsOfFile:custom encoding:NSUTF8StringEncoding error:nil] isEqual:@"custom-child"]) return 9;
  if (prepare_mount_copy(child.fileSystemRepresentation) != 0) return 10;
  if (DOCustomMountIntroducesOverlap(@[src, child], @[src]) != YES ||
      DOCustomMountIntroducesOverlap(@[child, src], @[child]) != YES ||
      DOCustomMountIntroducesOverlap(@[child], @[src, child]) != NO ||
      DOCustomMountIntroducesOverlap(@[src, child], @[src, child]) != NO ||
      DOCustomMountPathsOverlap(src, [src stringByAppendingString:@"_tmp"]) != NO) return 11;
  return 0;
} }
`;
    const file = path.join(directory, 'mount.m');
    const binary = path.join(directory, 'mount-test');
    fs.writeFileSync(file, source);
    execFileSync('xcrun', ['clang', '-fobjc-arc', '-framework', 'Foundation', file, '-o', binary]);
    execFileSync(binary, [directory]);
  } finally { fs.rmSync(directory, { recursive: true, force: true }); }
});

test('mount removal persists the list before cleanup and guards both shared-tree directions', () => {
  const manager = read('Application/Dopamine/Jailbreak/DOEnvironmentManager.m');
  const finish = manager.slice(manager.indexOf('- (void)finishCustomMountRemovalAtPath:'),
    manager.indexOf('// 根据注入配置'));
  assert.ok(finish.indexOf('saveCustomMountPaths:updatedPaths') < finish.indexOf('runCustomMountCommand:@"cleanup_mount_copy"'));
  assert.match(finish, /if \(!\[self saveCustomMountPaths:updatedPaths\]\)\s*\{\s*completion\(DOCustomMountRemovalSaveFailed\)/);
  assert.match(finish, /conflictingCustomMountPathForPath:path/);
  assert.doesNotMatch(manager.slice(manager.indexOf('- (void)runCustomMountCommand:'),
    manager.indexOf('// 根据注入配置')), /removeItemAtPath:/);
  const remove = body(read('BaseBin/jbctl/src/internal.m'), 'cleanup_mount_copy');
  assert.ok(remove.indexOf('DOCustomMountConflictingPath(path, paths)') < remove.indexOf('removeItemAtPath:copy'));
  assert.match(remove, /fake_path_is_mounted\(rawPath\)/);
  assert.match(remove, /stringByResolvingSymlinksInPath/);
  const prepare = body(read('BaseBin/jbctl/src/internal.m'), 'prepare_mount_copy');
  assert.ok(prepare.indexOf('DOCustomMountHasSavedDescendant(path, paths)') < prepare.indexOf('contents.count > 0'));
  assert.match(manager, /DOCustomMountIntroducesOverlap\(paths, previous\)/);
  assert.match(manager, /DOCustomMountDropsChildBeforeParent\(paths, previous\)/);
  const settings = read('Application/Dopamine/UI/Settings/DOSettingsController.m');
  assert.match(settings, /conflictingCustomMountPathForPath:path/);
  assert.match(settings, /finishCustomMountRemovalAtPath:path/);
  assert.match(settings, /finishCustomMountRemovalAtPath:path completion:[\s\S]*?self\.customMountBusy = NO/);
});

test('native Foundation mount removal preserves copies on save failure and keeps legacy overlapping entries editable', {
  skip: process.platform !== 'darwin' ? 'Requires macOS Foundation; no mounts or privilege changes are performed.' : false,
}, () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'rh-mount-removal-'));
  try {
    const manager = read('Application/Dopamine/Jailbreak/DOEnvironmentManager.m');
    const method = (start, end) => manager.slice(manager.indexOf(start), manager.indexOf(end));
    const source = `#import <Foundation/Foundation.h>
${read('BaseBin/libjailbreak/src/custom_mount.h')}
#include <sys/stat.h>
#include <errno.h>
static NSString *fixtureRoot;
#define JBROOT_PATH(p) [fixtureRoot stringByAppendingString:p]
static bool mounted;
static bool custom_mount_path_is_valid(const char *p) { return p && p[0] == '/'; }
static bool fake_path_is_mounted(const char *p) { return mounted; }
${body(read('BaseBin/jbctl/src/internal.m'), 'cleanup_mount_copy')}
typedef NS_ENUM(NSInteger, DOCustomMountRemovalResult) {
  DOCustomMountRemovalCompleted, DOCustomMountRemovalSaveFailed,
  DOCustomMountRemovalCopyPreserved, DOCustomMountRemovalCleanupFailed
};
@interface TestEnvironment : NSObject
@property BOOL failSave, failCleanup, customMountTaskRunning;
@property NSUInteger cleanupCalls;
@end
@implementation TestEnvironment
- (void)runAsRoot:(void (^)(void))block { block(); }
- (void)runUnsandboxed:(void (^)(void))block { block(); }
- (NSString *)customMountListPath { return JBROOT_PATH(@"/mnt/newFakePath.plist"); }
- (NSArray *)customMountPaths { return [NSDictionary dictionaryWithContentsOfFile:self.customMountListPath][@"path"] ?: @[]; }
${method('- (BOOL)saveCustomMountPaths:', '- (int)mountCustomDirectory:').replace(
  'if (![paths isKindOfClass:NSArray.class])', 'if (self.failSave || ![paths isKindOfClass:NSArray.class])')}
- (void)runCustomMountCommand:(NSString *)command path:(NSString *)path completion:(void (^)(int))completion {
  if (!NSThread.isMainThread || self.customMountTaskRunning || ![command isEqual:@"cleanup_mount_copy"]) abort();
  self.cleanupCalls++;
  self.customMountTaskRunning = YES;
  BOOL failure = self.failCleanup;
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
    if (NSThread.isMainThread) abort();
    int result = failure ? EIO : cleanup_mount_copy(path.fileSystemRepresentation);
    dispatch_async(dispatch_get_main_queue(), ^{
      self.customMountTaskRunning = NO;
      completion(result);
    });
  });
}
${method('- (void)finishCustomMountRemovalAtPath:', '// 根据注入配置')}
@end
#define CHECK(...) do { if (!(__VA_ARGS__)) { fprintf(stderr, "check failed at line %d: %s\\n", __LINE__, #__VA_ARGS__); return 1; } } while (0)
static DOCustomMountRemovalResult finish(TestEnvironment *env, NSString *path) {
  __block BOOL completed = NO;
  __block DOCustomMountRemovalResult result;
  NSUInteger calls = env.cleanupCalls;
  [env finishCustomMountRemovalAtPath:path completion:^(DOCustomMountRemovalResult r) {
    if (!NSThread.isMainThread || env.customMountTaskRunning) abort();
    result = r; completed = YES;
  }];
  if (env.cleanupCalls > calls && (completed || !env.customMountTaskRunning)) abort();
  NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
  while (!completed && deadline.timeIntervalSinceNow > 0)
    [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
  if (!completed) abort();
  return result;
}
static NSString *makeCopy(NSString *path) {
  NSString *copy = [JBROOT_PATH(@"/mnt") stringByAppendingString:path];
  [NSFileManager.defaultManager createDirectoryAtPath:copy withIntermediateDirectories:YES attributes:nil error:nil];
  NSString *font = [copy stringByAppendingPathComponent:@"user-font"];
  [@"custom" writeToFile:font atomically:YES encoding:NSUTF8StringEncoding error:nil];
  return font;
}
int main(int argc, char **argv) { @autoreleasepool {
  fixtureRoot = [[NSString stringWithUTF8String:argv[1]] stringByResolvingSymlinksInPath];
  TestEnvironment *env = [TestEnvironment new];
  NSString *parent = @"/System/Library/Fonts", *child = @"/System/Library/Fonts/Cache";
  CHECK([env saveCustomMountPaths:@[parent]]);
  CHECK(![env saveCustomMountPaths:@[parent, child]]);
  CHECK([env saveCustomMountPaths:@[child]]);
  CHECK(![env saveCustomMountPaths:@[child, parent]]);
  CHECK(![env saveCustomMountPaths:@[parent]]);
  CHECK([env saveCustomMountPaths:@[]]);
  NSString *font = makeCopy(parent);
  CHECK([env saveCustomMountPaths:@[parent]]);
  env.failSave = YES;
  CHECK(finish(env, parent) == DOCustomMountRemovalSaveFailed);
  CHECK(env.cleanupCalls == 0 && [env.customMountPaths containsObject:parent]);
  CHECK([NSFileManager.defaultManager fileExistsAtPath:font]);
  env.failSave = NO;
  CHECK(finish(env, parent) == DOCustomMountRemovalCompleted);
  CHECK(env.customMountPaths.count == 0 && ![NSFileManager.defaultManager fileExistsAtPath:font]);
  // Simulate an old on-disk overlapping list, in both insertion orders.
  for (NSArray *legacy in @[@[child, parent], @[parent, child]]) {
    CHECK([@{@"path": legacy} writeToFile:env.customMountListPath atomically:YES]);
    NSString *childFont = makeCopy(child);
    CHECK(cleanup_mount_copy(parent.fileSystemRepresentation) == EBUSY);
    CHECK([env saveCustomMountPaths:legacy]);
    CHECK(finish(env, parent) == DOCustomMountRemovalCopyPreserved);
    CHECK([env.customMountPaths isEqual:@[child]] && [NSFileManager.defaultManager fileExistsAtPath:childFont]);
    CHECK(finish(env, child) == DOCustomMountRemovalCompleted);
    CHECK([@{@"path": legacy} writeToFile:env.customMountListPath atomically:YES]);
    childFont = makeCopy(child);
    CHECK(finish(env, child) == DOCustomMountRemovalSaveFailed);
    CHECK([env.customMountPaths isEqual:legacy] && [NSFileManager.defaultManager fileExistsAtPath:childFont]);
    CHECK(finish(env, parent) == DOCustomMountRemovalCopyPreserved);
    CHECK(finish(env, child) == DOCustomMountRemovalCompleted);
  }
  font = makeCopy(parent);
  CHECK([env saveCustomMountPaths:@[parent]]);
  env.failCleanup = YES;
  CHECK(finish(env, parent) == DOCustomMountRemovalCleanupFailed);
  CHECK(env.customMountPaths.count == 0 && [NSFileManager.defaultManager fileExistsAtPath:font]);
  env.failCleanup = NO;
  CHECK(finish(env, parent) == DOCustomMountRemovalCompleted);
  CHECK(![NSFileManager.defaultManager fileExistsAtPath:font]);
  font = makeCopy(parent);
  mounted = true;
  CHECK(cleanup_mount_copy(parent.fileSystemRepresentation) == EBUSY);
  mounted = false;
  CHECK([@{} writeToFile:env.customMountListPath atomically:YES]);
  CHECK(cleanup_mount_copy(parent.fileSystemRepresentation) == EIO);
  CHECK([NSFileManager.defaultManager fileExistsAtPath:font]);
  CHECK([env saveCustomMountPaths:@[]]);
  CHECK(cleanup_mount_copy(parent.fileSystemRepresentation) == 0);
  // A redirected intermediate copy directory must not delete outside its tree.
  NSString *library = JBROOT_PATH(@"/mnt/System/Library");
  NSString *outside = [fixtureRoot stringByAppendingPathComponent:@"outside"];
  CHECK([NSFileManager.defaultManager createDirectoryAtPath:outside withIntermediateDirectories:YES attributes:nil error:nil]);
  NSString *outsideFont = [outside stringByAppendingPathComponent:@"Fonts"];
  CHECK([NSFileManager.defaultManager createDirectoryAtPath:outsideFont withIntermediateDirectories:YES attributes:nil error:nil]);
  CHECK([NSFileManager.defaultManager removeItemAtPath:library error:nil]);
  CHECK([NSFileManager.defaultManager createSymbolicLinkAtPath:library withDestinationPath:outside error:nil]);
  CHECK(cleanup_mount_copy(parent.fileSystemRepresentation) == EINVAL);
  CHECK([NSFileManager.defaultManager fileExistsAtPath:outsideFont]);
  return 0;
} }
`;
    const file = path.join(directory, 'removal.m');
    const binary = path.join(directory, 'removal-test');
    fs.writeFileSync(file, source);
    execFileSync('xcrun', ['clang', '-fobjc-arc', '-framework', 'Foundation', file, '-o', binary]);
    execFileSync(binary, [directory]);
  } finally {
    fs.rmSync(directory, { recursive: true, force: true });
  }
});

test('render authorization is display-only and license mutations invalidate it before notifying views', () => {
  for (const name of ['DORHSupporterStoreLicenseCode', 'DORHSupporterStoreActivationText', 'DORHSupporterRemoveLicense']) {
    const method = body(licenseSource, name);
    assert.ok(method.indexOf('DORHSupporterInvalidateRenderAuthorization()') < method.indexOf('postNotificationName:'));
    assert.ok(method.indexOf('DORHSupporterInvalidateRenderAuthorization()') > method.indexOf('DORHSupporterWritePersistentState('));
  }
  const render = read('Application/Dopamine/UI/DOSupporterRenderAuthorization.h');
  assert.match(render, /queue:nil/);
  assert.match(render, /UIApplicationWillResignActiveNotification/);
  assert.match(render, /UIApplicationDidBecomeActiveNotification/);
  assert.match(render, /now - \[state\[@"checkedAt"\] doubleValue\] >= 1\.0/);
  for (const file of ['DOMainViewController.m', '../Jailbreak/DOJailbreaker.m', 'DOSupporterLicenseUI.h'])
    assert.doesNotMatch(read('Application/Dopamine/UI/' + file), /DORHSupporterRenderIsVerified/);
  assert.doesNotMatch(body(licenseSource, 'DORHSupporterIsVerified'), /Render/);
  const theme = read('Application/Dopamine/UI/DOCustomGlassView.m');
  assert.match(theme, /- \(void\)reloadMaterial\s*\{[\s\S]*?DORHSupporterRenderIsVerified\(\)/);
  assert.match(theme, /if \(!DORHSupporterIsVerified\(\)\)/);
});

test('native render snapshot is shared across translation units, expires and invalidates before earlier view observers run', {
  skip: process.platform !== 'darwin' ? 'Requires macOS Foundation/Objective-C runtime; authorization is a test double.' : false,
}, () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'rh-render-authorization-'));
  try {
    const prefix = `#import <Foundation/Foundation.h>
#import <objc/runtime.h>
extern NSString * const DORHSupporterLicenseDidChangeNotification;
extern NSString * const UIApplicationWillResignActiveNotification;
extern NSString * const UIApplicationDidBecomeActiveNotification;
extern NSTimeInterval testUptime;
BOOL DORHSupporterIsVerified(void);
${body(licenseSource, 'DORHSupporterInvalidateRenderAuthorization')}
`;
    const header = read('Application/Dopamine/UI/DOSupporterRenderAuthorization.h')
      .replace('#import "DOSupporterLicense.h"', prefix)
      .replace('NSProcessInfo.processInfo.systemUptime', 'testUptime');
    fs.writeFileSync(path.join(directory, 'render.h'), header);
    fs.writeFileSync(path.join(directory, 'other.m'), `#import "render.h"
BOOL otherRender(void) { return DORHSupporterRenderIsVerified(); }
`);
    const source = `#import "render.h"
NSString * const DORHSupporterLicenseDidChangeNotification = @"license";
NSString * const UIApplicationWillResignActiveNotification = @"resign";
NSString * const UIApplicationDidBecomeActiveNotification = @"active";
NSTimeInterval testUptime = 100;
static BOOL entitled;
static NSUInteger checks;
BOOL DORHSupporterIsVerified(void) { checks++; return entitled; }
BOOL otherRender(void);
#define CHECK(value) do { if (!(value)) { fprintf(stderr, "check failed at line %d\\n", __LINE__); return 1; } } while (0)
int main(void) { @autoreleasepool {
  __block BOOL notifiedValue = YES;
  // Views can register before the lazy cache observer. Mutation must invalidate first.
  id earlier = [NSNotificationCenter.defaultCenter addObserverForName:DORHSupporterLicenseDidChangeNotification
    object:nil queue:nil usingBlock:^(NSNotification *n) { notifiedValue = otherRender(); }];
  CHECK(!DORHSupporterRenderIsVerified() && checks == 1);
  for (int i = 0; i < 100; i++) CHECK(!otherRender());
  CHECK(checks == 1);
  entitled = YES;
  CHECK(!otherRender() && checks == 1);
  DORHSupporterInvalidateRenderAuthorization();
  [NSNotificationCenter.defaultCenter postNotificationName:DORHSupporterLicenseDidChangeNotification object:nil];
  CHECK(notifiedValue && DORHSupporterRenderIsVerified() && checks >= 2 && checks <= 3);
  NSUInteger previous = checks;
  entitled = NO;
  DORHSupporterInvalidateRenderAuthorization();
  [NSNotificationCenter.defaultCenter postNotificationName:DORHSupporterLicenseDidChangeNotification object:nil];
  CHECK(!notifiedValue && !otherRender() && checks > previous && checks <= previous + 2);
  previous = checks;
  entitled = YES;
  testUptime += 1.01;
  CHECK(otherRender() && DORHSupporterRenderIsVerified() && checks == previous + 1);
  previous = checks;
  entitled = NO;
  // The action check is always fresh, independently of the display snapshot.
  CHECK(!DORHSupporterIsVerified() && otherRender() && checks == previous + 1);
  previous = checks;
  [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationWillResignActiveNotification object:nil];
  CHECK(!otherRender() && checks == previous + 1);
  previous = checks;
  entitled = YES;
  [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationDidBecomeActiveNotification object:nil];
  CHECK(DORHSupporterRenderIsVerified() && checks == previous + 1);
  [NSNotificationCenter.defaultCenter removeObserver:earlier];
  return 0;
} }
`;
    const file = path.join(directory, 'main.m');
    const binary = path.join(directory, 'render-test');
    fs.writeFileSync(file, source);
    execFileSync('xcrun', ['clang', '-fobjc-arc', '-framework', 'Foundation', file, path.join(directory, 'other.m'), '-o', binary]);
    execFileSync(binary, []);
  } finally { fs.rmSync(directory, { recursive: true, force: true }); }
});
