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
        if ($strip.Right -gt $btnCopy.Left -or $state.Refresh.Right -gt $strip.ClientSize.Width) { throw 'Minimum-width toolbar clipped' }
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
