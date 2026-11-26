'use strict';

const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');

const hash = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const knownPrevious = {
  'SupporterBindingIntegration.ps1': [
    'd6cab08aa685596f5c8c26fbc2b2cff84d6f3ac708a6efee082931a1cfcabf57',
    '22ebaa8c70cc369d57bb669f36ee26afd8683820384e5cd2d0d3b3cb39558c60',
    'f81549316edc11a8e1208e32e52610a0e3b327c18c7192a2a18228fe5c6916a2',
    '3eb46879a75965071bf12cbce02c6918a4d9d9138c2dabc7faf04f7b57746a57',
    '4937a801b3ca4aeac810f04812dc4412661864eb0e9cc988a7bcdc420c226ed2',
    '400b5166d3babdfce08a05ce52dcfbc188cf8415127973f30050dd08e8fcbd38',
  ],
  'supporter-key-review.cjs': ['b1efacb58f26190f2af47fcb040e8de02ba9befd2fa78098161d1c6acbf99001',
    '8b0bfa130a5be0a93bc096bf68e42fef29e75cf4afc3f44ea51a9fec9ad0a71d'],
  'supporter-binding.cjs': ['a78695c9dc1be96c61a469dc89f5960436284cfad939b9fbdeca95e5a19463c9'],
};
const marker = '# RootHide binding integration v1';
const hook = `${marker}
. (Join-Path $script:BaseDir 'SupporterBindingIntegration.ps1')
Initialize-RHBindingIntegration @{
    Directory = $script:BaseDir; Form = $form; Panel = $licensePanel
    Grid = $grid; Output = $txtLicense; Status = $status
    VerifyProofButton = $btnVerifyProof; RH1IssueButton = $btnIssue
}
`;

const guidanceMarker = '# RootHide issuer proof guidance v1';

function replaceIssuerText(source, before, after) {
  if (source.split(before).length !== 2) throw new Error('unsupported-issuer-proof-guidance-layout: ' + before.split('\n')[0].trim());
  return source.replace(before, () => after);
}

function patchProofGuidance(source) {
  const migration = 'function Show-DeviceCodeMigrationDialog(';
  if (!source.includes(migration) || source.includes(guidanceMarker)) return source;
  source = replaceIssuerText(source, migration, `${guidanceMarker}\n${migration}`);
  const replacements = [
    ['$lblSource.Text = "Source Supporter"', '$lblSource.Text = "原用户和原设备码"'],
    ['$lblTarget.Text = "NEW Device Code"', '$lblTarget.Text = "新设备码（NEW Device Code）"'],
    ['$lblResult.Text = "Verification Result"', '$lblResult.Text = "验证结果和下一步"'],
    ['$txtResult.Text = "等待生成 migration RHC1。"', '$txtResult.Text = "填入对方发来的新设备码，再点击「生成 Migration RHC1」。"'],
    ['$txtResult.Size = New-Object System.Drawing.Size(596, 122)', '$txtResult.Size = New-Object System.Drawing.Size(596, 158)'],
    ['$dialog.ClientSize = New-Object System.Drawing.Size(640, 520)', '$dialog.ClientSize = New-Object System.Drawing.Size(640, 556)'],
    ['$btnCloseMigration.Location = New-Object System.Drawing.Point(498, 466)', '$btnCloseMigration.Location = New-Object System.Drawing.Point(498, 502)'],
    ['"MIGRATION RHC1 READY",', '"验证文本已复制（RHC1）",'],
    ['"请让用户在 App 点击 Bind This Device，然后把返回的 RHP1 复制回来。",',
      '"下一步 · 让用户在多巴胺「支持者授权」点「2. 生成证明码」。复制他发回的完整 RHP1，在本窗口点击验证。",'],
    ['$txtResult.Text = $_.Exception.Message\n            Show-Error $_.Exception.Message',
      '$txtResult.Text = Get-RHProofErrorText $_.Exception.Message $true\n            Show-Error $txtResult.Text'],
    ['$txtResult.Text = "VERIFY FAILED`r`n`r`n" + $message', '$txtResult.Text = "设备证明验证失败`r`n`r`n" + (Get-RHProofErrorText $message $true)'],
    ['            Show-Error $message\n        }\n    })\n\n    $btnCloseMigration',
      '            Show-Error $txtResult.Text\n        }\n    })\n\n    $btnCloseMigration'],
    ['$status.Text = "Migration Verify PASS · policy=" + [string]$result.Policy + " · 尚未修改记录"',
      '$status.Text = (Get-RHProofResultText ([string]$result.Policy) $true).Split("`r")[0]'],
    ['$status.Text = "RHP1 cryptographic verification PASS · challenge 已消费 · policy=" + [string]$result.Policy',
      '$guidance = Get-RHProofResultText ([string]$result.Policy)\n        $status.Text = $guidance.Split("`r")[0]\n        Show-Info $guidance'],
    ['        Set-DeviceState "RHP1 验证失败；challenge 不会因无效 proof 被消费（过期除外）" "Warning"\n        Show-Error $message',
      '        Set-DeviceState "设备证明验证失败 · 请按提示检查" "Warning"\n        Show-Error (Get-RHProofErrorText $message)'],
    ['"● REVIEW"', '"● 同设备 · 密钥待复核"'],
    ['"● Hardware mismatch"', '"● 硬件不符 · 停止补发"'],
  ];
  for (const [before, after] of replacements) source = replaceIssuerText(source, before, after);

  const first = '            $resultLines.Add([string]$result.Policy)\n';
  const last = '            $txtResult.Text = $resultLines -join "`r`n"';
  if (source.split(first).length !== 2 || source.split(last).length !== 2 || source.indexOf(first) >= source.indexOf(last)) {
    throw new Error('unsupported-issuer-migration-result-layout');
  }
  const result = [
    '            $resultLines.Add((Get-RHProofResultText ([string]$result.Policy) $true))',
    '            $resultLines.Add("")',
    '            $resultLines.Add("原用户 · #" + [string]$result.SupporterId)',
    '            $resultLines.Add("原设备码 · " + [string]$result.SourceDeviceCode)',
    '            $resultLines.Add("新设备码 · " + [string]$result.TargetDeviceCode)',
    '            $resultLines.Add("RHP1 签名有效 · 验证文本已使用")',
    last,
  ].join('\n');
  return source.slice(0, source.indexOf(first)) + result + source.slice(source.indexOf(last) + last.length);
}

