const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { execFileSync } = require('node:child_process');
const test = require('node:test');
const root = path.resolve(__dirname, '..');
const read = file => fs.readFileSync(path.join(root, file), 'utf8').replace(/\r\n/g, '\n');
const digest = text => crypto.createHash('sha256').update(text.replace(/[\t ]+$/gm, '')).digest('hex');
const source = read('BaseBin/libjailbreak/src/util.c');
const signature = /void killall\(const char \*executablePath, int signal\)\n\{[\s\S]*?\n\}/;
const production = source.match(signature)?.[0];
const original = read('tests/fixtures/zqbb-killall-original.c').trimEnd();

test('killall is the approved ZQBB function and the rest of util.c retains its baseline', () => {
  assert.ok(production);
  assert.equal(digest(production), '7e26acb7194254546ffd646f6ce1654c594ba73f68e30cd0698104e9874e76ff');
  const manifest = JSON.parse(read('tests/fixtures/zqbb-ios16-baseline.json'));
  const base = manifest.files.find(entry => entry.file === 'BaseBin/libjailbreak/src/util.c');
  const approved = manifest.approvedBackports.find(entry => entry.id === 'zqbb-killall-bounds');
  assert.equal(approved.sourceRepository, 'w2599/Dopamine');
  assert.equal(approved.sourceCommit, '04c18e40ef2a04f666a705d9c0361515f1afc318');
  const restored = source.replace('// 按参数容量读取进程路径，避免进程列表长度与参数长度混用。\n', '')
    .replace(production, () => original);
  assert.equal(digest(restored), base.sha256);
  assert.match(read('BaseBin/libjailbreak/src/util.h'), /void killall\(const char \*executablePath, int signal\);/);
  for (const file of ['BaseBin/jbctl/src/main.m', 'BaseBin/launchdhook/src/main.m']) {
    assert.ok(read(file).includes('killall("/usr/libexec/backboardd", SIGTERM);'));
  }
  assert.ok(read('BaseBin/launchdhook/src/jbserver/jbdomain_systemwide.c')
    .includes('killall("/System/Library/TextInput/kbd", SIGKILL);'));
});

test('production killall passes native boundary tests and the old function fails the capacity control', {
  skip: process.platform === 'win32' ? 'Requires the Linux/macOS C compiler; runs in cloud CI.' : false,
}, t => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'rh-approved-killall-'));
  const fixture = read('tests/fixtures/approved-killall-harness.c');
  try {
    function compile(name, body) {
      const file = path.join(directory, `${name}.c`);
      const binary = path.join(directory, name);
      fs.writeFileSync(file, fixture.replace('/* PRODUCTION_KILLALL */', () => body));
      execFileSync('cc', ['-std=c11', '-Wall', '-Wextra', '-Werror', '-fsanitize=address,undefined',
        '-fno-omit-frame-pointer', file, '-o', binary], { stdio: 'pipe' });
      return binary;
    }
    const binary = compile('approved', production);
    const output = execFileSync(binary, { encoding: 'utf8', stdio: 'pipe' });
    assert.match(output, /PASS approved killall: 13 scenarios/);
    t.diagnostic(output.trim());
    const baseline = compile('baseline', original);
    assert.throws(() => execFileSync(baseline, { stdio: 'pipe' }), error => {
      assert.ok(error.status !== 0 || error.signal);
      assert.match(String(error.stderr), /available/);
      return true;
    });
    t.diagnostic('PASS negative control: original ZQBB allocation/capacity mismatch rejected before mock write');
  } finally {
    fs.rmSync(directory, { recursive: true, force: true });
  }
});
