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
const environment = read('Application/Dopamine/Jailbreak/DOEnvironmentManager.m');
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

test('homepage action wiring preserves the baseline except for the removed A8-only notice', () => {
  // The iOS 16 projection removes only the A8 CPU lookup and notice append.
  assert.equal(
    fingerprint(section(main, '- (void)startJailbreak', '-(void)setupUpdateAvailable:')),
    'af93af210e873720636064bcc8f1e51685810675db6d7fd0b23e31b8a1ce089a',
  );
  assert.doesNotMatch(main, /CPUFAMILY_ARM_TYPHOON|Respring_Required_Notice_A8/);
  assert.equal(
    fingerprint(section(main, '- (NSString *)jailbreakButtonTitle', '// 读取含休眠时间')),
    '7a31c112fb7259e68c18924acb3834ed220ffe23ba2be8993f6ba4fc92d1ba88',
  );
});

test('glass presentation keeps shared materials and does not use the retired Metal overlay', () => {
  for (const source of [material, media, sync, project])
    assert.doesNotMatch(source, /DORHSupporter|DOSupporterLicense|DOCustomGlassRefractionView/);
  assert.match(navigation, /DORHSupporterIsVerified/);
  assert.doesNotMatch(navigation, /DOCustomGlassRefractionView/);
  assert.doesNotMatch(components, /DOCustomGlassRefractionView/);
  assert.match(settings, /DOCustomGlassThemeDidChangeNotification/);
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

test('profile system line displays the live injection mode only while jailbroken', () => {
  const mode = section(environment, '- (NSString *)injectionModeDescription', '// 读取当前 Sileo');
  assert.match(mode, /cn\.zqbb\.inject\.plist/);
  assert.match(mode, /whitelist \? @"Whitelist" : @"Blacklist"/);

  const refresh = section(main, '- (void)refreshCustomGlassSystemLabel', '- (void)supporterLicenseDidChange:');
  assert.match(refresh, /iOS %@/);
  assert.match(refresh, /environment\.isJailbroken/);
  assert.match(refresh, /%@ \| %@/);
  assert.match(refresh, /injectionModeDescription/);
  assert.match(refresh, /else \{[\s\S]*self\.customGlassSystemLabel\.text = systemVersion/);
  const resume = section(main, '- (void)resumeSystemInformationUpdates', '- (void)stopUptimeTimer');
  assert.match(resume, /refreshCustomGlassSystemLabel/);
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

test('video wallpaper skips full-screen blur and pauses outside the active foreground', () => {
  const blur = section(
    navigation,
    '- (void)customGlassApplySharedBackgroundBlurIntensity:',
    '- (void)customGlassRefreshSharedBackground',
  );
  assert.match(blur, /if \(self\.customGlassUsingVideoWallpaper\)[\s\S]*?customGlassVideoWallpaperBlurView\.blurIntensity = 0\.0;[\s\S]*?customGlassVideoWallpaperBlurView\.hidden = YES;[\s\S]*?return;/);

  const resume = section(
    navigation,
    '- (void)customGlassResumeVideoWallpaperPlayback',
    '- (BOOL)customGlassIsUsingVideoWallpaper',
  );
  for (const guard of [
    'customGlassWallpaperPlaybackRetired',
    'customGlassWallpaperSuspended',
    '!self.customGlassWallpaperViewVisible',
    '!window || window.hidden',
    'window.rootViewController != self',
    'windowScene.activationState != UISceneActivationStateForegroundActive',
    'UIApplication.sharedApplication.applicationState != UIApplicationStateActive',
  ]) assert.ok(resume.includes(guard), guard);
  assert.match(resume, /\[self\.customGlassWallpaperPlayer pause\]/);
  assert.match(resume, /playImmediatelyAtRate:/);

  const resign = section(
    navigation,
    '- (void)customGlassHandleApplicationWillResignActive:(NSNotification *)notification\n{',
    '- (void)customGlassHandleApplicationDidBecomeActive:(NSNotification *)notification\n{',
  );
  assert.match(resign, /UISceneWillDeactivateNotification/);
  assert.match(resign, /\[self\.customGlassWallpaperPlayer pause\]/);
  assert.match(navigation, /- \(void\)viewWillDisappear:[\s\S]*?customGlassWallpaperViewVisible = NO;[\s\S]*?\[self\.customGlassWallpaperPlayer pause\]/);
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

test('media validates ownership and commits authoritative references before deleting old files', () => {
  assert.match(media, /NSBundle\.mainBundle\.bundleIdentifier/);
  assert.match(media, /DOCustomGlassMediaStoreLSContainerURL\(bundleIdentifier\)/);
  assert.match(media, /DOCustomGlassMediaStoreMCMContainerURL\(bundleIdentifier\)/);
  assert.match(media, /filename\.lastPathComponent/);
  const image = section(media, 'static inline NSString *DOCustomGlassMediaStoreStageImage', 'static inline UIImage *DOCustomGlassMediaStoreLoadAvatar');
  const operations = ['writeToURL:newURL', 'dataWithContentsOfURL:newURL', 'if (!decodedImage)'];
  const positions = operations.map(token => {
    const index = image.indexOf(token);
    assert.ok(index >= 0, token);
    return index;
  });
  assert.deepEqual(positions, [...positions].sort((a, b) => a - b));
  const commit = section(media, 'static inline BOOL DOCustomGlassMediaStoreCommit', 'static inline NSString *DOCustomGlassMediaStoreStageImage');
  assert.ok(commit.indexOf('DOCustomGlassThemeSyncCommitChanges(changes)') < commit.indexOf('for (NSString *filename in replacedFiles)'));
  assert.match(commit, /@synchronized\(NSUserDefaults\.class\)/);
  assert.match(commit, /request\.cancelled/);
  const themeCommit = section(sync, 'static inline BOOL DOCustomGlassThemeSyncCommitChanges', 'static inline void DOCustomGlassThemeSyncFlush');
  assert.ok(themeCommit.indexOf('DOCustomGlassThemeSyncWrite(snapshot)') < themeCommit.indexOf('[defaults setObject:value'));
  assert.match(section(sync, 'static inline void DOCustomGlassThemeSyncFlush', '// Call once from main'), /@synchronized\(NSUserDefaults\.class\)/);
});

test('media imports cancel prior requests and never publish stale completions after page retirement', () => {
  for (const [source, property] of [[main, 'customGlassAvatarImport'], [components, 'wallpaperImport']]) {
    const picker = section(source, '- (void)picker:', source === main ?
      '- (void)presentCustomGlassUsernameEditor' : '- (void)showThemePlaceholderForTitle:');
    assert.match(picker, new RegExp(`@synchronized\\(NSUserDefaults\\.class\\) \\{\\s*\\[self\\.${property} cancel\\]`));
    assert.match(picker, /request\.cancelled/);
    assert.match(source, new RegExp(`\\[_${property} cancel\\]`));
  }
  assert.match(components, /isMovingFromParentViewController \|\| self\.isBeingDismissed/);
  assert.doesNotMatch(media, /DOCustomGlassMediaStoreClearWallpaperVideo|DOCustomGlassMediaStoreSaveImage\(/);
});

test('blur coalesces unchanged inputs and cancels obsolete work before rendering', () => {
  const blur = section(navigation, '- (void)customGlassApplySharedBackgroundBlurIntensity:', '- (void)supporterLicenseDidChange:');
  assert.match(blur, /sourceImage == self\.customGlassBackgroundBlurRequestedImage/);
  assert.match(blur, /queue\.maxConcurrentOperationCount = 1/);
  assert.ok(blur.indexOf('activeOperation.cancelled') < blur.indexOf('DOCustomGlassNavigationCreateBlurredImage(sourceImage'));
  assert.match(blur, /generation != strongSelf\.customGlassBackgroundBlurGeneration/);
  assert.match(blur, /sourceImage != strongSelf\.customGlassBackgroundSourceImage/);
  assert.match(navigation, /customGlassPauseForJailbreak[\s\S]*?cancelAllOperations/);
});

test('maintenance uses this jailbreak and restores the faded interface when commands fail', () => {
  const actions = section(main, 'BOOL isJailbroken =', '// Keep a dedicated gap');
  assert.doesNotMatch(actions, /isJailbrokenWithOtherJailbreak/);
  assert.equal((actions.match(/performCustomGlassMaintenance:/g) || []).length, 3);
  const maintenance = section(main, '- (void)performCustomGlassMaintenance:', '#pragma mark - Action Menu Delegate');
  for (const token of ['int result = operation()', 'self.didFade = NO', 'mainView.transform = transform',
    'mainView.alpha = alpha', 'mainView.userInteractionEnabled = interactionEnabled', 'Maintenance_Failed'])
    assert.ok(maintenance.includes(token), token);
  assert.doesNotMatch(maintenance, /static bool didFade/);
  const spawn = section(environment, '- (int)spawnJbctlAsRootWithArgs:', '- (int)runTrollStoreAction:');
  assert.match(spawn, /if \(r != 0 \|\| pid <= 0\)/);
  assert.match(spawn, /needsLegacySolution && r == 0 && pid > 0/);
  assert.match(spawn, /pipe\(waitPipe\) != 0/);
  for (const locale of ['en', 'zh-Hans', 'zh-CN'])
    assert.match(read(`Application/Dopamine/${locale}.lproj/Localizable.strings`), /"Maintenance_Failed"\s*=/);
});

test('mount tasks spawn in the existing privilege scope and wait outside it with reentry protection', () => {
  const task = section(environment, '- (void)runCustomMountCommand:', '- (BOOL)removeCustomMountCopyAtPath:');
  assert.match(task, /self\.customMountTaskRunning = YES/);
  assert.match(task, /exec_cmd_nowait\(&child/);
  assert.ok(task.indexOf('exec_cmd_nowait') < task.indexOf('dispatch_get_global_queue'));
  assert.ok(task.indexOf('dispatch_get_global_queue') < task.indexOf('waitpid(child'));
  assert.match(task, /errno == EINTR/);
  assert.match(task, /dispatch_get_main_queue\(\), \^\{\s*self\.customMountTaskRunning = NO;\s*completion\(result\)/);
  assert.match(settings, /self\.view\.userInteractionEnabled = !busy/);
  assert.match(settings, /mountCustomDirectory:path completion:/);
  assert.match(settings, /unmountCustomDirectory:path completion:/);
  // The startup restore is a separate synchronous caller on the jailbreak
  // worker. It must not continue before saved mounts have been restored.
  assert.match(environment, /- \(int\)mountCustomDirectory:\(NSString \*\)path\s*\{/);
  assert.match(read('Application/Dopamine/Jailbreak/DOEnvironmentManager.h'), /- \(int\)mountCustomDirectory:\(NSString \*\)path;/);
  assert.match(read('Application/Dopamine/Jailbreak/DORuntimeConfiguration.m'), /int result = \[environment mountCustomDirectory:path\]/);
});

test('native Foundation media transactions preserve old files on write failure and reject late imports', {
  skip: process.platform !== 'darwin' ? 'Requires macOS Foundation; image codecs and the app container are test doubles.' : false,
}, () => {
  const os = require('node:os');
  const { execFileSync } = require('node:child_process');
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'rh-media-native-'));
  try {
    // Exercise the production transaction/file code. UIKit JPEG decoding and
    // container discovery are substituted so Foundation can run it on macOS.
    const theme = sync.replace(
      /static NSString \* const DOCustomGlassThemeSyncDirectory =\s*@"[^"]+";/,
      'static NSString *DOCustomGlassThemeSyncDirectory;',
    ).replace(/\bNSUserDefaults\b/g, 'TestDefaults').replace(/^#pragma once$/gm, '');
    const store = (media.slice(0, media.indexOf('static inline id DOCustomGlassMediaStoreCallObjectGetter')) +
      `static inline NSURL *DOCustomGlassMediaStoreDirectoryURL(void) {
        NSURL *url = [NSURL fileURLWithPath:[testRoot stringByAppendingPathComponent:@"media"]];
        [NSFileManager.defaultManager createDirectoryAtURL:url withIntermediateDirectories:YES attributes:nil error:nil];
        return url;
      }\n` + media.slice(media.indexOf('static inline BOOL DOCustomGlassMediaStoreIsSafeFilename')))
      .replace('#import <UIKit/UIKit.h>', '')
      .replace('#import "DOCustomGlassThemeSync.h"', '')
      .replace(/\bNSUserDefaults\b/g, 'TestDefaults').replace(/^#pragma once$/gm, '');
    const source = `#import <Foundation/Foundation.h>
static NSString *testRoot;
static NSString *suite;
@interface TestDefaults : NSUserDefaults
@end
@implementation TestDefaults
+ (TestDefaults *)standardUserDefaults {
  static TestDefaults *defaults; static dispatch_once_t once;
  dispatch_once(&once, ^{ suite = [@"rh-media-test-" stringByAppendingString:NSUUID.UUID.UUIDString];
    defaults = [[TestDefaults alloc] initWithSuiteName:suite]; });
  return defaults;
}
@end
@interface UIImage : NSObject
@property(nonatomic, strong) NSData *data;
+ (UIImage *)imageWithData:(NSData *)data;
@end
@implementation UIImage
+ (UIImage *)imageWithData:(NSData *)data {
  if (!data.length || [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] isEqual:@"invalid"]) return nil;
  UIImage *image = [UIImage new]; image.data = data; return image;
}
@end
static NSData *UIImageJPEGRepresentation(UIImage *image, double quality) { return image.data; }
${theme}
${store}
#define CHECK(value) do { if (!(value)) { fprintf(stderr, "check failed at line %d\\n", __LINE__); return 1; } } while (0)
static NSProgress *request(void) { return [NSProgress progressWithTotalUnitCount:1]; }
static UIImage *image(NSString *text) { return [UIImage imageWithData:[text dataUsingEncoding:NSUTF8StringEncoding]]; }
static NSSet *files(void) { return [NSSet setWithArray:[NSFileManager.defaultManager contentsOfDirectoryAtPath:DOCustomGlassMediaStoreDirectoryURL().path error:nil]]; }
static BOOL exists(NSString *name) { return [NSFileManager.defaultManager fileExistsAtPath:DOCustomGlassMediaStoreFileURL(name).path]; }
int main(int argc, char **argv) { @autoreleasepool {
  testRoot = [NSString stringWithUTF8String:argv[1]];
  DOCustomGlassThemeSyncDirectory = [testRoot stringByAppendingPathComponent:@"theme"];
  NSString *goodDirectory = DOCustomGlassThemeSyncDirectory;
  NSUserDefaults *defaults = TestDefaults.standardUserDefaults;
  NSURL *movie = [NSURL fileURLWithPath:[testRoot stringByAppendingPathComponent:@"source.mov"]];
  [@"video" writeToURL:movie atomically:YES encoding:NSUTF8StringEncoding error:nil];
  CHECK(DOCustomGlassMediaStoreSaveAvatar(image(@"avatar"), request(), NULL));
  NSString *avatar = [defaults stringForKey:DOCustomGlassMediaStoreAvatarFilenameKey];
  CHECK(DOCustomGlassMediaStoreSaveWallpaperVideo(movie, image(@"poster"), request(), NULL));
  NSString *poster = [defaults stringForKey:DOCustomGlassMediaStoreWallpaperFilenameKey];
  NSString *video = [defaults stringForKey:DOCustomGlassMediaStoreWallpaperVideoFilenameKey];
  NSDictionary *external = [NSDictionary dictionaryWithContentsOfFile:DOCustomGlassThemeSyncPath()];
  CHECK([external[DOCustomGlassMediaStoreWallpaperFilenameKey] isEqual:poster]);
  CHECK([external[DOCustomGlassMediaStoreWallpaperVideoFilenameKey] isEqual:video]);
  NSSet *before = files();

  // A non-directory at the destination makes authoritative commits fail.
  DOCustomGlassThemeSyncDirectory = [testRoot stringByAppendingPathComponent:@"blocked"];
  [@"block" writeToFile:DOCustomGlassThemeSyncDirectory atomically:YES encoding:NSUTF8StringEncoding error:nil];
  CHECK(!DOCustomGlassMediaStoreSaveWallpaper(image(@"new"), request(), NULL));
  CHECK(!DOCustomGlassMediaStoreSaveWallpaperVideo(movie, image(@"new-poster"), request(), NULL));
  CHECK(!DOCustomGlassMediaStoreSaveAvatar(image(@"new-avatar"), request(), NULL));
  CHECK([files() isEqual:before] && exists(avatar) && exists(poster) && exists(video));
  CHECK([[defaults stringForKey:DOCustomGlassMediaStoreWallpaperFilenameKey] isEqual:poster]);
  CHECK([[defaults stringForKey:DOCustomGlassMediaStoreWallpaperVideoFilenameKey] isEqual:video]);
  DOCustomGlassThemeSyncDirectory = goodDirectory;
  CHECK([[NSDictionary dictionaryWithContentsOfFile:DOCustomGlassThemeSyncPath()] isEqual:external]);

  UIImage *invalid = [UIImage new]; invalid.data = [@"invalid" dataUsingEncoding:NSUTF8StringEncoding];
  CHECK(!DOCustomGlassMediaStoreSaveWallpaperVideo(movie, invalid, request(), NULL));
  CHECK([files() isEqual:before]);
  NSProgress *cancelled = request(); [cancelled cancel];
  CHECK(!DOCustomGlassMediaStoreSaveWallpaperVideo(movie, image(@"late"), cancelled, NULL));
  CHECK([files() isEqual:before]);

  // A is staged, B finishes first, then A's provider finally returns.
  NSProgress *a = request();
  NSString *late = DOCustomGlassMediaStoreStageImage(image(@"A"), @"wallpaper", NULL);
  @synchronized(TestDefaults.class) { [a cancel]; }
  CHECK(DOCustomGlassMediaStoreSaveWallpaper(image(@"B"), request(), NULL));
  NSString *winner = [defaults stringForKey:DOCustomGlassMediaStoreWallpaperFilenameKey];
  CHECK(!DOCustomGlassMediaStoreCommit(@{DOCustomGlassMediaStoreWallpaperFilenameKey:late}, a));
  DOCustomGlassMediaStoreRemoveFile(late);
  CHECK([[defaults stringForKey:DOCustomGlassMediaStoreWallpaperFilenameKey] isEqual:winner]);
  CHECK(exists(winner) && exists(avatar) && !exists(poster) && !exists(video));
  CHECK(![defaults objectForKey:DOCustomGlassMediaStoreWallpaperVideoFilenameKey]);
  DOCustomGlassThemeSyncFlush();
  external = [NSDictionary dictionaryWithContentsOfFile:DOCustomGlassThemeSyncPath()];
  CHECK([external[DOCustomGlassMediaStoreWallpaperFilenameKey] isEqual:winner]);
  CHECK(!external[DOCustomGlassMediaStoreWallpaperVideoFilenameKey]);

  // Restart reconstructs local references from the committed external state.
  [defaults setObject:@"stale.jpg" forKey:DOCustomGlassMediaStoreWallpaperFilenameKey];
  DOCustomGlassThemeSyncBootstrap();
  CHECK([[defaults stringForKey:DOCustomGlassMediaStoreWallpaperFilenameKey] isEqual:winner]);
  CHECK(exists(winner) && files().count == 2);
  [defaults removePersistentDomainForName:suite];
  return 0;
} }
`;
    const file = path.join(directory, 'media.m');
    const binary = path.join(directory, 'media-test');
    fs.writeFileSync(file, source);
    execFileSync('xcrun', ['clang', '-fobjc-arc', '-framework', 'Foundation', file, '-o', binary]);
    execFileSync(binary, [directory]);
  } finally {
    fs.rmSync(directory, { recursive: true, force: true });
  }
});

test('native Foundation runs production blur scheduling with obsolete requests and duplicate parameters', {
  skip: process.platform !== 'darwin' ? 'Requires macOS Foundation; Core Image rendering and UIKit views are test doubles.' : false,
}, () => {
  const os = require('node:os');
  const { execFileSync } = require('node:child_process');
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'rh-blur-native-'));
  try {
    const method = section(navigation, '- (void)customGlassApplySharedBackgroundBlurIntensity:', '- (void)supporterLicenseDidChange:');
    const source = `#import <Foundation/Foundation.h>
#import <math.h>
@interface UIImage : NSObject
@property CGFloat intensity;
@end
@implementation UIImage
@end
@interface UIView : NSObject
@property(nonatomic, strong) UIImage *image;
@property CGFloat blurIntensity;
@property BOOL hidden;
+ (void)performWithoutAnimation:(void (^)(void))block;
@end
@implementation UIView
+ (void)performWithoutAnimation:(void (^)(void))block { block(); }
@end
static dispatch_semaphore_t started, gate;
static NSMutableArray *renders;
static CGFloat DOCustomGlassNavigationClamp01(CGFloat value) { return MIN(1.0, MAX(0.0, value)); }
static UIImage *DOCustomGlassNavigationCreateBlurredImage(UIImage *image, CGFloat intensity) {
  @synchronized(renders) { [renders addObject:@(intensity)]; }
  if (fabs(intensity - 0.1) < 0.0001) {
    dispatch_semaphore_signal(started);
    dispatch_semaphore_wait(gate, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));
  }
  UIImage *result = [UIImage new]; result.intensity = intensity; return result;
}
@interface TestNavigation : NSObject
@property(nonatomic, strong) UIImage *customGlassBackgroundSourceImage;
@property(nonatomic, strong) UIImage *customGlassBackgroundBlurRequestedImage;
@property CGFloat customGlassBackgroundBlurRequestedIntensity;
@property BOOL customGlassWallpaperPlaybackRetired, customGlassWallpaperSuspended, customGlassUsingVideoWallpaper;
@property NSUInteger customGlassBackgroundBlurGeneration;
@property(nonatomic, strong) NSOperationQueue *customGlassBackgroundBlurQueue;
@property(nonatomic, strong) UIView *backgroundImageView, *customGlassVideoWallpaperBlurView;
@end
@implementation TestNavigation
${method}
@end
#define CHECK(value) do { if (!(value)) { fprintf(stderr, "check failed at line %d\\n", __LINE__); return 1; } } while (0)
int main(void) { @autoreleasepool {
  renders = [NSMutableArray array]; started = dispatch_semaphore_create(0); gate = dispatch_semaphore_create(0);
  TestNavigation *nav = [TestNavigation new];
  nav.backgroundImageView = [UIView new]; nav.customGlassVideoWallpaperBlurView = [UIView new];
  nav.customGlassBackgroundSourceImage = [UIImage new];
  [nav customGlassApplySharedBackgroundBlurIntensity:0.1];
  CHECK(dispatch_semaphore_wait(started, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) == 0);
  [nav customGlassApplySharedBackgroundBlurIntensity:0.2];
  [nav customGlassApplySharedBackgroundBlurIntensity:0.3];
  [nav customGlassApplySharedBackgroundBlurIntensity:0.4];
  NSUInteger generation = nav.customGlassBackgroundBlurGeneration;
  [nav customGlassApplySharedBackgroundBlurIntensity:0.4];
  CHECK(nav.customGlassBackgroundBlurGeneration == generation);
  dispatch_semaphore_signal(gate);
  NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
  while (fabs(nav.backgroundImageView.image.intensity - 0.4) > 0.0001 && deadline.timeIntervalSinceNow > 0)
    [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
  CHECK(fabs(nav.backgroundImageView.image.intensity - 0.4) < 0.0001);
  @synchronized(renders) { CHECK(renders.count == 2); CHECK(fabs([renders.lastObject doubleValue] - 0.4) < 0.0001); }
  nav.customGlassUsingVideoWallpaper = YES;
  [nav customGlassApplySharedBackgroundBlurIntensity:0.8];
  CHECK(nav.backgroundImageView.image == nav.customGlassBackgroundSourceImage);
  CHECK(nav.customGlassVideoWallpaperBlurView.hidden && nav.customGlassVideoWallpaperBlurView.blurIntensity == 0);
  nav.customGlassWallpaperPlaybackRetired = YES;
  generation = nav.customGlassBackgroundBlurGeneration;
  [nav customGlassApplySharedBackgroundBlurIntensity:0.9];
  CHECK(nav.customGlassBackgroundBlurGeneration == generation);
  CHECK(renders.count == 2);
  return 0;
} }
`;
    const file = path.join(directory, 'blur.m');
    const binary = path.join(directory, 'blur-test');
    fs.writeFileSync(file, source);
    execFileSync('xcrun', ['clang', '-fobjc-arc', '-framework', 'Foundation', file, '-o', binary]);
    execFileSync(binary, []);
  } finally {
    fs.rmSync(directory, { recursive: true, force: true });
  }
});

test('native Foundation mount task waits outside privilege scopes and reports spawn, busy and child failures', {
  skip: process.platform !== 'darwin' ? 'Requires macOS Foundation; no mounts or privilege changes are performed.' : false,
}, () => {
  const os = require('node:os');
  const { execFileSync } = require('node:child_process');
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'rh-mount-task-'));
  try {
    const methods = section(environment, '- (void)runCustomMountCommand:', '- (BOOL)removeCustomMountCopyAtPath:');
    const source = `#import <Foundation/Foundation.h>
#include <spawn.h>
#include <sys/wait.h>
#include <errno.h>
extern char **environ;
static int scopeDepth, spawnFailure, waitCalls;
static dispatch_semaphore_t gate;
static int exec_cmd_nowait(pid_t *child, const char *binary, ...) {
  if (scopeDepth != 2) abort();
  if (spawnFailure) return spawnFailure;
  char *args[] = {"/bin/sh", "-c", "exit 3", NULL};
  return posix_spawn(child, args[0], NULL, NULL, args, environ);
}
static pid_t testWait(pid_t child, int *status, int options) {
  if (scopeDepth != 0 || NSThread.isMainThread || child <= 0) abort();
  waitCalls++;
  if (waitCalls == 1) { errno = EINTR; return -1; }
  dispatch_semaphore_wait(gate, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));
  return waitpid(child, status, options);
}
#define waitpid testWait
#define JBROOT_PATH(p) p
@interface TestEnvironment : NSObject
@property BOOL isJailbroken, customMountTaskRunning;
@end
@implementation TestEnvironment
- (void)runAsRoot:(void (^)(void))block { scopeDepth++; block(); scopeDepth--; }
- (void)runUnsandboxed:(void (^)(void))block { scopeDepth++; block(); scopeDepth--; }
${methods}
@end
#undef waitpid
#define CHECK(value) do { if (!(value)) { fprintf(stderr, "check failed at line %d\\n", __LINE__); return 1; } } while (0)
int main(void) { @autoreleasepool {
  gate = dispatch_semaphore_create(0);
  TestEnvironment *env = [TestEnvironment new]; env.isJailbroken = YES;
  __block BOOL completed = NO, busy = NO, responsive = NO;
  __block int result = -1;
  [env mountCustomDirectory:@"/test" completion:^(int r) {
    if (!NSThread.isMainThread || env.customMountTaskRunning || scopeDepth) abort();
    result = r; completed = YES;
  }];
  CHECK(env.customMountTaskRunning && scopeDepth == 0);
  [env unmountCustomDirectory:@"/test" completion:^(int r) { busy = r == EBUSY; }];
  dispatch_async(dispatch_get_main_queue(), ^{ responsive = YES; dispatch_semaphore_signal(gate); });
  NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
  while ((!completed || !busy || !responsive) && deadline.timeIntervalSinceNow > 0)
    [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
  CHECK(completed && busy && responsive && WIFEXITED(result) && WEXITSTATUS(result) == 3 && waitCalls == 2);
  completed = NO; spawnFailure = 57;
  [env mountCustomDirectory:@"/test" completion:^(int r) { result = r; completed = YES; }];
  deadline = [NSDate dateWithTimeIntervalSinceNow:5];
  while (!completed && deadline.timeIntervalSinceNow > 0)
    [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
  CHECK(completed && result == 57 && waitCalls == 2 && !env.customMountTaskRunning);
  return 0;
} }
`;
    const file = path.join(directory, 'mount-task.m');
    const binary = path.join(directory, 'mount-task-test');
    fs.writeFileSync(file, source);
    execFileSync('xcrun', ['clang', '-fobjc-arc', '-framework', 'Foundation', file, '-o', binary]);
    execFileSync(binary, []);
  } finally {
    fs.rmSync(directory, { recursive: true, force: true });
  }
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

test('iOS 16 slimming preserves settings data sources and action/preference implementations', () => {
  assert.equal(
    fingerprint(section(settings, '- (NSArray *)availableKernelExploitIdentifiers', '- (id)specifiers')),
    'd9b1e11b9aaf31b59efa0849e2b8a7014fecfcf9731f1a9d42420fe0886ae84c',
  );
  // Baseline excludes the removed whitelist installer and separately tested ports.
  const supporterActions = section(
    settings,
    '- (void)lowPowerSchedulePressed',
    '- (void)changeMobilePasswordWithAuthenticationPressed',
  );
  const actions = section(settings, '- (void)setPreferenceValue:', '- (void)setDyldPatchEnabled:')
    .replace(supporterActions, '')
    .replace(section(settings, '- (void)setCustomMountBusy:', '- (void)presentCustomMountMessage:'), '')
    .replace(section(settings, '- (void)presentCustomMountMessage:', '- (void)refreshJailbreakAppsPressed'), '');
  assert.equal(fingerprint(actions.replace(/\n{3,}/g, '\n\n')),
    'c41d2b8b3706d4a2e3291ca57b8cbbca01c3487d0b4d12ebe393cf0b0bf234b8');
  assert.match(settings, /setProperty:@"shippingbox\.and\.arrow\.backward" forKey:@"image"/);
  assert.doesNotMatch(settings, /isSPTM|majorVersion==15|spinlock fix is/);
  const dyld = settings.slice(settings.indexOf('- (void)setDyldPatchEnabled:'));
  assert.match(dyld, /jbclient_set_dyld_patch\(enable\) == 0/);
  assert.match(dyld, /\[self setPreferenceValue:value specifier:specifier\]/);
  assert.match(dyld, /confirmAction\(\);/);
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

test('credits content except the removed authorization action and license-to-credits return remain intact', () => {
  assert.equal(
    fingerprint(credits.slice(credits.indexOf('- (id)specifiers'))),
    '98ca746c282da993c08bdaff16d45eca7affb0051f9457b8044f64f32930a781',
  );
  const license = read(ui + 'Settings/DOLicenseViewController.m');
  assert.match(license, /makeHeader:DOLocalizedString\(@"Credits_Button_License"\) withTarget:self/);
  assert.match(license, /- \(void\)dismiss[\s\S]*?popViewControllerAnimated:YES/);
  assert.match(credits, /pushViewController:\[\[DOLicenseViewController alloc\] init\]/);
});

test('supporter license entry uses the audited core and reports persistent removal failure', () => {
  const settings = read(ui + 'Settings/DOSettingsController.m');
  const licenseUI = read(ui + 'DOSupporterLicenseUI.h');
  assert.match(settings, /^#import "\.\.\/DOSupporterLicenseUI\.h"$/m);
  assert.match(settings, /Supporter_Title/);
  assert.match(settings, /supporterLicensePressed/);
  assert.match(licenseUI, /if \(!DORHSupporterRemoveLicense\(\)\)/);
  assert.match(licenseUI, /Supporter_Remove_Failed/);
  assert.match(licenseUI, /DORHPresentSupporterDiagnostics/);
  assert.doesNotMatch(credits, /DOSupporterLicenseUI|DORHPresentSupporterLicense|supporterLicensePressed/);
  assert.doesNotMatch(read(ui + 'Settings/Credits.plist'), /Supporter_Title|supporterLicensePressed/);
  for (const locale of ['en', 'zh-Hans', 'zh-CN']) {
    const strings = read(`Application/Dopamine/${locale}.lproj/Localizable.strings`);
    assert.match(strings, /"Supporter_Title"\s*=/);
    assert.match(strings, /"Supporter_Remove_Failed_Message"\s*=/);
  }
});

test('Credits has no builder attribution and the build verifies the packaged menu', () => {
  const workflow = read('.github/workflows/build.yml');
  assert.doesNotMatch(read(ui + 'Settings/Credits.plist'), /kulinichx|<string>BUILDER<\/string>/i);
  assert.doesNotMatch(workflow, /plutil -insert items\.|github\.actor/);
  assert.match(workflow, /unzip -p "\$tipa" Payload\/Dopamine\.app\/Credits\.plist/);
  assert.match(workflow, /plutil -lint "\$RUNNER_TEMP\/RootHide-Credits\.plist"/);
  assert.match(workflow, /Removed authorization entry or builder attribution found in packaged Credits/);
});

test('credits uses shared glass without replacing its content or collection delegates', () => {
  assert.match(credits, /^#import "DOCustomGlassView\.h"$/m);
  assert.match(credits, /self\.view\.backgroundColor = UIColor\.clearColor/);
  assert.match(credits, /self\.view\.layer\.masksToBounds = NO/);
  assert.match(credits, /_table\.opaque = NO/);
  assert.match(credits, /UITableViewCellSeparatorStyleNone/);
  assert.match(credits, /initWithCornerRadius:24\.0 baseTintAlpha:0\.044/);
  assert.match(credits, /pageBackdrop\.materialScale = 0\.94/);
  assert.match(credits, /pageBackdrop\.userInteractionEnabled = NO/);
  assert.match(credits, /\[_table insertSubview:pageBackdrop atIndex:0\]/);
  assert.match(credits, /rectForSection:0/);
  assert.match(credits, /self\.customGlassPageBackdrop\.frame = sectionRect/);
  assert.match(credits, /\[_table sendSubviewToBack:self\.customGlassPageBackdrop\]/);
  assert.match(credits, /MIN\(620\.0, availableWidth - 24\.0\)/);
  assert.doesNotMatch(credits, /customGlassSectionBackdrops|rectForHeaderInSection:|rectForRowAtIndexPath:/);
  assert.doesNotMatch(credits, /(?:_table|collectionView)\.(?:delegate|dataSource)\s*=/);
  assert.doesNotMatch(credits, /DORHSupporter|DOCustomGlassMediaStoreSave|setObject:.*forKey:/);
});

test('credits glass is limited to the upper action section', () => {
  assert.match(credits, /customGlassPageBackdrop/);
  assert.match(credits, /rectForSection:0/);
  assert.match(credits, /_table\.numberOfSections <= 0 \|\| \[_table numberOfRowsInSection:0\] <= 0/);
  assert.doesNotMatch(credits, /self\.customGlassPageBackdrop\.frame = _table\.frame/);
  assert.doesNotMatch(credits, /NSMutableDictionary<NSNumber \*, DOCustomLiquidGlassView \*>|activeSections|activeKeys/);
  const content = read(ui + 'Settings/Credits.plist');
  assert.match(content, /<string>DOCreditsCell<\/string>/);
  assert.match(content, /<key>names<\/key>/);
  assert.match(content, /<string>Developers<\/string>/);
  assert.match(content, /<string>UI and Design<\/string>/);
  assert.match(content, /<string>Credits<\/string>/);
  const creditsCell = read(ui + 'Settings/Specifiers/DOCreditsCell.m');
  assert.match(creditsCell, /collectionView\.scrollEnabled = NO/);
  assert.match(creditsCell, /- \(void\)layoutSubviews/);
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