const deviceInfoMarker = '# RootHide issuer device info v1';
const profileMarker = '# RootHide issuer profile editing v1';
const statusMarker = '# RootHide issuer binding status feedback v1';

function patchProfileEditing(source) {
  if (!source.includes('function Get-FilteredRecords {') || source.includes(profileMarker)) return source;
  const searchStart = '                ([string]$_.SupporterId).IndexOf($q, [StringComparison]::OrdinalIgnoreCase) -ge 0 -or';
  const searchEnd = '                ([string]$_.Note).IndexOf($q, [StringComparison]::OrdinalIgnoreCase) -ge 0';
  if (source.split(searchStart).length !== 2 || source.split(searchEnd).length !== 2) throw new Error('unsupported-profile-search-layout');
  source = source.slice(0, source.indexOf(searchStart)) + '                Test-RHProfileSearch $_ $q' + source.slice(source.indexOf(searchEnd) + searchEnd.length);
  source = replaceIssuerText(source, '@{Name="联系方式 / 备注";Expression={$_.Note}}', '@{Name="联系方式 / 备注";Expression={Get-RHProfileSummary $_}}');
  source = replaceIssuerText(source, '@{Name="联系方式或备注";Expression={$_.Note}},',
    '@{Name="联系方式";Expression={Get-RHProfileField $_ \'Contact\'}},\n' +
    '                @{Name="备注";Expression={$_.Note}},\n' +
    '                @{Name="历史用户名";Expression={@(Get-RHProfileField $_ \'PreviousDisplayNames\') -join \' / \'}},');
  // Functions must be available before the first Refresh-Grid at startup.
  source = replaceIssuerText(source, 'function Get-FilteredRecords {', profileMarker + '\n' +
    ". (Join-Path $script:BaseDir 'SupporterProfileIntegration.ps1')\n\nfunction Get-FilteredRecords {");
  source = replaceIssuerText(source, '[void]$form.ShowDialog()', 'Initialize-RHProfileIntegration\n[void]$form.ShowDialog()');
  // Equal line boxes plus a small optical offset align the Consolas digits.
  source = replaceIssuerText(source, '$lblIdValue.Location = New-Object System.Drawing.Point(112, 240)', [
    '$labelId.AutoSize = $false',
    '$labelId.Size = New-Object System.Drawing.Size(94, 24)',
    '$labelId.Location = New-Object System.Drawing.Point(18, 240)',
    '$labelId.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft',
    '$lblIdValue.AutoSize = $false',
    '$lblIdValue.Size = New-Object System.Drawing.Size(60, 24)',
    '$lblIdValue.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft',
    '$lblIdValue.Location = New-Object System.Drawing.Point(112, 242)',
  ].join('\n'));
  return source;
}

