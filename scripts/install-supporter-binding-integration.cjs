'use strict';

const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');

const hash = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const marker = '# RootHide binding integration v1';
const hook = `${marker}
. (Join-Path $script:BaseDir 'SupporterBindingIntegration.ps1')
Initialize-RHBindingIntegration @{
    Directory = $script:BaseDir; Form = $form; Panel = $licensePanel
    Grid = $grid; Output = $txtLicense; Status = $status
    VerifyProofButton = $btnVerifyProof; RH1IssueButton = $btnIssue
}
`;

function patchIssuerSource(source) {
  const newline = source.includes('\r\n') ? '\r\n' : '\n';
  const normalized = source.replace(/\r\n/g, '\n');
  if (normalized.includes(marker)) {
    if (!normalized.includes(hook)) throw new Error('existing-integration-hook-differs');
    return source;
  }
  const finalDialog = '[void]$form.ShowDialog()';
  if (normalized.split(finalDialog).length !== 2 || !normalized.trimEnd().endsWith(finalDialog)) {
    throw new Error('unsupported-issuer-startup-layout');
  }
  for (const anchor of ['function Refresh-Grid', '$script:BaseDir', '$licensePanel =', '$grid =',
    '$txtLicense =', '$status =', '$btnVerifyProof =', '$btnIssue =']) {
    if (!normalized.includes(anchor)) throw new Error(`missing-issuer-anchor: ${anchor}`);
  }
  return normalized.replace(finalDialog, `${hook}\n${finalDialog}`).replace(/\n/g, newline);
}

function install(directory, expectedHash, io = fs) {
  if (!/^[a-f0-9]{64}$/i.test(expectedHash || '')) throw new Error('expected-source-sha256-required');
  const target = path.resolve(directory);
  const issuerPath = path.join(target, 'RootHideSupporterIssuer.ps1');
  const before = io.readFileSync(issuerPath);
  if (hash(before) !== expectedHash.toLowerCase()) throw new Error('issuer-source-changed');
  const modified = Buffer.from(patchIssuerSource(before.toString('utf8')), 'utf8');
  const files = ['SupporterBindingIntegration.ps1', 'supporter-binding.cjs'].map(name => ({
    name, bytes: io.readFileSync(path.join(__dirname, name)),
  }));
  for (const file of files) {
    const filename = path.join(target, file.name);
    if (io.existsSync(filename) && !io.readFileSync(filename).equals(file.bytes)) {
      throw new Error(`existing-program-file-differs: ${file.name}`);
    }
  }
  if (before.equals(modified) && files.every(file => io.existsSync(path.join(target, file.name)))) {
    return { changed: false, issuerSha256: hash(before) };
  }
  const backup = path.join(target, 'program-backups', `binding-${new Date().toISOString().replace(/[:.]/g, '-')}-${crypto.randomBytes(4).toString('hex')}`);
  io.mkdirSync(backup, { recursive: true });
  io.writeFileSync(path.join(backup, 'RootHideSupporterIssuer.ps1'), before, { flag: 'wx' });
  const result = { changed: true, backup, issuerSha256: hash(modified),
    sourceSha256: hash(before), programFiles: files.map(file => ({ name: file.name, sha256: hash(file.bytes) })) };
  io.writeFileSync(path.join(backup, 'installation.json'), JSON.stringify(result, null, 2) + '\n', { flag: 'wx' });
  // The installer reads/copies program files only, never databases or a private key.
  const created = [];
  const temporary = path.join(target, `.issuer-binding-${crypto.randomBytes(8).toString('hex')}.tmp`);
  try {
    for (const file of files) {
      const filename = path.join(target, file.name);
      if (!io.existsSync(filename)) {
        io.writeFileSync(filename, file.bytes, { flag: 'wx' });
        created.push(filename);
      }
    }
    io.writeFileSync(temporary, modified, { flag: 'wx' });
    if (hash(io.readFileSync(issuerPath)) !== hash(before)) throw new Error('issuer-source-changed-before-install');
    io.renameSync(temporary, issuerPath);
  } catch (error) {
    if (io.existsSync(temporary)) io.unlinkSync(temporary);
    for (const filename of created) io.unlinkSync(filename);
    throw error;
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
