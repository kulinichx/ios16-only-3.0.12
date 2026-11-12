const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const { spawnSync } = require('node:child_process');
const { verifyAppEntitlements } = require('../scripts/verify-app-entitlements.cjs');

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

function section(source, start, end) {
  const a = source.indexOf(start);
  const b = source.indexOf(end, a + start.length);
  assert.ok(a >= 0 && b > a, `Missing section: ${start}`);
  return source.slice(a, b);
}

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

test('authorization actions use matching numbered labels and brief copied-proof feedback without changing activation copy', () => {
  const actionKeys = ['Supporter_Copy_Device_Code', 'Supporter_Bind_This_Device', 'Supporter_Paste_License'];
  const value = (text, key) => {
    const matches = [...text.matchAll(new RegExp(`^"${key}"\\s*=\\s*("(?:[^"\\\\]|\\\\.)*");`, 'gm'))];
    assert.equal(matches.length, 1, `Missing or duplicate ${key}`);
    return JSON.parse(matches[0][1]);
  };
  for (const locale of ['zh-Hans', 'zh-CN', 'en']) {
    const text = fs.readFileSync(path.join(root, `Application/Dopamine/${locale}.lproj/Localizable.strings`), 'utf8');
    const actions = actionKeys.map(key => value(text, key));
    actions.forEach((label, index) => assert.ok(label.startsWith(`${index + 1}. `)));
    if (locale !== 'en') {
      assert.deepEqual(actions, ['1. 复制设备码', '2. 生成证明码', '3. 粘贴授权码']);
      assert.equal(new Set(actions.map(label => [...label].length)).size, 1);
      assert.equal(value(text, 'Supporter_Device_Code_Copied'), '设备码已复制');
      assert.equal(value(text, 'Supporter_Device_Proof_Ready'), '证明已生成并复制');
      assert.equal(value(text, 'Supporter_Device_Code_Copied_Message'), '请粘贴发给作者。');
      assert.equal(value(text, 'Supporter_Device_Proof_Ready_Message'), '请粘贴发给作者。');
      assert.equal(value(text, 'Supporter_Activated'), '支持者授权已启用');
      assert.equal(value(text, 'Supporter_Activated_Message'), '授权已保存。立即应用以刷新界面。');
      assert.equal(value(text, 'Supporter_Apply_Now'), '立即应用');
    }
    assert.ok(!/^\d/.test(value(text, 'Supporter_Remove_License')));
    assert.ok(!/^\d/.test(value(text, 'Supporter_Advanced_Diagnostics')));
  }
  assert.ok(licenseUI.indexOf('UIPasteboard.generalPasteboard.string = deviceCode;') <
    licenseUI.indexOf('DOLocalizedString(@"Supporter_Device_Code_Copied")'));
  assert.ok(licenseUI.indexOf('UIPasteboard.generalPasteboard.string = proofText;') <
    licenseUI.indexOf('DOLocalizedString(@"Supporter_Device_Proof_Ready")'));
});

test('brief user guides preserve the app step numbers when existing users skip device-code submission', () => {
  const guides = ['03-发给用户-授权与设备绑定步骤.txt', '04-发给旧用户-补发授权步骤.txt']
    .map(name => fs.readFileSync(path.join(root, '授权流程说明', name), 'utf8'));
  assert.deepEqual([...guides[0].matchAll(/^(\d)\. /gm)].map(match => match[1]), ['1', '2', '3']);
  assert.deepEqual([...guides[1].matchAll(/^(\d)\. /gm)].map(match => match[1]), ['2', '3']);
  for (const guide of guides) {
    assert.ok(guide.includes('复制作者发来的验证文本'));
    assert.ok(guide.includes('2. 生成证明码'));
    assert.ok(guide.includes('3. 粘贴授权码'));
    assert.ok(guide.includes('已验证 · 已绑定本机'));
    assert.ok(guide.length < 400);
  }
  assert.ok(guides[1].includes('原记录和设备码未变'));
  assert.ok(guides[1].includes('旧授权不用删除'));
});

