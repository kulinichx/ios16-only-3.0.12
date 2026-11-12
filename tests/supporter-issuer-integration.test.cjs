const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const crypto = require('node:crypto');
const { execFileSync } = require('node:child_process');
const test = require('node:test');
const { patchIssuerSource, install } = require('../scripts/install-supporter-binding-integration.cjs');

const root = path.resolve(__dirname, '..');
const hash = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const source = '\uFEFF$script:BaseDir = $PSScriptRoot\n' +
  '$licensePanel = $null\n$grid = $null\n$txtLicense = $null\n$status = $null\n' +
  '$btnVerifyProof = $null\n$btnIssue = $null\nfunction Refresh-Grid {}\n[void]$form.ShowDialog()\n';

function fixture(run) {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'rh-issuer-integration-'));
  try { return run(directory); }
  finally { fs.rmSync(directory, { recursive: true, force: true }); }
}

test('issuer hook preserves UTF-8 BOM and line endings, is idempotent and rejects unknown layouts', () => {
  for (const original of [source, source.replace(/\n/g, '\r\n')]) {
    const patched = patchIssuerSource(original);
    assert.ok(patched.startsWith('\uFEFF'));
    assert.equal(patched.replace(/\r\n/g, '\n').split('# RootHide binding integration v1').length, 2);
    assert.equal(patchIssuerSource(patched), patched);
    assert.equal(patched.endsWith('\r\n'), original.endsWith('\r\n'));
    assert.ok(patched.indexOf('Initialize-RHBindingIntegration') < patched.indexOf('[void]$form.ShowDialog()'));
  }
  for (const invalid of [source + 'unexpected', source + source,
    source.replace('$grid =', '$different ='), '# RootHide binding integration v1\n' + source]) {
    assert.throws(() => patchIssuerSource(invalid));
  }
});

test('integration installation backs up program source only and leaves issuer secrets and databases untouched', () => {
  fixture(directory => {
    const issuerPath = path.join(directory, 'RootHideSupporterIssuer.ps1');
    fs.writeFileSync(issuerPath, source);
    const protectedNames = ['supporters.json', 'supporters.backup.json', 'supporter-device-proof-bindings.json',
      'supporter-device-proof-challenges.json', 'DopamineRH-supporter-private.pem', 'supporter-0028-bound.txt'];
    const before = new Map(protectedNames.map(name => [name, Buffer.from(`TEST SENTINEL ONLY ${name}`)]));
    for (const [name, bytes] of before) fs.writeFileSync(path.join(directory, name), bytes);
    const guarded = { ...fs, readFileSync(filename, ...args) {
      assert.equal(protectedNames.includes(path.basename(filename)), false, 'installer must never read user data or keys');
      return fs.readFileSync(filename, ...args);
    } };
    const result = install(directory, hash(source), guarded);
    assert.equal(result.changed, true);
    assert.deepEqual(fs.readFileSync(path.join(result.backup, 'RootHideSupporterIssuer.ps1')), Buffer.from(source));
    assert.deepEqual(fs.readdirSync(result.backup).sort(), ['RootHideSupporterIssuer.ps1', 'installation.json']);
    assert.equal(hash(fs.readFileSync(issuerPath)), result.issuerSha256);
    assert.equal(fs.readFileSync(path.join(directory, 'SupporterBindingIntegration.ps1')).subarray(0, 3).toString('hex'), 'efbbbf');
    assert.equal(install(directory, result.issuerSha256, guarded).changed, false);
    for (const [name, bytes] of before) assert.deepEqual(fs.readFileSync(path.join(directory, name)), bytes);
    assert.equal(fs.readdirSync(path.join(directory, 'program-backups')).length, 1);
  });
});

