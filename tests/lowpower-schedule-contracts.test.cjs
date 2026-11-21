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
  assert.match(header, /rename\(temporary\.fileSystemRepresentation, path\.fileSystemRepresentation\)/);
  assert.match(header, /NSDataWritingFileProtectionNone/);
  assert.match(header, /NSFilePosixPermissions: @0600/);
  const save = body(environment, '- (BOOL)saveLowPowerScheduleConfiguration:');
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
  const apply = body(runtime, '- (NSString *)applyEvent:');
  assert.ok(refresh.indexOf('[self armForDate:next[@"Date"]]') < refresh.indexOf('[self applyEvent:'));
  assert.ok(refresh.indexOf('rcLowPowerEventIsDeferred(configuration, previous)') < refresh.indexOf('[self applyEvent:'));
  assert.ok(apply.indexOf('configurationIsCurrent:configuration') < apply.indexOf('requestPowerMode:target'));
  assert.match(apply, /if \(self\.systemLowPowerEnabled == target\) \{\s*self\.lastHandled = event/);
  assert.match(refresh, /if \(!\[configuration\[@"Enabled"\] boolValue\]\)/);
  assert.match(refresh, /self\.retryCount < 4/);
  assert.match(refresh, /self\.retryAfter/);
  assert.match(refresh, /saved\[@"LastHandled"\]/);
});

test('the iOS 16 void setter is called by the backend and confirmed separately', () => {
  assert.match(runtime, /- \(void\)setPowerMode:\(NSInteger\)mode/);
  assert.match(body(runtime, 'static BOOL rcPowerSetterMatches'), /"vBc", "q@"/);
  assert.match(body(runtime, '- (BOOL)requestPowerMode:'), /rcSubmitPowerMode\(power, enabled \? 1 : 0\)/);
  assert.match(body(runtime, 'static BOOL rcSubmitPowerMode'), /\[invocation invokeWithTarget:power\]/);
  assert.doesNotMatch(body(runtime, 'static BOOL rcLowPowerAPIsAvailable'), /setUserVisible:/);
});

test('settings exposes the schedule while jailbroken and UI never applies system mode directly', () => {
  assert.match(settings, /DOLowPowerScheduleController\.h/);
  assert.match(settings, /PowerSchedule_Title/);
  assert.match(settings, /lowPowerSchedulePressed/);
  assert.match(settings, /pushViewController:\[DOPowerScheduleController new\]/);
  assert.match(controller, /DOScheduleTimePicker\(minute, self/);
  assert.match(read('Application/Dopamine/UI/Settings/DOScheduleTimePicker.h'), /UIDatePickerModeTime/);
  assert.match(controller, /start == end/);
  assert.doesNotMatch(controller, /RC_LOW_POWER_QUERY|notify_post|UIActivityIndicatorView|scheduledTimer/);
  assert.equal((controller.match(/dispatch_after\(/g) || []).length, 1);
  assert.doesNotMatch(body(controller, '- (void)finishScheduleWait:'), /beginScheduleWait:|writeConfiguration:/);
  assert.match(controller, /runtimeStatus\[@"Revision"\] isEqual:self\.savedConfiguration\[@"Revision"\]/);
  assert.match(controller, /notify_cancel\(self\.statusToken\)/);
  assert.doesNotMatch(controller, /setPowerMode:/);
  const refresh = body(runtime, '- (void)refresh\n');
  const disabled = refresh.match(
    /if \(!\[configuration\[@"Enabled"\] boolValue\]\) \{([\s\S]*?)\n    \}/,
  )[1];
  assert.match(disabled, /disableWithConfiguration:configuration/);
  const stop = body(runtime, '- (void)disableWithConfiguration:');
  assert.match(body(runtime, '- (BOOL)requestPowerOff'), /requestPowerMode:NO/);
  assert.match(stop, /saved\[@"DisableRequest"\] isEqual:request/);
  assert.match(stop, /!self\.systemLowPowerEnabled\) self\.disableState = @"disabled"/);
  assert.match(stop, /self\.disableAttempts >= 3\) self\.disableState = @"applyFailed"/);
});

test('the enable prompt defers both edges and status never predicts an unconfirmed stop', () => {
  const prompt = body(controller, '- (void)settingsChanged');
  assert.match(prompt, /previous\[@"PowerMode"\]/);
  assert.match(prompt, /enablePlanDeferringCurrentWindow:YES/);
  const prepare = body(controller, '- (NSString *)prepareConfiguration:');
  assert.match(prepare, /configuration\[@"SkipThrough"\] = rcLowPowerEvent/);
  const status = body(controller, '- (NSString *)statusText');
  assert.doesNotMatch(status, /rcLowPowerEvent\(/);
  assert.match(status, /!\[next\[@"PowerMode"\] boolValue\] && systemOn/);
});

test('scheduler confirms system changes, rejects stale writes and skips a deferred window', {
  skip: process.platform !== 'darwin' ? 'Requires macOS Foundation.' : false,
}, t => {
  const dir = fs.mkdtempSync(path.join(require('node:os').tmpdir(), 'schedule-disable-'));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  const run = require('node:child_process').execFileSync;
  const bin = path.join(dir, 'test');
  run('xcrun', ['clang', '-fobjc-arc', '-fblocks', '-framework', 'Foundation', '-I',
    path.join(root, 'BaseBin/roothidehooks/src'), path.join(root, 'tests/fixtures/lowpower-disable-harness.m'), '-o', bin]);
  run(bin, [dir]);
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

test('schedule footers use one custom label and cannot receive UIKit default footer text', () => {
  const battery = read('Application/Dopamine/UI/Settings/DOBatteryRecordController.m');
  assert.doesNotMatch(controller + battery, /titleForFooterInSection:/);
  const footer = body(controller, '- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:');
  assert.doesNotMatch(footer, /UITableViewHeaderFooterView/);
  assert.equal((footer.match(/\[UILabel new\]/g) || []).length, 1);
  assert.match(footer, /footerTextForSection:section/);
});

test('scheduled recording has no manual start or refresh UI and keeps an exit for active records', () => {
  const battery = read('Application/Dopamine/UI/Settings/DOBatteryRecordController.m');
  assert.doesNotMatch(controller + battery, /PowerSchedule_TapRefresh|PowerSchedule_Refreshing|BatteryRecord_Start"|requestStatus|statusWaiting|queryDate/);
  assert.match(battery, /sendBatteryRecordCommand:@"stop"/);
  assert.doesNotMatch(battery, /sendBatteryRecordCommand:@"start"/);
  const cell = body(controller, '- (void)configureStatusCell:');
  assert.match(cell, /UIAccessibilityTraitStaticText/);
  assert.match(cell, /UITableViewCellSelectionStyleNone/);
});

test('page entry prelays out the destination and uses the reported animation duration', () => {
  const transition = read('Application/Dopamine/UI/Transition/DOModalTransitionPush.m');
  assert.ok(transition.indexOf('[toViewController.view layoutIfNeeded]') < transition.indexOf('[UIView animateWithDuration:'));
  assert.match(transition, /animateWithDuration:\[self transitionDuration:transitionContext\]/);
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
    'CustomMount_Overlap',
    'CustomMount_RemoveParentFirst',
    'CustomMount_SharedCopyPreserved',
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