test('packaged entitlement verifier rejects missing, broad or mismatched keychain permissions', () => {
  const info = { CFBundleIdentifier: 'cn.zqbb.dopaRH' };
  const valid = {
    'application-identifier': info.CFBundleIdentifier,
    'keychain-access-groups': [info.CFBundleIdentifier],
    'platform-application': true,
    'com.apple.private.security.no-sandbox': true,
  };
  assert.doesNotThrow(() => verifyAppEntitlements(valid, info));
  for (const key of Object.keys(valid)) {
    const missing = { ...valid };
    delete missing[key];
    assert.throws(() => verifyAppEntitlements(missing, info), key);
  }
  for (const groups of [[], ['*'], ['TROLLTROLL.*'], ['other.app'],
    [info.CFBundleIdentifier, 'com.apple.token'], info.CFBundleIdentifier]) {
    assert.throws(() => verifyAppEntitlements({ ...valid, 'keychain-access-groups': groups }, info));
  }
  assert.throws(() => verifyAppEntitlements({ ...valid, 'application-identifier': 'other.app' }, info));
  assert.throws(() => verifyAppEntitlements({ ...valid, 'com.apple.developer.team-identifier': 'FAKETEAM' }, info));
  assert.throws(() => verifyAppEntitlements(valid, { CFBundleIdentifier: 'other.app' }));
});

test('source entitlements pass the native plist parser and scoped keychain contract', {
  skip: process.platform !== 'darwin' && process.platform !== 'win32',
}, () => {
  const file = path.join(root, 'Application/Dopamine/Dopamine.entitlements');
  let result;
  if (process.platform === 'darwin') {
    result = spawnSync('plutil', ['-convert', 'json', '-o', '-', file], { encoding: 'utf8' });
  } else {
    // Use the native XML parser, not text matching, to preserve plist value types.
    result = spawnSync('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command', `
      $ErrorActionPreference = 'Stop'
      $plist = [xml](Get-Content -LiteralPath '${file.replace(/'/g, "''")}' -Raw)
      $values = @{}
      foreach ($key in $plist.plist.dict.SelectNodes('key')) {
        $value = $key.NextSibling
        switch ($value.LocalName) {
          'string' { $values[$key.InnerText] = $value.InnerText }
          'true' { $values[$key.InnerText] = $true }
          'false' { $values[$key.InnerText] = $false }
          'array' { $values[$key.InnerText] = @($value.SelectNodes('string') | ForEach-Object { $_.InnerText }) }
          default { throw 'Unexpected entitlement plist value type' }
        }
      }
      ConvertTo-Json -InputObject $values -Depth 10 -Compress
    `], { encoding: 'utf8' });
  }
  assert.equal(result.status, 0, result.stderr);
  verifyAppEntitlements(JSON.parse(result.stdout), { CFBundleIdentifier: 'cn.zqbb.dopaRH' });
  const workflow = fs.readFileSync(path.join(root, '.github/workflows/build.yml'), 'utf8');
  assert.match(workflow, /unzip -p "\$tipa" Payload\/Dopamine\.app\/Dopamine/);
  assert.match(workflow, /ldid -e .*RootHide-Dopamine.* > app-entitlements\.plist/);
  assert.match(workflow, /node scripts\/verify-app-entitlements\.cjs/);
});

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

test('settings retains the supporter-license flow while Credits has no authorization entry', () => {
  assert.match(settings, /DORHPresentSupporterLicense\(self\)/);
  assert.doesNotMatch(credits, /DOSupporterLicenseUI|DORHPresentSupporterLicense|supporterLicensePressed/);
  assert.doesNotMatch(creditsPlist, /Supporter_Title|supporterLicensePressed|<string>supporter<\/string>/);
  assert.match(licenseUI, /DORHSupporterStoreActivationText/);
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

test('glass editing and jailbreak entry check entitlement while focus mode stays available', () => {
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
  assert.match(jailbreak, /requireCustomGlassSupporterAuthorization/);
  assert.match(home, /self\.jailbreakBtn\.enabled = DORHSupporterIsVerified\(\)/);
  assert.match(home, /self\.customGlassJailbreakDisabledOverlay\.hidden = supporterVerified/);
  const jailbreakAction = section(home, 'self.jailbreakBtn = [[DOJailbreakButton alloc]', 'self.jailbreakBtn.enabled =');
  assert.match(jailbreakAction, /requireCustomGlassSupporterAuthorization/);

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
