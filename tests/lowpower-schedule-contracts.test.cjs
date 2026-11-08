const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const root = path.resolve(__dirname, '..');
const read = relative => fs.readFileSync(path.join(root, relative), 'utf8');
const runtime = read('BaseBin/roothidehooks/src/lowpowerschedule.m');
const header = read('BaseBin/roothidehooks/src/RCLowPowerSchedule.h');
const controller = read('Application/Dopamine/UI/Settings/DOLowPowerScheduleController.m');
const environment = read('Application/Dopamine/Jailbreak/DOEnvironmentManager.m');
const settings = read('Application/Dopamine/UI/Settings/DOSettingsController.m');

function body(source, signature) {
  const start = source.indexOf(signature);
  assert.ok(start >= 0, `Missing source block: ${signature}`);
  const opening = source.indexOf('{', start + signature.length);
  let depth = 0;
  for (let index = opening; index < source.length; index++) {
    if (source[index] === '{') depth++;
    if (source[index] === '}' && --depth === 0) return source.slice(opening + 1, index);
  }
  assert.fail(`Unclosed source block: ${signature}`);
}

test('SpringBoard owns the event-driven scheduler, not the app lifecycle', () => {
  assert.match(read('BaseBin/roothidehooks/src/springboard.x'), /rcLowPowerScheduleStart\(\)/);
  assert.match(runtime, /jbclient_get_jbroot\(\)/);
  assert.match(runtime, /NSClassFromString\(@"PCPersistentTimer"\)/);
  assert.match(runtime, /setDisableSystemWaking:NO/);
  assert.match(runtime, /setMinimumEarlyFireProportion:0\.0/);
  assert.match(runtime, /setEarlyFireConstantInterval:0\.0/);
  assert.doesNotMatch(runtime, /NSTimer|sleep\(|dispatch_source_create/);
});

test('configuration validation and local calendar handle daily and DST boundaries', () => {
  assert.match(header, /CFBooleanGetTypeID\(\)/);
  assert.match(header, /initWithUUIDString:/);
  assert.match(header, /StartMinute.*EndMinute/s);
  assert.match(header, /NSCalendarMatchNextTime \| NSCalendarMatchFirst/);
  assert.match(header, /dateByAddingUnit:NSCalendarUnitDay/);
  assert.match(header, /NSTimeZone\.localTimeZone/);
  assert.doesNotMatch(header, /86400/);
});

test('storage is bounded and atomic and writes are restricted to the unsandboxed RootHide path', () => {
  assert.match(header, /> 16384/);
  assert.match(header, /NSDataWritingAtomic/);
  assert.match(header, /NSDataWritingFileProtectionNone/);
  assert.match(header, /NSFilePosixPermissions: @0600/);
  const save = body(environment, '- (BOOL)saveLowPowerScheduleEnabled:');
  assert.match(save, /!self\.isJailbroken/);
  assert.match(save, /rcLowPowerConfigurationValid\(configuration\)/);
  assert.match(save, /runUnsandboxed/);
  assert.match(save, /notify_post\(RC_LOW_POWER_CHANGED\)/);
  assert.doesNotMatch(save, /runAsRoot/);
});

test('scheduler checks private ABI, arms the next event before applying mode, and bounds retries', () => {
  const refresh = body(runtime, '- (void)refresh\n');
  assert.match(refresh, /rcLowPowerAPIsAvailable\(\)/);
  assert.match(refresh, /@try/);
  assert.match(refresh, /@catch/);
  assert.ok(refresh.indexOf('[self armForDate:next[@"Date"]]') <
    refresh.indexOf('setPowerMode:'));
  assert.match(refresh, /if \(!\[configuration\[@"Enabled"\] boolValue\]\)/);
  assert.match(refresh, /self\.retryCount < 4/);
  assert.match(refresh, /self\.retryAfter/);
  assert.match(refresh, /saved\[@"LastHandled"\]/);
});

test('settings exposes the schedule while jailbroken and UI never applies system mode directly', () => {
  assert.match(settings, /DOLowPowerScheduleController\.h/);
  assert.match(settings, /LowPowerSchedule_Title/);
  assert.match(settings, /lowPowerSchedulePressed/);
  assert.match(settings, /pushViewController:\[DOLowPowerScheduleController new\]/);
  assert.match(controller, /UIDatePickerModeTime/);
  assert.match(controller, /start == end/);
  assert.match(controller, /RC_LOW_POWER_QUERY/);
  assert.match(controller, /status\[@"Revision"\] isEqual:self\.savedConfiguration\[@"Revision"\]/);
  assert.match(controller, /notify_cancel\(self\.statusToken\)/);
  assert.doesNotMatch(controller, /setPowerMode:/);
  const refresh = body(runtime, '- (void)refresh\n');
  const disabled = refresh.match(
    /if \(!\[configuration\[@"Enabled"\] boolValue\]\) \{([\s\S]*?)\n    \}/,
  )[1];
  assert.match(disabled, /publishStatus:@"disabled"/);
  assert.doesNotMatch(disabled, /setPowerMode/);
});

test('low-power schedule uses the same full-screen navigation frame as settings', () => {
  const navigation = read('Application/Dopamine/UI/DONavigationController.m');
  const fullScreen = body(navigation, '- (BOOL)isCustomGlassFullScreenViewController:');
  assert.match(fullScreen, /DOSettingsController\.class/);
  assert.match(fullScreen, /DOLowPowerScheduleController\.class/);
  assert.match(controller, /tableView\.bounces = YES/);
  assert.match(controller, /tableView\.alwaysBounceVertical = YES/);
  assert.doesNotMatch(controller, /revealScheduleStatusIfNeeded/);
});

test('all schedule localization keys exist in the supported release locales', () => {
  const keys = new Set([...controller.matchAll(/@"(LowPowerSchedule_\w+)"/g)].map(match => match[1]));
  keys.add('LowPowerSchedule_Title');
  for (const locale of ['en', 'zh-CN', 'zh-Hans']) {
    const strings = read(`Application/Dopamine/${locale}.lproj/Localizable.strings`);
    for (const key of keys) {
      assert.equal([...strings.matchAll(new RegExp(`^"${key}"\\s*=`, 'gm'))].length, 1,
        `${locale} must define ${key} exactly once`);
    }
  }
});

test('custom mount controls have complete English and Simplified Chinese copy', () => {
  const keys = [
    'CustomMount_Title',
    'CustomMount_Add',
    'CustomMount_Manage',
    'CustomMount_Path_Prompt',
    'CustomMount_InvalidPath',
    'CustomMount_AlreadyExists',
    'CustomMount_Failed',
    'CustomMount_SaveFailedRolledBack',
    'CustomMount_SaveFailedRollbackFailed',
    'CustomMount_Empty',
    'CustomMount_ManagePrompt',
    'CustomMount_UnmountTitle',
    'CustomMount_Unmount',
    'CustomMount_View',
    'CustomMount_Forget',
    'CustomMount_ViewUnavailable',
    'CustomMount_CleanupFailed',
    'CustomMount_SaveFailed',
    'CustomMount_UnmountedSaveFailed',
  ];
  for (const locale of ['en', 'zh-CN', 'zh-Hans']) {
    const strings = read(`Application/Dopamine/${locale}.lproj/Localizable.strings`);
    for (const key of keys) {
      assert.equal([...strings.matchAll(new RegExp(`^"${key}"\\s*=`, 'gm'))].length, 1,
        `${locale} must define ${key} exactly once`);
    }
  }
});

test('controller is included in the Xcode app target and SpringBoard hook source glob', () => {
  const project = read('Application/Dopamine.xcodeproj/project.pbxproj');
  assert.equal(project.match(/DOLowPowerScheduleController\.m in Sources/g)?.length, 2);
  assert.match(read('BaseBin/roothidehooks/Makefile'), /wildcard src\/\*\.m/);
});
