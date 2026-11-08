const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const root = path.resolve(__dirname, '..');
const uiRoot = path.join(root, 'Application/Dopamine/UI');
const source = fs.readFileSync(
  path.join(uiRoot, 'DOSupporterLicense.h'),
  'utf8',
);
const licenseUI = fs.readFileSync(
  path.join(uiRoot, 'DOSupporterLicenseUI.h'),
  'utf8',
);
const home = fs.readFileSync(path.join(uiRoot, 'DOMainViewController.m'), 'utf8');
const theme = fs.readFileSync(path.join(uiRoot, 'DOCustomGlassView.m'), 'utf8');
const settings = fs.readFileSync(
  path.join(uiRoot, 'Settings/DOSettingsController.m'),
  'utf8',
);
const credits = fs.readFileSync(
  path.join(uiRoot, 'Settings/DOCreditsViewController.m'),
  'utf8',
);
const creditsPlist = fs.readFileSync(
  path.join(uiRoot, 'Settings/Credits.plist'),
  'utf8',
);

function body(name) {
  const signature = new RegExp(
    String.raw`^static inline [^{;]+\b${name}\([^;]*?\)\s*\{`,
    'm',
  );
  const match = signature.exec(source);
  assert.ok(match, `Missing function definition: ${name}`);

  const start = match.index + match[0].length;
  let depth = 1;
  for (let index = start; index < source.length; index++) {
    if (source[index] === '{') depth++;
    if (source[index] === '}' && --depth === 0) {
      return source.slice(start, index);
    }
  }
  assert.fail(`Unclosed function body: ${name}`);
}

function objcMethod(sourceText, signature) {
  const start = sourceText.indexOf(signature);
  assert.ok(start >= 0, `Missing Objective-C method: ${signature}`);
  const opening = sourceText.indexOf('{', start + signature.length);
  assert.ok(opening >= 0, `Missing method body: ${signature}`);
  let depth = 0;
  for (let index = opening; index < sourceText.length; index++) {
    if (sourceText[index] === '{') depth++;
    if (sourceText[index] === '}' && --depth === 0)
      return sourceText.slice(opening + 1, index);
  }
  assert.fail(`Unclosed Objective-C method: ${signature}`);
}

test('supporter state keeps stable legacy keys and an external removal tombstone', () => {
  for (const value of [
    '@"DORHSupporter.LicenseCode"',
    '@"/var/mobile/Library/Application Support/DopamineRH"',
    '@"supporter-state.plist"',
    '@"DeviceCode"',
    '@"LicenseCode"',
    '@"LicenseRemoved"',
  ]) {
    assert.ok(source.includes(value), `Missing compatibility key: ${value}`);
  }
});

test('invalid or wrong-device licenses are rejected before state mutation', () => {
  const store = body('DORHSupporterStoreLicenseCode');
  const verify = store.indexOf('DORHSupporterVerifyLicenseCode(');
  const reject = store.indexOf('if (!info)');
  const read = store.indexOf('DORHSupporterReadPersistentState()');
  assert.ok(verify >= 0 && reject > verify && read > reject);
  assert.match(store.slice(reject, read), /return NO;/);
});

test('license activation fails closed when external state cannot clear a removal tombstone', () => {
  const store = body('DORHSupporterStoreLicenseCode');
  const persist = store.indexOf('DORHSupporterWritePersistentState(state)');
  const failure = store.indexOf('if (!persisted)');
  const defaults = store.indexOf('setObject:trimmed');
  assert.ok(persist >= 0 && failure > persist && defaults > failure);
  assert.match(store.slice(failure, defaults), /Unable to persist supporter license/);
  assert.match(store.slice(failure, defaults), /return NO;/);
});

test('legacy device-code derivation stays independent of the fork bundle identifier', () => {
  const deviceCode = body('DORHSupporterDeviceCode');
  assert.match(deviceCode, /NSString \*bundleID = @"com\.opa334\.Dopamine-roothide";/);
  assert.doesNotMatch(deviceCode, /NSBundle\.mainBundle\.bundleIdentifier/);
});

test('signature verification precedes payload parsing and checks product, entitlement, and device', () => {
  const verify = body('DORHSupporterVerifyLicenseCodeForDevice');
  assert.ok(
    verify.indexOf('SecKeyVerifySignature(') <
      verify.indexOf('JSONObjectWithData:payload'),
  );
  assert.match(verify, /kSecKeyAlgorithmECDSASignatureMessageX962SHA256/);
  assert.match(verify, /isEqualToString:@"RH1"/);
  assert.match(verify, /isEqualToString:@"DopamineRH"/);
  assert.match(verify, /containsObject:@"custom_glass"/);
  assert.match(verify, /if \(!\[device isEqualToString:currentDeviceCode\]\)/);
});