test('integration installation refuses source drift, unknown sidecars and failures before replacing the issuer', () => {
  fixture(directory => {
    const issuerPath = path.join(directory, 'RootHideSupporterIssuer.ps1');
    fs.writeFileSync(issuerPath, source);
    assert.throws(() => install(directory, '0'.repeat(64)), /source-changed/);
    fs.writeFileSync(path.join(directory, 'supporter-binding.cjs'), 'user modification');
    assert.throws(() => install(directory, hash(source)), /existing-program-file-differs/);
    assert.equal(fs.readFileSync(issuerPath, 'utf8'), source);
  });
  for (const mode of ['write-failure', 'concurrent-source-change']) fixture(directory => {
    const issuerPath = path.join(directory, 'RootHideSupporterIssuer.ps1');
    fs.writeFileSync(issuerPath, source);
    let sourceReads = 0;
    const io = { ...fs, readFileSync(filename, ...args) {
      if (filename === issuerPath && ++sourceReads === 2 && mode === 'concurrent-source-change') {
        fs.writeFileSync(issuerPath, source + '# concurrent change');
      }
      return fs.readFileSync(filename, ...args);
    }, renameSync(...args) {
      if (mode === 'write-failure') throw new Error('injected-rename-failure');
      return fs.renameSync(...args);
    } };
    assert.throws(() => install(directory, hash(source), io), /source-changed-before-install|injected-rename-failure/);
    assert.equal(fs.readFileSync(issuerPath, 'utf8'), source + (mode === 'concurrent-source-change' ? '# concurrent change' : ''));
    assert.deepEqual(fs.readdirSync(directory).sort(), ['RootHideSupporterIssuer.ps1', 'program-backups']);
  });
});

test('reviewed preceding integration upgrades with full program backup and rollback on partial failure', t => {
  const names = ['SupporterBindingIntegration.ps1', 'supporter-binding.cjs'];
  let previous;
  try {
    previous = names.map(name => execFileSync('git', ['-c', `safe.directory=${root.replace(/\\/g, '/')}`,
      'show', `f0ff47bc933ec7d9826f134c4c3902bd778ac211:scripts/${name}`], { cwd: root, stdio: ['ignore', 'pipe', 'ignore'] }));
  } catch { t.skip('Reviewed predecessor commit not present in a shallow checkout.'); return; }
  for (const fail of [false, true]) fixture(directory => {
    const patched = patchIssuerSource(source);
    fs.writeFileSync(path.join(directory, 'RootHideSupporterIssuer.ps1'), patched);
    names.forEach((name, index) => fs.writeFileSync(path.join(directory, name), previous[index]));
    let renames = 0;
    const io = { ...fs, renameSync(...args) {
      if (fail && ++renames === 2) throw new Error('injected-upgrade-failure');
      return fs.renameSync(...args);
    } };
    if (fail) {
      assert.throws(() => install(directory, hash(patched), io), /injected-upgrade-failure/);
      names.forEach((name, index) => assert.deepEqual(fs.readFileSync(path.join(directory, name)), previous[index]));
      assert.equal(fs.existsSync(path.join(directory, 'supporter-key-review.cjs')), false);
      assert.equal(fs.readdirSync(directory).some(name => name.endsWith('.tmp')), false);
    } else {
      const result = install(directory, hash(patched), io);
      assert.equal(result.changed, true);
      names.forEach((name, index) => assert.deepEqual(fs.readFileSync(path.join(result.backup, name)), previous[index]));
      for (const name of [...names, 'supporter-key-review.cjs']) {
        assert.deepEqual(fs.readFileSync(path.join(directory, name)), fs.readFileSync(path.join(root, 'scripts', name)));
      }
    }
    assert.equal(fs.readFileSync(path.join(directory, 'RootHideSupporterIssuer.ps1'), 'utf8'), patched);
  });
});

