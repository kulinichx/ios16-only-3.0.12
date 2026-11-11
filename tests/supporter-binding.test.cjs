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
    const helperNames = ['DORHSupporterLicenseError', 'DORHSupporterDecodeBase64URL',
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
