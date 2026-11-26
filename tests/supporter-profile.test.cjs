const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const {execFileSync} = require('node:child_process');
const test = require('node:test');

test('profile edits preserve identity, licenses, timestamps, unknown fields and other users; writes are backed up, atomic and stale-safe', {
  skip: process.platform !== 'win32',
}, () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'rh-profile-test-'));
  try {
    const records = ['0027', '0028'].map(SupporterId => ({SupporterId, DisplayName: '旧用户名',
      DeviceCode: `${SupporterId}-4567-89AB-CDEF-0123-4567-89AB-CDEF`, Note: '旧联系方式和备注',
      License: 'RH1.SYNTHETIC-ONLY', FirstIssuedAt: 'first-date', LastIssuedAt: 'last-date', Extra: {retain: true}}));
    fs.writeFileSync(path.join(directory, 'supporters.json'), JSON.stringify(records));
    const protectedFiles = ['supporter-device-proof-bindings.json', 'supporter-device-info.json', 'DopamineRH-supporter-private.pem'];
    for (const name of protectedFiles) fs.writeFileSync(path.join(directory, name), 'SYNTHETIC SENTINEL');
    const result = JSON.parse(execFileSync('powershell.exe', ['-NoProfile', '-STA', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
      '-File', path.join(__dirname, 'fixtures/supporter-profile.ps1'), '-Directory', directory,
      '-Source', path.resolve(__dirname, '../scripts/SupporterProfileIntegration.ps1')], {encoding: 'utf8', timeout: 15000}));
    assert.deepEqual(result, {Saved: true, FailurePreserved: true, StaleRejected: true});
    const updated = JSON.parse(fs.readFileSync(path.join(directory, 'supporters.json')));
    assert.deepEqual(updated[1], records[1]);
    const {DisplayName, Contact, Note, PreviousDisplayNames, ...stable} = updated[0];
    const {DisplayName: oldName, Note: oldNote, ...before} = records[0];
    assert.deepEqual(stable, before);
    assert.equal(DisplayName, '新用户名');
    assert.equal(Contact, '');
    assert.equal(Note, '备注再次修改');
    assert.deepEqual(PreviousDisplayNames, ['旧用户名']);
    for (const name of protectedFiles) assert.equal(fs.readFileSync(path.join(directory, name), 'utf8'), 'SYNTHETIC SENTINEL');
  } finally { fs.rmSync(directory, {recursive: true, force: true}); }
});