test('Windows issuer integration uses the original window, reviews single and batch snapshots and never signs on refresh or cancellation', {
  skip: process.platform !== 'win32' ? 'Requires Windows Forms; no real issuer data or private key is opened.' : false,
}, () => {
  fixture(directory => {
    const records = ['0027', '0028', '0029'].map((id, index) => ({
      id, displayName: index === 0 ? '\u6d4b\u8bd5\u7528\u6237' : `Example ${id}`,
      deviceCode: `${id}-4567-89AB-CDEF-0123-4567-89AB-CDEF`, lastIssuedAt: '2026-11-12 10:20:30',
      note: index === 0 ? 'contact\r\nsecond line' : '',
      status: index === 1 ? 'LEGACY_UNBOUND' : 'READY_FOR_REVIEW', reviewSha256: String(index + 1).repeat(64),
    }));
    fs.writeFileSync(path.join(directory, 'preview.json'), JSON.stringify({ total: 3, eligible: 2, needsProof: 1,
      orphanBindings: 0, reviewSha256: 'A'.repeat(64), records }));
    fs.copyFileSync(path.join(root, 'scripts/SupporterBindingIntegration.ps1'), path.join(directory, 'SupporterBindingIntegration.ps1'));
    fs.writeFileSync(path.join(directory, 'supporter-binding.cjs'), `
      const fs = require('node:fs'), path = require('node:path');
      const args = process.argv.slice(2), command = args[0], options = Object.fromEntries(Array.from({length:(args.length-1)/2}, (_,i) => [args[i*2+1],args[i*2+2]]));
      const directory = __dirname;
      fs.appendFileSync(path.join(directory,'commands.jsonl'), JSON.stringify(args)+'\\n');
      const preview = JSON.parse(fs.readFileSync(path.join(directory,'preview.json')));
      if (command === 'plan') {
        if(fs.existsSync(path.join(directory,'plan-failure'))) { console.error('injected-plan-failure'); process.exit(42); }
        console.log(JSON.stringify(preview));
      } else if (command === 'review-proof') {
        if (fs.readFileSync(0,'utf8') !== 'SYNTHETIC-PROOF-STDIN') process.exit(45);
        if (fs.existsSync(path.join(directory,'review-failure'))) process.exit(46);
        preview.records[2].status = 'REVIEW_KEY_MISMATCH'; preview.eligible = 1;
        fs.writeFileSync(path.join(directory,'preview.json'), JSON.stringify(preview));
        console.log(JSON.stringify({id:'0029',status:'REVIEW_KEY_MISMATCH'}));
      } else if (command === 'block-key-review') {
        preview.records[2].status = 'REVERIFY_REQUIRED';
        fs.writeFileSync(path.join(directory,'preview.json'), JSON.stringify(preview));
        console.log(JSON.stringify({id:'0029',status:'REVERIFY_REQUIRED'}));
      } else if (command === 'rekey-plan') {
        console.log(JSON.stringify({id:'0029',displayName:'Synthetic iPad',deviceCode:preview.records[2].deviceCode,
          note:'TEST ONLY',hardwareHash:'A'.repeat(64),oldKeyFingerprint:'B'.repeat(64),newKeyFingerprint:'C'.repeat(64),reviewSha256:'D'.repeat(64)}));
      } else if (command === 'rekey') {
        if(options['--id'] !== '0029' || options['--confirm-id'] !== '0029' || options['--review-sha256'] !== 'D'.repeat(64)) process.exit(47);
        preview.records[2].status = 'READY_FOR_REVIEW'; preview.eligible = 2;
        fs.writeFileSync(path.join(directory,'preview.json'), JSON.stringify(preview));
        console.log(JSON.stringify({migrated:true,id:'0029',backup:'SYNTHETIC BACKUP',signingPerformed:false}));
      } else {
        const record = preview.records.find(r => r.id === options['--id']);
        const expected = command === 'issue-all' ? preview.reviewSha256 : record?.reviewSha256;
        if(options['--review-sha256'] !== expected) { console.error('review-stale-reload-plan'); process.exit(43); }
        if(command === 'issue') fs.writeFileSync(options['--out'], 'RH1.TEST-ONLY\\nRHB1.TEST-ONLY\\n', {flag:'wx'});
        console.log(JSON.stringify({issued:command === 'issue' ? 1 : preview.eligible, cleanupWarnings:[]}));
      }
    `);
    const image = process.env.DORH_ISSUER_REVIEW_IMAGE || path.join(directory, 'review.png');
    const result = JSON.parse(execFileSync('powershell.exe', ['-NoProfile', '-NonInteractive', '-STA', '-ExecutionPolicy',
      'Bypass', '-File', path.join(root, 'tests/fixtures/supporter-issuer-integration.ps1'), '-Directory', directory,
      '-PreviewImage', image], { encoding: 'utf8', timeout: 45000 }));
    assert.equal(result.Checked, true);
    assert.equal(result.ReviewRows, 2);
    assert.equal(result.CanSignAfterFailure, false);
    assert.equal(result.OriginalProofEvents, 1);
    assert.equal(result.RealClipboardTouched, false);
    assert.ok(fs.readFileSync(image).subarray(1, 4).toString() === 'PNG');
    assert.equal(fs.existsSync(path.join(directory, 'DopamineRH-supporter-private.pem')), false);
  });
});

