const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const test = require('node:test');

const root = path.resolve(__dirname, '..');
const ui = 'Application/Dopamine/UI/';
const read = (file) => fs.readFileSync(path.join(root, file), 'utf8');
const main = read(ui + 'DOMainViewController.m');
const navigation = read(ui + 'DONavigationController.m');
const settings = read(ui + 'Settings/DOSettingsController.m');
const credits = read(ui + 'Settings/DOCreditsViewController.m');
const header = read(ui + 'DOHeaderView.m');
const components = read(ui + 'DOCustomGlassView.m');
const material = read(ui + 'DOCustomGlassView.h');
const media = read(ui + 'DOCustomGlassMediaStore.h');
const sync = read(ui + 'DOCustomGlassThemeSync.h');
const project = read('Application/Dopamine.xcodeproj/project.pbxproj');
const startup = read('Application/Dopamine/main.m');

function section(source, start, end) {
  const a = source.indexOf(start);
  const b = source.indexOf(end, a + start.length);
  assert.ok(a >= 0 && b > a, `Missing section: ${start}`);
  return source.slice(a, b);
}

function fingerprint(source) {
  const normalized = source.split('\n').map(line => line.trimEnd()).join('\n').trim();
  return crypto.createHash('sha256').update(normalized).digest('hex');
}

test('jailbreak execution remains identical to the tested 1754adf6 baseline', () => {
  assert.equal(
    fingerprint(section(main, '- (void)startJailbreak', '-(void)setupUpdateAvailable:')),
    'a7372380df80f365d42d094ab0aea92ed7758b5adacd7d31c94890c1b0a521bb',
  );
  assert.equal(
    fingerprint(section(main, '- (NSString *)jailbreakButtonTitle', '// 读取含休眠时间')),
    '7a31c112fb7259e68c18924acb3834ed220ffe23ba2be8993f6ba4fc92d1ba88',
  );
});

test('glass presentation does not import licensing or the retired Metal overlay', () => {
  for (const source of [main, navigation, settings, components, material, media, sync, project]) {
    assert.doesNotMatch(source, /DORHSupporter|DOSupporterLicense|DOCustomGlassRefractionView/);
  }
  assert.match(main, /\[self setupCustomGlassHome\];/);
  assert.match(components, /@implementation DOCustomLiquidGlassView/);
  assert.match(components, /UIVisualEffectView/);
  assert.match(components, /CABackdropLayer/);
});

