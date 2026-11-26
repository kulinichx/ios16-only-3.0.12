const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const {execFileSync} = require('node:child_process');
const test = require('node:test');
const {patchIssuerSource} = require('../scripts/install-supporter-binding-integration.cjs');

test('actual issuer profile dialog cancels, saves, refreshes and searches old names without signing', {
  skip: process.platform !== 'win32' || !process.env.DORH_ISSUER_SOURCE,
}, () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'rh-profile-ui-'));
  try {
    const records = ['0027', '0028'].map(SupporterId => ({SupporterId, DisplayName: `Original user ${SupporterId}`,
      DeviceCode: `${SupporterId}-4567-89AB-CDEF-0123-4567-89AB-CDEF`, Note: 'Synthetic note', License: 'RH1.SYNTHETIC-ONLY',
      FirstIssuedAt: 'first-date', LastIssuedAt: 'last-date'}));
    fs.writeFileSync(path.join(directory, 'supporters.json'), JSON.stringify(records));
    for (const name of ['SupporterBindingIntegration.ps1', 'SupporterProfileIntegration.ps1']) {
      fs.copyFileSync(path.resolve(__dirname, '../scripts', name), path.join(directory, name));
    }
    fs.writeFileSync(path.join(directory, 'supporter-binding.cjs'), `if(process.argv[2]!=='plan') process.exit(44);console.log(JSON.stringify({total:2,eligible:0,needsProof:2,orphanBindings:0,records:[]}));`);
    const original = fs.readFileSync(process.env.DORH_ISSUER_SOURCE, 'utf8');
    const body = fs.readFileSync(path.join(__dirname, 'fixtures/supporter-profile-ui.ps1'), 'utf8').replace(/^\uFEFF/, '');
    const source = patchIssuerSource(original).replace('[void]$form.ShowDialog()', () => body);
    const filename = path.join(directory, 'RootHideSupporterIssuer.ps1');
    fs.writeFileSync(filename, source);
    const result = JSON.parse(execFileSync('powershell.exe', ['-NoProfile', '-STA', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', filename], {encoding: 'utf8', timeout: 20000}));
    assert.deepEqual(result, {Saved:true, CancelledWithoutWrite:true, LoadedId:'0028', Rows:2});
    const updated = JSON.parse(fs.readFileSync(path.join(directory, 'supporters.json')));
    assert.deepEqual(updated[0], records[0]);
    assert.equal(updated[1].License, records[1].License);
    assert.equal(updated[1].LastIssuedAt, records[1].LastIssuedAt);
    assert.equal(fs.readdirSync(directory).some(name => name.endsWith('.pem') || name.endsWith('-bound.txt')), false);
  } finally { fs.rmSync(directory, {recursive:true, force:true}); }
});
