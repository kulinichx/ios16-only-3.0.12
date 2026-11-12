'use strict';

const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');

const hash = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const knownPrevious = {
  'SupporterBindingIntegration.ps1': 'd6cab08aa685596f5c8c26fbc2b2cff84d6f3ac708a6efee082931a1cfcabf57',
  'supporter-binding.cjs': 'a78695c9dc1be96c61a469dc89f5960436284cfad939b9fbdeca95e5a19463c9',
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
  const files = ['SupporterBindingIntegration.ps1', 'supporter-binding.cjs', 'supporter-key-review.cjs'].map(name => ({
    name, bytes: io.readFileSync(path.join(__dirname, name)), before: null,
  }));
  for (const file of files) {
    const filename = path.join(target, file.name);
    if (io.existsSync(filename)) {
      file.before = io.readFileSync(filename);
      if (!file.before.equals(file.bytes) && hash(file.before) !== knownPrevious[file.name]) {
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