function patchProofDeviceInfo(source) {
  const versionCheck = "    if ($type -cne 'RHP1' -or [int64]$obj.version -ne 1) { throw \"RHP1 type/version 无效。\" }";
  const versionLogic = [
    '    $version = [int64]$obj.version',
    '    if ($type -cne \'RHP1\' -or $version -notin @(1, 2)) { throw "RHP1 type/version 无效。" }',
    '    $deviceModel = $null',
    '    $osVersion = $null',
    '    if ($version -eq 2) {',
    "        $modelField = $obj.PSObject.Properties['device_model']",
    "        $osField = $obj.PSObject.Properties['os_version']",
    '        if ($null -eq $modelField -or $null -eq $osField -or -not (Test-RHProofDeviceInfo $modelField.Value $osField.Value)) {',
    '            throw "invalid-proof-device-info：设备型号或系统版本格式无效。"',
    '        }',
    '        $deviceModel = $modelField.Value',
    '        $osVersion = $osField.Value',
    '    }',
  ].join('\n');
  source = replaceIssuerText(source, versionCheck, versionLogic);
  const construct = '    $canonicalFull = $canonicalUnsigned.Substring';
  source = replaceIssuerText(source, construct, [
    '    if ($version -eq 2) {',
    '        $canonicalUnsigned = $canonicalUnsigned.Replace(\'"version":1,\', \'"version":2,\')',
    '        $canonicalUnsigned = $canonicalUnsigned.Substring(0, $canonicalUnsigned.Length - 1) + \',"device_model":"\' + $deviceModel + \'","os_version":"\' + $osVersion + \'"}\'',
    '    }',
    construct,
  ].join('\n'));
  source = replaceIssuerText(source, 'RHP1 不是 canonical v1 encoding', 'RHP1 不是 canonical encoding');
  for (const indent of [8, 12]) {
    const pad = ' '.repeat(indent);
    const prop = '\n' + pad + 'PublicKey = $publicKeyText\n';
    source = replaceIssuerText(source, prop, prop + pad + 'DeviceModel = $deviceModel\n' + pad + 'OSVersion = $osVersion\n');
  }
  source = replaceIssuerText(source, '            $resultLines.Add("RHP1 签名有效 · 验证文本已使用")',
    '            $resultLines.AddRange([string[]](Show-RHProofDeviceInfo $result ([string]$result.SourceDeviceCode)))\n' +
    '            $resultLines.Add("RHP1 签名有效 · 验证文本已使用")');
  return replaceIssuerText(source, '        Show-Info $guidance',
    '        $deviceLines = Show-RHProofDeviceInfo $result ([string]$result.DeviceCode)\n' +
    '        Show-Info ($guidance + "`r`n`r`n" + ($deviceLines -join "`r`n"))');
}

function patchIssuerSource(source) {
  const newline = source.includes('\r\n') ? '\r\n' : '\n';
  let normalized = patchProofGuidance(source.replace(/\r\n/g, '\n'));
  const finalDialog = '[void]$form.ShowDialog()';
  if (normalized.includes(marker)) {
    if (!normalized.includes(hook)) throw new Error('existing-integration-hook-differs');
  } else {
    if (normalized.split(finalDialog).length !== 2 || !normalized.trimEnd().endsWith(finalDialog)) {
      throw new Error('unsupported-issuer-startup-layout');
    }
    for (const anchor of ['function Refresh-Grid', '$script:BaseDir', '$licensePanel =', '$grid =',
      '$txtLicense =', '$status =', '$btnVerifyProof =', '$btnIssue =']) {
      if (!normalized.includes(anchor)) throw new Error('missing-issuer-anchor: ' + anchor);
    }
    normalized = normalized.replace(finalDialog, hook + '\n' + finalDialog);
  }
  if (!normalized.includes(deviceInfoMarker) && normalized.includes('function Show-DeviceCodeMigrationDialog(')) {
    normalized = patchProofDeviceInfo(normalized);
    normalized = replaceIssuerText(normalized, finalDialog, [
      deviceInfoMarker,
      'Initialize-RHDeviceInfo $issuePanel $txtDevice $txtName',
      "$issuerIcon = Join-Path $script:BaseDir 'RootHideSupporterIssuer.ico'",
      'if (Test-Path -LiteralPath $issuerIcon) { $form.Icon = New-Object Drawing.Icon($issuerIcon) }',
      finalDialog,
    ].join('\n'));
  }
  normalized = patchProfileEditing(normalized);
  if (normalized.includes(deviceInfoMarker) && !normalized.includes(statusMarker)) {
    normalized = replaceIssuerText(normalized, finalDialog, [statusMarker,
      'Initialize-RHIntegratedStatusFeedback $txtDevice $topStatus $colorSuccess ${function:Set-DeviceState}',
      finalDialog].join('\n'));
  }
  return normalized.replace(/\n/g, newline);
}