test('original issuer source opens with integrated controls and refreshes its data-bound history using synthetic users only', {
  skip: process.platform !== 'win32' || !process.env.DORH_ISSUER_SOURCE
    ? 'Optional Windows test of the owner-provided program source; no production databases are read.' : false,
}, () => {
  fixture(directory => {
    const records = ['0027', '0028'].map((id, index) => ({ SupporterId: id,
      DeviceCode: `${id}-4567-89AB-CDEF-0123-4567-89AB-CDEF`, DisplayName: `Synthetic user ${id}`,
      Note: 'TEST DATA ONLY', License: 'RH1.TEST-ONLY', FirstIssuedAt: '2026-11-12 10:20:30', LastIssuedAt: '2026-11-12 10:20:30' }));
    fs.writeFileSync(path.join(directory, 'supporters.json'), JSON.stringify(records));
    fs.writeFileSync(path.join(directory, 'supporter-device-proof-bindings.json'), '[]');
    const before = fs.readFileSync(path.join(directory, 'supporters.json'));
    fs.copyFileSync(path.join(root, 'scripts/SupporterBindingIntegration.ps1'), path.join(directory, 'SupporterBindingIntegration.ps1'));
    const preview = { total: 2, eligible: 1, needsProof: 1, orphanBindings: 0, reviewSha256: 'A'.repeat(64),
      records: records.map((row, index) => ({ id: row.SupporterId, displayName: row.DisplayName,
        deviceCode: row.DeviceCode, lastIssuedAt: row.LastIssuedAt, note: row.Note,
        status: index === 0 ? 'READY_FOR_REVIEW' : 'LEGACY_UNBOUND', reviewSha256: 'B'.repeat(64) })) };
    fs.writeFileSync(path.join(directory, 'supporter-binding.cjs'),
      `if(process.argv[2] !== 'plan') process.exit(44); console.log(${JSON.stringify(JSON.stringify(preview))});`);
    const original = fs.readFileSync(process.env.DORH_ISSUER_SOURCE, 'utf8');
    const instrumented = patchIssuerSource(original).replace('[void]$form.ShowDialog()', `
      $form.Show()
      [Windows.Forms.Application]::DoEvents()
      try {
        Refresh-Grid
        $txtSearch.Text = '0027'
        [Windows.Forms.Application]::DoEvents()
        if ($grid.Rows.Count -ne 1 -or -not $script:RHIntegratedBinding.Single.Enabled) { throw 'Filtered bound user unavailable' }
        $txtSearch.Text = ''
        [Windows.Forms.Application]::DoEvents()
        if ($grid.Rows.Count -ne 2) { throw 'Original history refresh lost users' }
        if (@($grid.Columns | Where-Object { $_.Name -eq 'RHBindingState' }).Count -ne 1) { throw 'Duplicate binding state column' }
        if ($grid.Rows[0].Cells['RHBindingState'].Value -ne '待设备证明') { throw 'Original descending history has wrong state' }
        if ($grid.Rows[1].Cells['RHBindingState'].Value -ne '已有设备证明') { throw 'Bound row state lost on refresh' }
        $state = $script:RHIntegratedBinding
        $strip = $state.Single.Parent
        if ($strip.Right -gt $btnCopy.Left -or $strip.Top -lt 0 -or $strip.Bottom -gt $txtLicense.Top) { throw 'Original copy/output controls overlapped' }
        $form.ClientSize = New-Object Drawing.Size(790, 930)
        $form.PerformLayout()
        if ($strip.Right -gt $btnCopy.Left -or $state.Rekey.Right -gt $strip.ClientSize.Width) { throw 'Minimum-width toolbar clipped' }
        $form.ClientSize = New-Object Drawing.Size(820, 950)
        $form.PerformLayout()
        $bitmap = New-Object Drawing.Bitmap($form.Width, $form.Height)
        try { $form.DrawToBitmap($bitmap, (New-Object Drawing.Rectangle(0, 0, $form.Width, $form.Height))); $bitmap.Save($env:DORH_ISSUER_MAIN_IMAGE, [Drawing.Imaging.ImageFormat]::Png) }
        finally { $bitmap.Dispose() }
        [pscustomobject]@{Rows=$grid.Rows.Count; Columns=$grid.Columns.Count; BatchEnabled=$state.Batch.Enabled} | ConvertTo-Json -Compress
      } finally { $form.Close(); $form.Dispose() }
    `);
    const script = path.join(directory, 'RootHideSupporterIssuer.ps1');
    fs.writeFileSync(script, instrumented);
    const result = JSON.parse(execFileSync('powershell.exe', ['-NoProfile', '-NonInteractive', '-STA', '-ExecutionPolicy', 'Bypass', '-File', script], {
      encoding: 'utf8', timeout: 45000, env: { ...process.env, DORH_ISSUER_MAIN_IMAGE:
        process.env.DORH_ISSUER_MAIN_IMAGE || path.join(directory, 'main.png') },
    }));
    assert.deepEqual(result, { Rows: 2, Columns: 6, BatchEnabled: true });
    assert.deepEqual(fs.readFileSync(path.join(directory, 'supporters.json')), before);
    assert.equal(fs.existsSync(path.join(directory, 'DopamineRH-supporter-private.pem')), false);
  });
});

