const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const root = path.resolve(__dirname, '..');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
const manifest = JSON.parse(read('tests/fixtures/zqbb-ios16-baseline.json'));
const normalized = text => text.replace(/\r\n/g, '\n').replace(/[\t ]+$/gm, '');
const digest = text => crypto.createHash('sha256').update(normalized(text)).digest('hex');

test('core runtime stays at the reviewed ZQBB/iOS 16 baseline', () => {
  assert.equal(manifest.upstream, '18049d5a81b294d3387b3af30c54558d04b8b5f5');
  assert.equal(manifest.files.length, 42);
  const approved = manifest.approvedBackports || [];
  assert.equal(new Set(approved.map(entry => entry.file)).size, approved.length);
  for (const entry of approved) {
    const original = manifest.files.find(file => file.file === entry.file);
    assert.ok(original, `${entry.file}: exception must reference a pinned baseline file`);
    assert.equal(entry.baselineSha256, original.sha256);
    assert.match(entry.sourceCommit, /^[a-f0-9]{40}$/);
    assert.ok(entry.scope && entry.authorization);
  }
  for (const entry of manifest.files) {
    const exception = approved.find(backport => backport.file === entry.file);
    assert.equal(digest(read(entry.file)),
      exception ? exception.sha256 : entry.sha256,
      `${entry.file}: runtime changes require an explicit scope review`);
  }
});

test('the app keeps ZQBB jbctl launch behavior alongside our feature methods', () => {
  const file = 'Application/Dopamine/Jailbreak/DOEnvironmentManager.m';
  const section = text => text.slice(text.indexOf('- (int)spawnJbctlAsRootWithArgs:'),
    text.indexOf('- (int)runTrollStoreAction:'));
  assert.equal(digest(section(read(file))), manifest.upstreamSections.jbctlLaunch);
  for (const feature of ['RCLowPowerSchedule.h', 'RCBatteryRecord.h', 'mountCustomDirectory:']) {
    assert.ok(read(file).includes(feature), feature);
  }
});

test('the only addition to ZQBB SpringBoard hooks starts our power and recording services', () => {
  const file = 'BaseBin/roothidehooks/src/springboard.x';
  const baseline = read(file).replace('#import "RCScheduleRuntime.h"\n', '')
    .replace('\n\trcScheduleServicesStartAfterLaunch();', '');
  assert.equal(digest(baseline), manifest.upstreamSections.springboard);
  const services = read('BaseBin/roothidehooks/src/springboardservices.m');
  for (const symbol of ['rcLowPowerScheduleStart();', 'rcBatteryRecordStart();']) {
    assert.ok(services.includes(symbol), symbol);
  }
});