test('extracted glass components import their localization function declaration', () => {
  assert.match(components, /^#import "DOUIManager\.h"$/m);
  assert.match(read(ui + 'DOUIManager.h'), /NSString \*DOLocalizedString\(NSString \*string\);/);
});

test('material roles and the four RC9 appearance controls remain connected', () => {
  for (const key of ['BackgroundBlur', 'GlassBlurIntensity', 'GlassTransparency', 'GlassTintAlpha']) {
    assert.match(material, new RegExp(`DOCustomGlassTheme\\.${key}`));
  }
  assert.match(components, /Light Glass/);
  assert.match(components, /Dark Glass/);
  assert.match(components, /restoreRecommendedAppearanceValues/);
  assert.match(components, /DOCustomGlassApplyMainMaterialProfile\(self\.previewGlassView\)/);
  assert.match(main, /innerGlass\.suppressBackdrop = YES/);
});

test('uptime uses continuous time and localized full day-hour-minute units', () => {
  const duration = section(main, '- (NSString *)systemUptimeDescription', '- (void)refreshSystemUptime');
  assert.match(duration, /mach_continuous_time\(\)/);
  assert.match(duration, /NSCalendarUnitDay \| NSCalendarUnitHour \| NSCalendarUnitMinute/);
  assert.match(duration, /NSDateComponentsFormatterUnitsStyleFull/);
  assert.match(duration, /NSDateComponentsFormatterZeroFormattingBehaviorDropAll/);
  assert.match(duration, /Uptime_Less_Than_Minute/);
  assert.doesNotMatch(duration, /CLOCK_MONOTONIC_RAW|Uptime_Format|NSCalendarUnitSecond/);
  for (const locale of ['en', 'zh-Hans', 'zh-CN']) {
    assert.match(read(`Application/Dopamine/${locale}.lproj/Localizable.strings`), /"Uptime_Less_Than_Minute"\s*=/);
  }
});

test('the minute timer preserves weak ownership, lifecycle stops and aligned first fire', () => {
  const timer = section(main, '- (void)resumeSystemInformationUpdates', '- (void)startJailbreak');
  assert.match(timer, /if \(!self\.informationVisible\) return/);
  assert.match(timer, /UIApplicationStateActive/);
  assert.match(timer, /__weak typeof\(self\) weakSelf/);
  assert.match(timer, /timerWithTimeInterval:60/);
  assert.match(timer, /60 - \(seconds % 60\)/);
  assert.match(timer, /NSRunLoopCommonModes/);
  assert.match(timer, /viewWillDisappear:[\s\S]*\[self stopUptimeTimer\]/);
  assert.match(main, /UIApplicationWillResignActiveNotification/);
  assert.match(timer, /\[_uptimeTimer invalidate\]/);
});

test('home header has only version, credits and localized uptime', () => {
  const setup = section(main, 'DOHeaderView *headerView =', 'NSMutableArray<UIView *> *headerSubtitleLabels');
  assert.equal((setup.match(/\[DOGlobalAppearance (?:main|secondary)SubtitleString:/g) || []).length, 3);
  assert.match(setup, /versionSupportString/);
  assert.match(setup, /DOLocalizedString\(@"Credits_Made_By"\)/);
  assert.match(setup, /self\.systemUptimeLabel = \[headerView addSubtitle:/);
  assert.match(setup, /DOLocalizedString\(@"Home_Uptime_Format"\)/);
  assert.doesNotMatch(main, /appBuildInfoLabel|appBuildTimeLabel|systemVersionLabel|addInformationRowToHeader|DOBuildTimestamp/);
  for (const locale of ['en', 'zh-Hans', 'zh-CN'])
    assert.match(read(`Application/Dopamine/${locale}.lproj/Localizable.strings`), /"Home_Uptime_Format"\s*=\s*"[^"]*%@";/);
});

test('RC9 header centers the logo and a compact left-aligned information block without freezing its width', () => {
  const layout = section(header, '- (void)applyGlassLayoutWithLogoHeight:', '\n@end');
  assert.match(layout, /self\.logoHeightConstraint\.constant = height/);
  assert.match(layout, /deactivateConstraints:self\.subtitleWidthConstraints/);
  assert.match(layout, /self\.subtitleStack\.alignment = UIStackViewAlignmentCenter/);
  assert.match(layout, /information\.alignment = UIStackViewAlignmentFill/);
  assert.match(layout, /label\.textAlignment = NSTextAlignmentLeft/);
  assert.match(layout, /originalFont\.pointSize : 14\.0\) \* scale/);
  assert.match(layout, /information\.widthAnchor constraintLessThanOrEqualToAnchor:self\.subtitleStack\.widthAnchor/);
  assert.doesNotMatch(layout, /constraintEqualToConstant:subtitleWidth|glassLogoContainer|removeArrangedSubview:self\.logoView/);
  assert.match(main, /self\.systemUptimeLabel\.text =/);
});

test('home uses the RC9 safe-area layout instead of stretching or scaling a whole-page wrapper', () => {
  const setup = section(main, '- (void)setupCustomGlassHome', '- (NSString *)jailbreakButtonTitle');
  assert.match(setup, /CGFloat topInset = isPad \? 24\.0 : \(compactLayout \? 6\.0 : 10\.0\)/);
  assert.match(setup, /CGFloat horizontalInset = compactLayout \? 20\.0 : 25\.0/);
  assert.match(setup, /mainStack\.topAnchor constraintGreaterThanOrEqualToAnchor:safeArea\.topAnchor constant:topInset/);
  assert.match(setup, /mainStack\.bottomAnchor constraintLessThanOrEqualToAnchor:safeArea\.bottomAnchor constant:-8\.0/);
  assert.match(setup, /mainStack\.centerYAnchor constraintEqualToAnchor:safeArea\.centerYAnchor/);
  assert.match(setup, /mainStack\.centerYAnchor constraintEqualToAnchor:safeArea\.centerYAnchor constant:-10\.0/);
  assert.match(setup, /mainStack\.widthAnchor constraintEqualToAnchor:self\.view\.widthAnchor multiplier:0\.8/);
  assert.match(setup, /mainStack\.widthAnchor constraintLessThanOrEqualToConstant:UI_IPAD_MAX_WIDTH/);
  assert.doesNotMatch(main, /self\.contentView|MAX\(size\.height, availableHeight\)|systemLayoutSizeFittingSize:/);
});

test('RC9 action-panel dimensions and jailbreak-bar offsets are retained', () => {
  for (const declaration of [
    'CGFloat mainSpacing = compactLayout ? 8.0 : 12.0;',
    'CGFloat headerToProfileSpacing = isPad ? 29.0 : (compactLayout ? 14.0 : 18.0);',
    'CGFloat avatarSize = isPad ? 104.0 : (compactLayout ? 72.0 : 84.0);',
    'CGFloat gridHeight = isPad ? 300.0 : (compactLayout ? 214.0 : 250.0);',
    'CGFloat themeCardHeight = isPad ? 60.0 : (compactLayout ? 48.0 : 52.0);',
    'CGFloat leftColumnWidthMultiplier = isPad ? 0.34 : 0.35;',
    'CGFloat jailbreakVerticalOffset = isPad ? -12.0 : (compactLayout ? -24.0 : -30.0);',
    'CGFloat updateReserveHeight = ([DOGlobalAppearance isHomeButtonDevice] ? 42.0 : 52.0) - gridDrop;',
  ]) assert.ok(main.includes(declaration), declaration);
  assert.match(main, /self\.jailbreakBtn\.centerYAnchor constraintEqualToAnchor:buttonPlaceHolder\.centerYAnchor constant:jailbreakVerticalOffset/);
});

test('jailbreak entry preserves other-jailbreak guard and root-coordinate expansion', () => {
  const click = section(main, 'self.jailbreakBtn = [[DOJailbreakButton alloc]', 'self.jailbreakBtn.enabled =');
  const positions = [
    'otherJailbreakActived(false)', 'customGlassPauseForJailbreak',
    'convertRect:self.jailbreakBtn.bounds toView:self.view',
    '[NSLayoutConstraint deactivateConstraints:self.jailbreakButtonConstraints]',
    '[self.view addSubview:self.jailbreakBtn]',
    '[self.jailbreakBtn expandButton:self.jailbreakButtonConstraints]',
    '[self startJailbreak]',
  ].map(token => {
    const index = click.indexOf(token);
    assert.ok(index >= 0, token);
    return index;
  });
  assert.deepEqual(positions, [...positions].sort((a, b) => a - b));
  assert.match(main, /updateButton\.bottomAnchor constraintEqualToAnchor:self\.jailbreakBtn\.topAnchor constant:-12/);
});

test('profile editing and focus mode are retained', () => {
  for (const selector of [
    'presentCustomGlassAvatarPicker', 'presentCustomGlassUsernameEditor',
    'presentCustomGlassMottoEditor', 'customGlassAvatarPanned',
    'setCustomGlassProfileFocusEnabled',
  ]) assert.ok(main.includes(selector), selector);
  assert.match(main, /DOCustomGlassMediaStoreSaveAvatar/);
  assert.match(material, /DOCustomGlassTheme\.ProfileFocusEnabled/);
});

test('username and motto editors use saved user input rather than treating placeholders as entered data', () => {
  const username = section(main, '- (void)presentCustomGlassUsernameEditor', '- (void)customGlassUsernameTextChanged:');
  assert.match(username, /currentUsername = \[NSUserDefaults\.standardUserDefaults stringForKey:DOCustomGlassUsernameKey\] \?: @""/);
  assert.match(username, /textField\.text = currentUsername/);
  assert.match(username, /setObject:username forKey:DOCustomGlassUsernameKey/);
  const motto = section(main, '- (void)presentCustomGlassMottoEditor', '- (void)customGlassMottoTextChanged:');
  assert.match(motto, /currentMotto = \[NSUserDefaults\.standardUserDefaults stringForKey:DOCustomGlassMottoKey\] \?: @""/);
  assert.match(motto, /textField\.text = currentMotto/);
  assert.match(motto, /setObject:motto forKey:DOCustomGlassMottoKey/);
  assert.match(main, /initWithTarget:self action:@selector\(presentCustomGlassUsernameEditor\)/);
  assert.match(main, /initWithTarget:self action:@selector\(presentCustomGlassMottoEditor\)/);
});

test('avatar focus retains root-edge docking, alpha-based hiding and restoration hooks', () => {
  // These source hooks do not establish frame invariance. The health audit
  // identifies a separate profile-height dependency that requires a layout fix.
  const focus = section(main, '- (void)setCustomGlassProfileFocusEnabled:', '- (void)configureCustomGlassHeaderView:');
  assert.match(focus, /for \(UIView \*label in self\.customGlassHeaderSubtitleLabels\)[\s\S]*?label\.alpha = detailAlpha/);
  assert.match(focus, /self\.customGlassUsernameLabel\.alpha = detailAlpha/);
  assert.match(focus, /self\.customGlassMottoLabel\.alpha = detailAlpha/);
  assert.match(focus, /CGRect screenFrame = self\.view\.bounds/);
  assert.match(focus, /translationInView:self\.view/);
  assert.match(focus, /fabs\(translation\.x\) >= 28\.0/);
  assert.match(focus, /if \(self\.customGlassProfileFocusEnabled\)/);
  assert.match(main, /avatarGlass\.centerXAnchor constraintEqualToAnchor:self\.view\.leadingAnchor/);
  assert.match(main, /avatarGlass\.centerXAnchor constraintEqualToAnchor:self\.view\.trailingAnchor/);
  assert.doesNotMatch(focus, /mainStack|setCustomSpacing|\.hidden\s*=/);
});

test('shared wallpaper handles images, video and Live Photo with persisted speed', () => {
  assert.match(components, /PHPickerFilter livePhotosFilter/);
  assert.match(components, /DOCustomGlassExportLivePhoto/);
  assert.match(components, /DOCustomGlassMediaStoreSaveWallpaperVideo/);
  assert.match(navigation, /AVPlayerLooper/);
  assert.match(navigation, /player\.muted = YES/);
  assert.match(navigation, /preventsDisplaySleepDuringVideoPlayback = NO/);
  assert.match(navigation, /playImmediatelyAtRate:/);
  assert.match(material, /WallpaperPlaybackRateDefault = 0\.65/);
});

test('video playback retires with its window and cannot resume during jailbreak', () => {
  assert.match(navigation, /customGlassWallpaperSuspended \|\|/);
  assert.match(navigation, /window\.rootViewController != self/);
  assert.match(navigation, /UISceneActivationStateForegroundActive/);
  assert.match(navigation, /UIApplicationWillResignActiveNotification/);
  assert.match(navigation, /customGlassPauseForJailbreak[\s\S]*customGlassWallpaperSuspended = YES/);
  const scene = read('Application/Dopamine/App Delegates/DOSceneDelegate.m');
  assert.equal((scene.match(/customGlassPrepareForWindowReplacement/g) || []).length, 2);
  assert.match(scene, /oldWindow\.rootViewController = nil/);
});

test('new theme persistence is isolated from RC9 and bootstraps before UIApplicationMain', () => {
  assert.match(sync, /Application Support\/DopamineRH-iOS16/);
  assert.doesNotMatch(sync, /@"\/var\/mobile\/Library\/Application Support\/DopamineRH"/);
  assert.match(sync, /hasPrefix:DOCustomGlassThemeSyncPrefix/);
  assert.match(sync, /external\[DOCustomGlassThemeSyncVersionKey\] != nil/);
  assert.match(sync, /if \(!merged\[key\]\)/);
  assert.ok(startup.indexOf('DOCustomGlassThemeSyncBootstrap();') < startup.indexOf('return UIApplicationMain('));
});

test('media validates app-container ownership and local-defaults-before-delete ordering', () => {
  assert.match(media, /NSBundle\.mainBundle\.bundleIdentifier/);
  assert.match(media, /DOCustomGlassMediaStoreLSContainerURL\(bundleIdentifier\)/);
  assert.match(media, /DOCustomGlassMediaStoreMCMContainerURL\(bundleIdentifier\)/);
  assert.match(media, /filename\.lastPathComponent/);
  const image = section(media, 'static inline BOOL DOCustomGlassMediaStoreSaveImage', 'static inline UIImage *DOCustomGlassMediaStoreLoadAvatar');
  const operations = ['writeToURL:newURL', 'dataWithContentsOfURL:newURL',
    'if (!decodedImage)', '[defaults setObject:newFilename forKey:defaultsKey]',
    'if (![committedFilename isEqualToString:newFilename])', 'removeItemAtURL:oldURL'];
  const positions = operations.map(token => {
    const index = image.indexOf(token);
    assert.ok(index >= 0, token);
    return index;
  });
  assert.deepEqual(positions, [...positions].sort((a, b) => a - b));
});

test('only the purple fallback theme and primary icon remain', () => {
  const themes = read(ui + 'Themes/Themes.plist');
  assert.equal((themes.match(/<dict>/g) || []).length, 1);
  assert.match(themes, /<string>purple<\/string>/);
  assert.match(themes, /Background_Purple\.jpg/);
  const assets = 'Application/Dopamine/Assets.xcassets/';
  for (const set of [
    'Background/Background_Green.imageset', 'Background/Background_ElleKit.imageset',
    'Background/Background_Blue.imageset', 'Background/Background_Red.imageset',
    'AppIcon_Blue.appiconset', 'AppIcon_ElleKit.appiconset',
    'AppIcon_Red.appiconset', 'AppIcon_Purple.appiconset',
  ]) assert.equal(fs.existsSync(path.join(root, assets, set)), false, set);
  for (const set of ['AppIcon.appiconset', 'Background/Background_Purple.imageset']) {
    const contents = path.join(root, assets, set, 'Contents.json');
    const catalog = JSON.parse(fs.readFileSync(contents, 'utf8'));
    for (const image of catalog.images.filter(item => item.filename)) {
      assert.ok(fs.existsSync(path.join(path.dirname(contents), image.filename)), image.filename);
    }
  }
  assert.doesNotMatch(project, /ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES/);
});

test('primary app icon files match the RC9 source snapshot', () => {
  const directory = path.join(root, 'Application/Dopamine/Assets.xcassets/AppIcon.appiconset');
  const expected = {
    'Contents.json': '43b8c2a5712feba25572215c427ebcb7fb1e4c19da45e874ecb56a469754e0d7',
    'Icon-38@2x.png': '1b1617c558f824d103390ee3648797724d750d29190b06cee4fa10f9583a99bc',
    'Icon-38@3x.png': 'a3d85243f152056ad95b0f98fd479b4ab2c01467793ef3419504f5dbc1564279',
    'Icon-60@3x.png': '37683d6e2f5b5a6481c7944811470e6dae6e4686b6b68457427b53e0e875b490',
    'Icon-64@2x.png': '546c55df209f98ee6a96c6389f0a55590cd0ea827b030f292f075d61884cb429',
    'Icon-64@3x.png': 'f15f69564c1fbca6405866e8de3dd105bfd7f30a7b57dd751383200bad9eeaf6',
    'Icon-68@2x.png': 'f8c470445a5111a8ef29df324f7c937ec53bf19618064413fdfbd6ac32268718',
    'Icon-76@2x.png': '5209ec0cc8c9163a5f9cf25e52c2bc4b69b9facc61b3f7380af01bbcf8371f75',
    'Icon-83.5@2x.png': '2821e251aa3cdeac1c16830edefefc97ee1c50aa377b39bd39528b195beef89d',
    'Icon-Notification@2x.png': '64b263a0fe612b3434cad1bcca8a79ebc8250fab4470d1216bc7f308f48bbd42',
    'Icon-Notification@3x.png': '4a870f53c9a8a0352c8f710ce36089d7660f8e4ebd847756e33c0ffa89f1c099',
    'Icon-Small-40@2x.png': 'b3a9d186840518e78503aec89e534dbd952561dd2c7931574d7a502c2f27df1d',
    'Icon-Small-40@3x 1.png': '149adccff014812250a50def780f6d133734af7ce3788eeff799ebc34d45c51e',
    'Icon-Small-40@3x.png': '149adccff014812250a50def780f6d133734af7ce3788eeff799ebc34d45c51e',
    'Icon-Small@2x.png': '7c0a68d7ca50c3ea971dc4fa7a755f457b7cd39882e3375342fbe3e5c26c5943',
    'Icon-Small@3x.png': '6f355906b1234847599033561123dfc2c3766c403d59fa1b048bc543f28d6568',
  };
  assert.deepEqual(fs.readdirSync(directory).sort(), Object.keys(expected).sort());
  for (const [file, hash] of Object.entries(expected)) {
    const bytes = fs.readFileSync(path.join(directory, file));
    assert.equal(crypto.createHash('sha256').update(bytes).digest('hex'), hash, file);
  }
  const catalog = JSON.parse(fs.readFileSync(path.join(directory, 'Contents.json'), 'utf8'));
  for (const image of catalog.images.filter(item => item.filename)) {
    const bytes = fs.readFileSync(path.join(directory, image.filename));
    assert.equal(bytes.subarray(0, 8).toString('hex'), '89504e470d0a1a0a', image.filename);
    const [width, height] = image.size.split('x').map(Number);
    const scale = Number.parseFloat(image.scale);
    assert.equal(bytes.readUInt32BE(16), width * scale, `${image.filename}: width`);
    assert.equal(bytes.readUInt32BE(20), height * scale, `${image.filename}: height`);
  }
  assert.equal((project.match(/ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;/g) || []).length, 2);
});

test('glass slider notifications do not reload wallpaper files in navigation', () => {
  assert.doesNotMatch(navigation, /customGlassThemeDidChange:|DOCustomGlassThemeDidChangeNotification/);
  assert.match(components, /\[self\.navigationController customGlassApplySharedBackgroundBlurIntensity:backgroundBlur\]/);
  assert.match(components, /\[weakSelf\.navigationController customGlassRefreshSharedBackground\]/);
});

test('stale theme selection falls back safely and the old settings picker is gone', () => {
  assert.match(read(ui + 'Themes/DOThemeManager.m'), /isKindOfClass:NSString\.class/);
  assert.match(read(ui + 'Themes/DOThemeManager.m'), /setPreferenceValue:theme\.key forKey:@"theme"/);
  assert.doesNotMatch(read(ui + 'Settings/DOSettingsController.m'), /themeSpecifier|setAlternateIconName|_lastKnownTheme/);
  assert.match(main, /setAlternateIconName:nil/);
  assert.match(read(ui + 'Themes/DOTheme.m'), /generateBootLogo/);
});

test('settings presentation leaves all existing specifiers, actions and preferences unchanged', () => {
  assert.equal(
    fingerprint(settings.slice(settings.indexOf('- (NSArray *)availableKernelExploitIdentifiers'))),
    'c6f43eee7638c83d4ecc9c91a3d2af8477d5ccea2b0ea4c2ff2b39bc95680c32',
  );
});

test('the reboot card and its confirmation have localized copy instead of raw keys', () => {
  assert.match(main, /customGlassRestartButtonWithTitle:DOLocalizedString\(@"Menu_Reboot_Device_Title"\)/);
  for (const locale of ['en', 'zh-Hans', 'zh-CN']) {
    const strings = read(`Application/Dopamine/${locale}.lproj/Localizable.strings`);
    for (const key of ['Menu_Reboot_Device_Title', 'Alert_Reboot_Device_Body', 'Button_Reboot']) {
      const values = [...strings.matchAll(new RegExp(`^"${key}"\\s*=\\s*"((?:\\\\.|[^"\\\\])*)";`, 'gm'))];
      assert.equal(values.length, 1, `${locale}: ${key} must appear exactly once`);
      assert.ok(values[0][1].length > 0, `${locale}: ${key} is empty`);
      assert.notEqual(values[0][1], key, `${locale}: ${key} is untranslated`);
    }
  }
});

test('settings has a fixed accessible 44-point back button and left-edge return', () => {
  const load = section(settings, '- (void)viewDidLoad', '- (void)customGlassBackPressed');
  assert.match(load, /customGlassBackButton = backButton/);
  assert.match(load, /backButton\.accessibilityLabel = DOLocalizedString\(@"Button_Back"\)/);
  assert.match(load, /widthAnchor constraintEqualToConstant:44\.0/);
  assert.match(load, /heightAnchor constraintEqualToConstant:44\.0/);
  assert.match(load, /safeAreaLayoutGuide\.topAnchor constant:6\.0/);
  assert.match(load, /edgeGesture\.edges = UIRectEdgeLeft/);
  assert.match(load, /requireGestureRecognizerToFail:edgeGesture/);
  const back = section(settings, '- (void)customGlassBackPressed', '- (void)customGlassStyleContent:');
  assert.match(back, /topViewController == self/);
  assert.match(back, /popViewControllerAnimated:YES/);
  assert.match(back, /UIGestureRecognizerStateEnded/);
  assert.doesNotMatch(back, /NSUserDefaults|DORHSupporter|reloadMaterial/);
  for (const locale of ['en', 'zh-Hans', 'zh-CN'])
    assert.match(read(`Application/Dopamine/${locale}.lproj/Localizable.strings`), /"Button_Back"\s*=\s*"(?:Back|返回)";/);
});

test('settings and credits gain full-screen framing without changing other Preferences pages', () => {
  const classification = section(navigation, '- (BOOL)isCustomGlassFullScreenViewController:', '- (void)viewDidLoad');
  assert.match(navigation, /^#import "DOSettingsController\.h"$/m);
  assert.match(classification, /isKindOfClass:DOSettingsController\.class/);
  assert.match(navigation, /^#import "DOCreditsViewController\.h"$/m);
  assert.match(classification, /isKindOfClass:DOCreditsViewController\.class/);
  assert.doesNotMatch(classification, /DOPSListController\.class|DOLicenseViewController\.class/);
  assert.match(section(navigation, '-(CGRect)_frameForViewController:(id)viewController', '\n@end'), /isCustomGlassFullScreenViewController:viewController/);
  const layout = section(settings, '- (void)viewDidLayoutSubviews', '- (void)tableView:');
  assert.match(layout, /safeArea\.top \+ 56\.0/);
  assert.match(layout, /MIN\(620\.0, availableWidth - 24\.0\)/);
  assert.match(layout, /- top - safeArea\.bottom/);
  // Existing Preferences selection pages retain their own return path.
  const items = read(ui + 'Settings/PSLists/DOPSListItemsController.m');
  assert.match(items, /addTarget:target action:@selector\(dismiss\)/);
  assert.match(items, /\[self\.navigationController popViewControllerAnimated:YES\]/);
});

test('settings uses one RC9 glass surface per section without replacing controls or data sources', () => {
  assert.match(settings, /^#import "DOCustomGlassView\.h"$/m);
  assert.match(settings, /self\.view\.backgroundColor = UIColor\.clearColor/);
  assert.match(settings, /self\.view\.layer\.masksToBounds = NO/);
  assert.match(settings, /_table\.opaque = NO/);
  assert.match(settings, /_table\.backgroundView = nil/);
  assert.match(settings, /UITableViewCellSeparatorStyleNone/);
  assert.match(settings, /self\.customGlassSectionBackdrops\[key\]/);
  assert.match(settings, /CGRectUnion\(firstRect, lastRect\)/);
  assert.match(settings, /initWithCornerRadius:18\.0 baseTintAlpha:0\.038/);
  assert.match(settings, /glass\.materialScale = 0\.88/);
  assert.match(settings, /glass\.userInteractionEnabled = NO/);
  assert.match(settings, /\[_table sendSubviewToBack:glass\]/);
  assert.match(settings, /removeObjectForKey:key/);
  assert.match(settings, /isKindOfClass:UISwitch\.class/);
  assert.match(settings, /isKindOfClass:UISlider\.class/);
  assert.doesNotMatch(settings, /_table\.(?:delegate|dataSource)\s*=/);
});

test('settings refreshes reused cells, layout and theme changes without retaining its controller', () => {
  assert.match(settings, /name:DOCustomGlassThemeDidChangeNotification/);
  assert.match(settings, /if \(!NSThread\.isMainThread\)/);
  assert.match(settings, /__weak typeof\(self\) weakSelf/);
  assert.match(settings, /__weak UITableViewCell \*weakCell/);
  assert.match(settings, /indexPathForCell:visibleCell/);
  assert.match(settings, /willDisplayHeaderView:/);
  assert.match(settings, /willDisplayFooterView:/);
  assert.match(settings, /bringSubviewToFront:self\.customGlassBackButton/);
  const cleanup = section(settings, '- (void)dealloc', '- (NSArray *)availableKernelExploitIdentifiers');
  assert.match(cleanup, /removeObserver:self/);
  assert.match(cleanup, /name:DOCustomGlassThemeDidChangeNotification/);
});

test('credits has an accessible fixed back button and an edge return independent of the hidden navigation bar', () => {
  const load = section(credits, '- (void)viewDidLoad', '- (void)backPressed');
  assert.match(load, /self\.backButton = backButton/);
  assert.match(load, /backButton\.accessibilityLabel = DOLocalizedString\(@"Button_Back"\)/);
  assert.match(load, /widthAnchor constraintEqualToConstant:44\.0/);
  assert.match(load, /heightAnchor constraintEqualToConstant:44\.0/);
  assert.match(load, /safeAreaLayoutGuide\.topAnchor constant:6\.0/);
  assert.match(load, /\[self\.view addSubview:backButton\]/);
  assert.match(load, /edgeGesture\.edges = UIRectEdgeLeft/);
  assert.match(load, /requireGestureRecognizerToFail:edgeGesture/);
  const back = section(credits, '- (void)backPressed', '- (void)viewDidLayoutSubviews');
  assert.match(back, /topViewController == self/);
  assert.match(back, /popViewControllerAnimated:YES/);
  assert.match(back, /UIGestureRecognizerStateEnded/);
  assert.doesNotMatch(back, /NSUserDefaults|DORHSupporter|reloadMaterial/);
  const layout = section(credits, '- (void)viewDidLayoutSubviews', '- (id)specifiers');
  assert.match(layout, /\[super viewDidLayoutSubviews\]/);
  assert.match(layout, /safeArea\.top \+ 56\.0/);
  assert.match(layout, /- top - safeArea\.bottom - 5\.0/);
  assert.match(layout, /bringSubviewToFront:self\.backButton/);
});

test('credits content and license-to-credits return remain intact', () => {
  assert.equal(
    fingerprint(credits.slice(credits.indexOf('- (id)specifiers'))),
    '98ca746c282da993c08bdaff16d45eca7affb0051f9457b8044f64f32930a781',
  );
  const license = read(ui + 'Settings/DOLicenseViewController.m');
  assert.match(license, /makeHeader:DOLocalizedString\(@"Credits_Button_License"\) withTarget:self/);
  assert.match(license, /- \(void\)dismiss[\s\S]*?popViewControllerAnimated:YES/);
  assert.match(credits, /pushViewController:\[\[DOLicenseViewController alloc\] init\]/);
});

test('credits uses shared glass without replacing its content or collection delegates', () => {
  assert.match(credits, /^#import "DOCustomGlassView\.h"$/m);
  assert.match(credits, /self\.view\.backgroundColor = UIColor\.clearColor/);
  assert.match(credits, /self\.view\.layer\.masksToBounds = NO/);
  assert.match(credits, /_table\.opaque = NO/);
  assert.match(credits, /UITableViewCellSeparatorStyleNone/);
  assert.match(credits, /initWithCornerRadius:18\.0 baseTintAlpha:0\.038/);
  assert.match(credits, /glass\.materialScale = 0\.88/);
  assert.match(credits, /glass\.userInteractionEnabled = NO/);
  assert.match(credits, /\[_table sendSubviewToBack:glass\]/);
  assert.match(credits, /MIN\(620\.0, availableWidth - 24\.0\)/);
  assert.doesNotMatch(credits, /(?:_table|collectionView)\.(?:delegate|dataSource)\s*=/);
  assert.doesNotMatch(credits, /DORHSupporter|DOCustomGlassMediaStoreSave|setObject:.*forKey:/);
});

test('credits glass includes header-only contributor sections and cleans up obsolete surfaces', () => {
  const backdrops = section(credits, '- (void)customGlassRefreshSectionBackdrops', '- (void)customGlassRefreshPageAppearance');
  assert.match(backdrops, /rectForHeaderInSection:section/);
  assert.match(backdrops, /if \(rows > 0\)/);
  assert.match(backdrops, /CGRectUnion\(rect, CGRectUnion\(firstRect, lastRect\)\)/);
  assert.doesNotMatch(backdrops, /if \(rows == 0\)/);
  assert.match(backdrops, /CGRectIsNull\(rect\)/);
  assert.match(backdrops, /removeObjectForKey:key/);
  const content = read(ui + 'Settings/Credits.plist');
  assert.match(content, /<string>DOCreditsCell<\/string>/);
  assert.match(content, /<key>names<\/key>/);
});

test('credits refreshes reused content and theme changes with weak callbacks and observer cleanup', () => {
  assert.match(credits, /willDisplayCell:/);
  assert.match(credits, /willDisplayHeaderView:/);
  assert.match(credits, /willDisplayFooterView:/);
  assert.match(credits, /__weak typeof\(self\) weakSelf/);
  assert.match(credits, /__weak UITableViewCell \*weakCell/);
  assert.match(credits, /indexPathForCell:visibleCell/);
  assert.match(credits, /if \(!NSThread\.isMainThread\)/);
  assert.match(credits, /configuration\.baseForegroundColor = UIColor\.whiteColor/);
  assert.match(section(credits, '- (void)dealloc', '- (id)specifiers'), /removeObserver:self/);
  assert.match(section(credits, '- (void)dealloc', '- (id)specifiers'), /name:DOCustomGlassThemeDidChangeNotification/);
});

test('new source and required system frameworks are in the app build phases', () => {
  assert.match(project, /A91611040000000000000001 \/\* DOCustomGlassView\.m in Sources \*\/,/);
  for (const framework of ['AVFoundation', 'Photos', 'PhotosUI', 'CoreImage', 'QuartzCore']) {
    assert.ok(project.includes(`${framework}.framework in Frameworks */ ,`) ||
      project.includes(`${framework}.framework in Frameworks */,`), framework);
    assert.ok(project.includes(`System/Library/Frameworks/${framework}.framework`), framework);
  }
  const definitions = [...project.matchAll(/^\s*([A-F0-9]{24}) \/\* [^\n]+ \*\/ = \{/gm)].map(match => match[1]);
  assert.equal(new Set(definitions).size, definitions.length, 'Duplicate Xcode object definitions');
});

test('ported Objective-C files have balanced delimiters and no duplicate method definitions per class', () => {
  for (const file of [
    'DOMainViewController.m', 'DONavigationController.m',
    'DOCustomGlassView.h', 'DOCustomGlassView.m',
    'DOCustomGlassMediaStore.h', 'DOCustomGlassThemeSync.h', 'DOHeaderView.m',
    'Settings/DOSettingsController.m', 'Settings/DOCreditsViewController.m',
  ]) {
    const source = read(ui + file).replace(
      /\/\*[\s\S]*?\*\/|\/\/[^\n]*|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'/g, '',
    );
    const stack = [];
    for (const char of source) {
      if ('({['.includes(char)) stack.push(char);
      if (')}]'.includes(char)) {
        assert.equal(stack.pop(), { ')': '(', '}': '{', ']': '[' }[char], `${file}: unmatched ${char}`);
      }
    }
    assert.equal(stack.length, 0, `${file}: unclosed delimiters`);
    for (const implementation of source.matchAll(/@implementation ([^\n]+)([\s\S]*?)@end/g)) {
      const selectors = [...implementation[2].matchAll(/^[-+]\s*\([^)]+\)\s*([^{;]+)\{/gm)].map(match => {
        const args = [...match[1].matchAll(/(\w+)\s*:/g)].map(arg => arg[1] + ':');
        return args.length ? args.join('') : match[1].trim();
      });
      assert.equal(new Set(selectors).size, selectors.length, `${file}: duplicate selector in ${implementation[1]}`);
    }
  }
});