test('original verifier consumes a disposable signed RHP1, preserves mismatch and explicitly migrates only the test device', {
  skip: process.platform !== 'win32' || !process.env.DORH_ISSUER_SOURCE
    ? 'Optional original-program/OpenSSL test using disposable keys and synthetic data only.' : false,
}, () => fixture(directory => {
  const binding = require('../scripts/supporter-binding.cjs');
  const issuer = crypto.generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
  const deviceKeys = [0, 1].map(() => crypto.generateKeyPairSync('ec', { namedCurve: 'prime256v1' }));
  const points = deviceKeys.map(key => {
    const jwk = key.publicKey.export({ format: 'jwk' });
    return Buffer.concat([Buffer.from([4]), Buffer.from(jwk.x, 'base64url'), Buffer.from(jwk.y, 'base64url')]);
  });
  const deviceCode = '0123-4567-89AB-CDEF-0123-4567-89AB-CDEF';
  const hardware = binding.sha256('synthetic iPad');
  const body = Buffer.from(JSON.stringify({ v: 1, product: 'DopamineRH', sid: '0029', device: deviceCode, ent: ['custom_glass'] }));
  const license = `RH1.${body.toString('base64url')}.${crypto.sign('sha256', body, issuer.privateKey).toString('base64url')}`;
  fs.writeFileSync(path.join(directory, 'supporters.json'), JSON.stringify([{ SupporterId: '0029', DeviceCode: deviceCode,
    DisplayName: 'Synthetic iPad', Note: 'TEST DATA ONLY', License: license, LastIssuedAt: '2026-11-12 10:20:30' }]));
  const baseline = [{ DeviceCode: deviceCode, HardwareHash: hardware, KeyFingerprint: binding.sha256(points[0]),
    PublicKey: points[0].toString('base64url'), FirstVerifiedAt: 'preserve-original-test-date' }];
  const bindingsPath = path.join(directory, 'supporter-device-proof-bindings.json');
  fs.writeFileSync(bindingsPath, JSON.stringify(baseline));
  const before = fs.readFileSync(bindingsPath);
  const timestamp = Math.floor(Date.now() / 1000);
  const challenge = { type: 'RHC1', version: 1, challenge_id: 'D'.repeat(32), nonce: 'E'.repeat(64),
    issued_at: timestamp, expires_at: timestamp + 300, audience: 'com.dopaminerh.supporter.device-proof' };
  const canonical = JSON.stringify(challenge);
  fs.writeFileSync(path.join(directory, 'supporter-device-proof-challenges.json'), JSON.stringify([{
    ChallengeId: challenge.challenge_id, State: 'ISSUED', DeviceCode: deviceCode, Canonical: canonical,
    ChallengeHash: binding.sha256(canonical), IssuedAt: timestamp, ExpiresAt: timestamp + 300, ConsumedAt: '' }]));
  const unsigned = { type: 'RHP1', version: 1, challenge_id: challenge.challenge_id, challenge_hash: binding.sha256(canonical),
    hardware_protocol: 'rh-hw-v1', hardware_hash: hardware, key_fingerprint: binding.sha256(points[1]),
    public_key: points[1].toString('base64url'), signature_algorithm: 'ecdsa-p256-sha256-x962' };
  const signature = crypto.sign('sha256', Buffer.concat([Buffer.from('DopamineRH-RHP1-Sign-v1\0'),
    Buffer.from(JSON.stringify(unsigned))]), deviceKeys[1].privateKey).toString('base64url');
  fs.writeFileSync(path.join(directory, 'synthetic-proof.json'), JSON.stringify({ ...unsigned, signature }));
  fs.copyFileSync(path.join(root, 'scripts/SupporterBindingIntegration.ps1'), path.join(directory, 'SupporterBindingIntegration.ps1'));
  fs.writeFileSync(path.join(directory, 'supporter-binding.cjs'), `
    const binding = require(${JSON.stringify(path.join(root, 'scripts/supporter-binding.cjs'))});
    const publicKey = require('node:crypto').createPublicKey(${JSON.stringify(issuer.publicKey.export({ format: 'pem', type: 'spki' }))});
    try { binding.main(process.argv.slice(2), publicKey); } catch(e) { console.error(e.message); process.exitCode=1; }
  `);
  const original = fs.readFileSync(process.env.DORH_ISSUER_SOURCE, 'utf8');
  const instrumented = patchIssuerSource(original).replace('[void]$form.ShowDialog()', `
    $form.Show()
    [Windows.Forms.Application]::DoEvents()
    try {
      $wire = [IO.File]::ReadAllText((Join-Path $script:BaseDir 'synthetic-proof.json'))
      $verified = Verify-RHP1Proof $wire 'NORMAL'
      if ($verified.Policy -ne 'REVIEW_KEY_MISMATCH') { throw 'Original verifier lost mismatch policy' }
      Refresh-RHIntegratedBindingPlan
      $state = $script:RHIntegratedBinding
      $grid.ClearSelection(); $grid.Rows[0].Selected = $true
      if ($state.Single.Enabled -or -not $state.Rekey.Enabled) { throw 'Original proof did not persist blocking review' }
      $oldFingerprint = [string]$script:Bindings[0].KeyFingerprint
      function Confirm-RHIntegratedKeyReview($Plan) { return '0029' }
      function Show-RHIntegratedBindingMessage($Message, $Failed = $false) { if ($Failed) { throw $Message } }
      Start-RHIntegratedKeyMigration
      if (-not $state.Single.Enabled -or $state.Rekey.Enabled) { throw 'Explicit migration did not restore supplement review' }
      if ([string]$script:Bindings[0].KeyFingerprint -eq $oldFingerprint) { throw 'Original verifier memory not reloaded after migration' }
      [pscustomobject]@{Policy=$verified.Policy; State=$script:Challenges[0].State; SupplementEnabled=$state.Single.Enabled} | ConvertTo-Json -Compress
    } finally { $form.Close(); $form.Dispose() }
  `);
  const script = path.join(directory, 'RootHideSupporterIssuer.ps1');
  fs.writeFileSync(script, instrumented);
  const result = JSON.parse(execFileSync('powershell.exe', ['-NoProfile', '-NonInteractive', '-STA', '-ExecutionPolicy',
    'Bypass', '-File', script], { encoding: 'utf8', timeout: 45000 }));
  assert.deepEqual(result, { Policy: 'REVIEW_KEY_MISMATCH', State: 'CONSUMED', SupplementEnabled: true });
  const updated = JSON.parse(fs.readFileSync(bindingsPath));
  assert.equal(updated[0].KeyFingerprint, binding.sha256(points[1]));
  assert.equal(updated[0].FirstVerifiedAt, baseline[0].FirstVerifiedAt);
  const backups = fs.readdirSync(path.join(directory, 'binding-backups')).map(name => path.join(directory, 'binding-backups', name));
  assert.equal(backups.filter(dir => fs.existsSync(path.join(dir, 'supporter-device-proof-bindings.json')))
    .some(dir => fs.readFileSync(path.join(dir, 'supporter-device-proof-bindings.json')).equals(before)), true);
  assert.equal(fs.existsSync(path.join(directory, 'DopamineRH-supporter-private.pem')), false);
  assert.equal(fs.readdirSync(directory).some(name => name.endsWith('-bound.txt')), false);
}));