test('removal only clears defaults and announces completion after persistent tombstone is confirmed', () => {
  const remove = body('DORHSupporterRemoveLicense');
  assert.match(remove, /removedState\[DORHSupporterPersistentLicenseRemovedKey\] = @YES;/);
  assert.match(
    remove,
    /if \(!DORHSupporterWritePersistentState\(removedState\) \|\|\s*!DORHSupporterLicenseTombstoned\(\)\)\s*\{\s*return NO;/,
  );
  const failClosed = remove.indexOf('return NO;');
  assert.ok(failClosed < remove.indexOf('removeObjectForKey:DORHSupporterLicenseDefaultsKey'));
  assert.ok(failClosed < remove.indexOf('postNotificationName:'));
  assert.doesNotMatch(remove, /removeItemAtPath:/);
  assert.match(remove, /return YES;/);
});

test('device-key diagnostics never delete existing keys or fall back to software or ephemeral keys', () => {
  const keyLookup = body('DORHSupporterCopyOrCreateDevicePrivateKey');
  assert.match(keyLookup, /SecItemCopyMatching\(/);
  assert.match(keyLookup, /kSecAttrTokenID[\s\S]*kSecAttrTokenIDSecureEnclave/);
  assert.match(keyLookup, /DORHSupporterDeviceKeyIsSecureEnclaveP256PrivateKey/);
  assert.match(keyLookup, /SecKeyCreateRandomKey\(/);
  assert.doesNotMatch(keyLookup, /SecItemDelete\(/);
  assert.doesNotMatch(keyLookup, /kSecAttrIsPermanent\s*:\s*@NO/);
  assert.doesNotMatch(keyLookup, /fallbackAttrs|fallbackPrivate|ephemeralAttrs/);
});

test('application source contains no issuer private-key material', () => {
  assert.doesNotMatch(source, /-----BEGIN (?:EC |RSA )?PRIVATE KEY-----/);
  assert.doesNotMatch(source, /DORHSupporterIssuerPrivateKey/);
  assert.match(source, /static NSString \* const publicKeyBase64/);
});

test('settings and Credits use one shared supporter-license flow', () => {
  assert.match(settings, /DORHPresentSupporterLicense\(self\)/);
  assert.match(credits, /DORHPresentSupporterLicense\(self\)/);
  assert.match(creditsPlist, /<string>supporterLicensePressed<\/string>/);
  assert.match(licenseUI, /DORHSupporterStoreLicenseCode/);
  assert.match(licenseUI, /DORHSupporterRemoveLicense/);
});

test('device diagnostics disclose persistent key creation and never expose identifiers', () => {
  assert.match(licenseUI, /Supporter_Diagnostics_Consent_Message/);
  assert.ok(
    licenseUI.indexOf('Supporter_Diagnostics_Consent_Message') <
      licenseUI.indexOf('DORHSupporterDeviceKeyProbe()'),
    'the persistent-key disclosure must be shown before key probing',
  );
  const diagnostics = licenseUI.slice(
    licenseUI.indexOf('static inline void DORHPresentSupporterDiagnostics'),
    licenseUI.indexOf('static inline void DORHPresentSupporterLicense'),
  );
  assert.match(diagnostics, /signature_self_test/);
  assert.match(diagnostics, /created/);
  assert.doesNotMatch(diagnostics, /hardware_id|key_fingerprint|UIPasteboard/);
  for (const locale of ['en', 'zh-Hans', 'zh-CN']) {
    const strings = fs.readFileSync(
      path.join(root, `Application/Dopamine/${locale}.lproj/Localizable.strings`),
      'utf8',
    );
    for (const key of [
      'Supporter_Diagnostics_Consent_Message',
      'Supporter_Diagnostics_Result_Format',
      'Supporter_Key_State_Created',
    ]) {
      assert.match(strings, new RegExp(`"${key}"\\s*=`), `${locale} missing ${key}`);
    }
  }
});

test('glass editing checks entitlement at action time without gating jailbreak or focus mode', () => {
  for (const signature of [
    '- (void)presentCustomGlassUsernameEditor',
    '- (void)presentCustomGlassMottoEditor',
    '- (void)customGlassAvatarTapped:',
  ]) {
    assert.match(objcMethod(home, signature), /requireCustomGlassSupporterAuthorization/);
  }

  const focusGesture = objcMethod(home, '- (void)customGlassAvatarPanned:');
  assert.doesNotMatch(focusGesture, /requireCustomGlassSupporterAuthorization|DORHSupporter/);

  const jailbreak = objcMethod(home, '- (void)startJailbreak');
  assert.doesNotMatch(jailbreak, /requireCustomGlassSupporterAuthorization|DORHSupporter/);

  const themeEntry = home.slice(
    home.indexOf('UIAction *themeAction'),
    home.indexOf('DOCustomLiquidGlassView *themeCard'),
  );
  assert.match(themeEntry, /requireCustomGlassSupporterAuthorization/);

  for (const signature of [
    '- (void)presentCustomGlassBackgroundPicker',
    '- (void)glassAppearanceChanged:',
    '- (void)appearanceSliderChanged:',
    '- (void)wallpaperPlaybackRateChanged:',
    '- (void)applyAppearancePreviewAndPersist:',
    '- (void)restoreRecommendedAppearanceValues',
  ]) {
    assert.match(objcMethod(theme, signature), /requireCustomGlassSupporterAuthorization/);
  }
  assert.match(theme, /name:DORHSupporterLicenseDidChangeNotification/);
  assert.match(theme, /self\.supporterAuthorizationVerified = DORHSupporterIsVerified\(\)/);
});