function install(directory, expectedHash, io = fs) {
  if (!/^[a-f0-9]{64}$/i.test(expectedHash || '')) throw new Error('expected-source-sha256-required');
  const target = path.resolve(directory);
  const issuerPath = path.join(target, 'RootHideSupporterIssuer.ps1');
  const before = io.readFileSync(issuerPath);
  if (hash(before) !== expectedHash.toLowerCase()) throw new Error('issuer-source-changed');
  const modified = Buffer.from(patchIssuerSource(before.toString('utf8')), 'utf8');
  const names = ['SupporterBindingIntegration.ps1', 'supporter-binding.cjs', 'supporter-key-review.cjs'];
  if (modified.toString('utf8').includes(deviceInfoMarker)) names.push('RootHideSupporterIssuer.ico');
  if (modified.toString('utf8').includes(profileMarker)) names.push('SupporterProfileIntegration.ps1');
  const files = names.map(name => ({
    name, bytes: io.readFileSync(path.join(__dirname, name)), before: null,
  }));
  for (const file of files) {
    const filename = path.join(target, file.name);
    if (io.existsSync(filename)) {
      file.before = io.readFileSync(filename);
      if (!file.before.equals(file.bytes) && !(knownPrevious[file.name] || []).includes(hash(file.before))) {
        throw new Error(`existing-program-file-differs: ${file.name}`);
      }
    }
  }
  if (before.equals(modified) && files.every(file => file.before && file.before.equals(file.bytes))) {
    return { changed: false, issuerSha256: hash(before) };
  }
  const backup = path.join(target, 'program-backups', `binding-${new Date().toISOString().replace(/[:.]/g, '-')}-${crypto.randomBytes(4).toString('hex')}`);
  io.mkdirSync(backup, { recursive: true });
  io.writeFileSync(path.join(backup, 'RootHideSupporterIssuer.ps1'), before, { flag: 'wx' });
  for (const file of files) {
    if (file.before && !file.before.equals(file.bytes)) {
      io.writeFileSync(path.join(backup, file.name), file.before, { flag: 'wx' });
    }
  }
  const result = { changed: true, backup, issuerSha256: hash(modified),
    sourceSha256: hash(before), programFiles: files.map(file => ({ name: file.name, sha256: hash(file.bytes),
      previousSha256: file.before ? hash(file.before) : null })) };
  io.writeFileSync(path.join(backup, 'installation.json'), JSON.stringify(result, null, 2) + '\n', { flag: 'wx' });
  // The installer reads/copies program files only, never databases or a private key.
  const changes = [...files, { name: 'RootHideSupporterIssuer.ps1', bytes: modified, before }]
    .filter(file => !file.before || !file.before.equals(file.bytes));
  const installed = [];
  const staged = [];
  const matchesBefore = file => {
    const filename = path.join(target, file.name);
    return file.before ? io.existsSync(filename) && io.readFileSync(filename).equals(file.before) : !io.existsSync(filename);
  };
  try {
    for (const file of changes) {
      file.temporary = path.join(target, `.issuer-binding-${crypto.randomBytes(8).toString('hex')}.tmp`);
      staged.push(file.temporary);
      io.writeFileSync(file.temporary, file.bytes, { flag: 'wx' });
    }
    if (hash(io.readFileSync(issuerPath)) !== hash(before)) throw new Error('issuer-source-changed-before-install');
    for (const file of changes) {
      if (!matchesBefore(file)) throw new Error(`program-file-changed-before-install: ${file.name}`);
      io.renameSync(file.temporary, path.join(target, file.name));
      installed.push(file);
    }
  } catch (error) {
    const failures = [];
    for (const file of installed.reverse()) {
      const filename = path.join(target, file.name);
      try {
        if (!io.readFileSync(filename).equals(file.bytes)) throw new Error('concurrent-program-edit');
        if (file.before) {
          const temporary = path.join(target, `.issuer-binding-${crypto.randomBytes(8).toString('hex')}.tmp`);
          staged.push(temporary);
          io.writeFileSync(temporary, file.before, { flag: 'wx' });
          io.renameSync(temporary, filename);
        } else { io.unlinkSync(filename); }
      } catch { failures.push(file.name); }
    }
    if (failures.length) throw new Error(`${error.message}; rollback-incomplete: ${failures.join(', ')}; backup: ${backup}`);
    throw error;
  } finally {
    for (const temporary of staged) if (io.existsSync(temporary)) io.unlinkSync(temporary);
  }
  return result;
}

module.exports = { patchIssuerSource, install };
if (require.main === module) {
  try {
    const args = process.argv.slice(2);
    if (args.length !== 4 || args[0] !== '--issuer-dir' || args[2] !== '--expected-sha256') {
      throw new Error('usage: node install-supporter-binding-integration.cjs --issuer-dir DIR --expected-sha256 HASH');
    }
    console.log(JSON.stringify(install(args[1], args[3]), null, 2));
  } catch (error) { console.error(error.message); process.exitCode = 1; }
}
