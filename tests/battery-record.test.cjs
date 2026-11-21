const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const root = path.resolve(__dirname, '..');
const read = p => fs.readFileSync(path.join(root, p), 'utf8');
const runtime = read('BaseBin/roothidehooks/src/batteryrecord.m');
const header = read('BaseBin/roothidehooks/src/RCBatteryRecord.h');
const controller = read('Application/Dopamine/UI/Settings/DOBatteryRecordController.m');

test('battery recorder is a separate SpringBoard endpoint sampler, never a power-mode setter', () => {
  assert.match(read('BaseBin/roothidehooks/src/springboard.x'), /rcBatteryRecordStart\(\)/);
  assert.match(runtime, /batteryMonitoringEnabled = wasMonitoring/);
  assert.match(runtime, /mach_continuous_time\(\)/);
  assert.match(runtime, /thermalState/);
  assert.doesNotMatch(runtime, /setPowerMode:|NSTimer|dispatch_source_create|sleep\(/);
  assert.match(runtime, /setDisableSystemWaking:NO/);
  assert.match(runtime, /rcBatteryTimerMethod/);
  assert.match(header, /battery-record/);
  assert.match(runtime, /history.count > 60/);
  assert.match(header, /262144/);
});

test('coincident low-power events bracket battery endpoint sampling', () => {
  const low = read('BaseBin/roothidehooks/src/lowpowerschedule.m');
  const apply = low.indexOf('submitted = rcSubmitPowerMode(');
  const before = low.lastIndexOf('rcBatteryRecordBeforePowerChange();', apply);
  const after = low.indexOf('rcBatteryRecordAfterPowerChange();', apply);
  assert.ok(before >= 0 && before < apply && apply < after);
  assert.match(runtime, /rcLowPowerScheduleRefresh\(\);\s*\[self refresh\]/);
});

test('recording UI inherits the schedule editor while keeping its own configuration', () => {
  const env = read('Application/Dopamine/Jailbreak/DOEnvironmentManager.m');
  assert.match(env, /saveBatteryRecordConfiguration/);
  assert.match(env, /rcBatteryPath\(JBROOT_PATH\(@"\/"\), suffix\)/);
  assert.match(read('Application/Dopamine/UI/Settings/DOBatteryRecordController.h'), /: DOLowPowerScheduleController/);
  assert.match(read('Application/Dopamine/UI/Settings/DOLowPowerScheduleController.m'), /DOScheduleTimePicker\(/);
  assert.match(controller, /lowPowerScheduleConfiguration/);
  assert.doesNotMatch(controller, /saveLowPowerScheduleEnabled|setPowerMode:/);
  assert.match(controller, /comparison.count == 2/);
  assert.match(controller, /statusFresh/);
  assert.match(read('Application/Dopamine/UI/Settings/DOSettingsController.m'), /DOPowerScheduleController new/);
  const project = read('Application/Dopamine.xcodeproj/project.pbxproj');
  assert.equal((project.match(/DOBatteryRecordController.m in Sources/g) || []).length, 2);
});

test('all battery result and page messages have English and Simplified Chinese text', () => {
  const keys = new Set([...controller.matchAll(/@"(BatteryRecord_[A-Za-z]+)"/g)].map(m => m[1]));
  for (const result of ['complete','late','interrupted','cancelled','clockChanged','busy','missed','sampleFailed','timerFailed','expired','noActive']) keys.add(`BatteryRecord_Result_${result}`);
  for (const state of ['idle','scheduled','recording','timerFailed','runtimeFailed']) keys.add(`BatteryRecord_State_${state}`);
  for (const locale of ['en','zh-CN','zh-Hans','zh-Hant']) {
    const strings = read(`Application/Dopamine/${locale}.lproj/Localizable.strings`);
    for (const key of keys) assert.match(strings, new RegExp(`"${key}" = "[^"\\n]+";`), `${locale}: ${key}`);
  }
});

test('production recorder handles one-shot, overnight, repeat, missing, interruption, charging and command deduplication', {
  skip: process.platform !== 'darwin' ? 'Requires macOS Foundation; uses production recorder with fake clock, battery and persistent timer.' : false,
}, () => {
  const os = require('node:os');
  const { execFileSync } = require('node:child_process');
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'rh-battery-record-'));
  try {
    const source = read('tests/fixtures/battery-record-harness.m')
      .replace('/* RUNTIME */', runtime.replace('#import "RCBatteryRecord.h"', ''));
    const file = path.join(temp, 'test.m'); const binary = path.join(temp, 'test');
    fs.writeFileSync(file, source);
    execFileSync('xcrun', ['clang', '-fobjc-arc', '-fblocks', '-Wall', '-Wextra', '-Wno-unused-parameter',
      '-Werror', '-framework', 'Foundation', '-I', path.join(root, 'BaseBin/roothidehooks/src'), file, '-o', binary], { stdio: 'pipe' });
    execFileSync(binary, [temp], { stdio: 'pipe' });
  } finally { fs.rmSync(temp, { recursive: true, force: true }); }
});
