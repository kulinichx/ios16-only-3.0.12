const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { execFileSync } = require('node:child_process');
const test = require('node:test');

const root = path.resolve(__dirname, '..');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
const main = read('BaseBin/systemhook/src/main.c');
const start = main.indexOf('bool should_enable_tweaks(void)');
const end = main.indexOf('\nint __posix_spawn_hook(', start);
assert.ok(start >= 0 && end > start);
const policy = main.slice(start, end);

function runC(source, expected) {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'rh-approved-backports-'));
  try {
    const file = path.join(directory, 'test.c');
    const binary = path.join(directory, 'test');
    fs.writeFileSync(file, source);
    execFileSync('cc', ['-std=c11', '-Wall', '-Wextra', '-Werror', file, '-o', binary]);
    assert.match(execFileSync(binary, { encoding: 'utf8' }), expected);
  } finally {
    fs.rmSync(directory, { recursive: true, force: true });
  }
}

test('approved logd_helper exclusion keeps the existing initialization and precise tweak gate', () => {
  const disabled = policy.match(/const char \*iOS16TweaksDisabledPaths\[\] = \{([\s\S]*?)\};/);
  assert.ok(disabled);
  assert.deepEqual([...disabled[1].matchAll(/"([^"]+)"/g)].map(match => match[1]), [
    '/usr/libexec/logd', '/usr/libexec/logd_helper', '/usr/sbin/notifyd', '/usr/libexec/usermanagerd',
  ]);
  assert.match(policy, /!strcmp\(gExecutablePath, iOS16TweaksDisabledPaths\[i\]\)\) return false;/);
  assert.ok(main.indexOf('roothide_init_with_executable(gExecutablePath);') < main.indexOf('if (should_enable_tweaks())'));
  assert.equal((main.match(/"\/usr\/libexec\/logd_helper"/g) || []).length, 1);
  assert.doesNotMatch(read('BaseBin/systemhook/src/common/common.c'), /"\/usr\/libexec\/logd_helper"/);
});

test('approved tweak policy executes exact exclusions and preserves ordinary apps and safe mode', {
  skip: process.platform === 'win32' ? 'Requires a C compiler on Linux/macOS; runs in cloud CI.' : false,
}, () => runC(`
#include <assert.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>
#define F_OK 0
#define JBROOT_PATH(path) path
static const char *gExecutablePath;
static bool safeModeFile, dopamineApp;
static const char *disableTweaks, *safeMode, *msSafeMode;
static int mock_access(const char *file, int mode) {
    assert(strcmp(file, "/basebin/.safe_mode") == 0 && mode == F_OK);
    return safeModeFile ? 0 : -1;
}
static char *mock_getenv(const char *name) {
    if (!strcmp(name, "DISABLE_TWEAKS")) return (char *)disableTweaks;
    if (!strcmp(name, "_SafeMode")) return (char *)safeMode;
    assert(!strcmp(name, "_MSSafeMode"));
    return (char *)msSafeMode;
}
static bool jbclient_dopamine_is_jailbroken(void *out) { assert(out == NULL); return dopamineApp; }
static bool string_has_suffix(const char *string, const char *suffix) {
    size_t n = strlen(string), m = strlen(suffix);
    return n >= m && !strcmp(string + n - m, suffix);
}
#define access mock_access
#define getenv mock_getenv
${policy}
int main(void) {
    const char *disabled[] = {
        "/usr/libexec/logd", "/usr/libexec/logd_helper", "/usr/sbin/notifyd", "/usr/libexec/usermanagerd",
        "/usr/libexec/xpcproxy", "/private/root/usr/libexec/xpcproxy"
    };
    for (size_t i = 0; i < sizeof(disabled) / sizeof(disabled[0]); i++) {
        gExecutablePath = disabled[i]; assert(!should_enable_tweaks());
    }
    const char *allowed[] = {
        "/Applications/Example.app/Example", "/usr/bin/example", "/usr/libexec/logd_helper_extra",
        "/opt/bin/logd_helper", "/usr/libexec/logd_helper/child"
    };
    for (size_t i = 0; i < sizeof(allowed) / sizeof(allowed[0]); i++) {
        gExecutablePath = allowed[i]; assert(should_enable_tweaks());
        safeModeFile = true; assert(!should_enable_tweaks()); safeModeFile = false;
        dopamineApp = true; assert(!should_enable_tweaks()); dopamineApp = false;
        disableTweaks = "1"; assert(!should_enable_tweaks()); disableTweaks = NULL;
        safeMode = "1"; assert(!should_enable_tweaks()); safeMode = NULL;
        msSafeMode = "1"; assert(!should_enable_tweaks()); msSafeMode = NULL;
        disableTweaks = safeMode = msSafeMode = "0"; assert(should_enable_tweaks());
        disableTweaks = safeMode = msSafeMode = NULL;
    }
    puts("PASS approved tweak policy");
    return 0;
}
`, /PASS approved tweak policy/));

const common = read('BaseBin/systemhook/src/common/common.c');
const spawnStart = common.indexOf('static int spawn_exec_hook_common(');
const spawnEnd = common.indexOf('\nint posix_spawn_hook_shared(', spawnStart);
assert.ok(spawnStart >= 0 && spawnEnd > spawnStart);
const spawn = common.slice(spawnStart, spawnEnd);

test('approved spawn backport restores only memory fields and preserves the ZQBB MB policy', () => {
  for (const [kind, saved] of [['active', 'Active'], ['inactive', 'Inactive']]) {
    assert.ok(spawn.includes('memlimit' + saved + 'Orig = memlimit_' + kind + ';'));
    const restore = spawn.indexOf('if (memlimit' + saved + 'Orig != -1)');
    assert.ok(restore > spawn.lastIndexOf('orig(&childPid,'));
    assert.ok(restore > spawn.indexOf('envbuf_free(envc);'));
    assert.ok(restore < spawn.lastIndexOf('return r;'));
  }
  assert.match(spawn, /zqbb_getJetsamAddend\(path\) \+ round\(jetsamMultiplier \* 10\)/);
  assert.match(spawn, /memlimit_active \+ jetsamAddend/);
  assert.match(spawn, /memlimit_inactive \+ jetsamAddend/);
  assert.doesNotMatch(spawn, /personaModified|flagsModified|personaOrig|memlimit_\w+ \* jetsamMultiplier/);
});

test('production spawn function passes temporary child limits and restores caller bytes across reuse and failure', {
  skip: process.platform !== 'darwin' ? 'Requires macOS clang/Blocks; runs in the native build job.' : false,
}, t => {
  const componentsStart = common.indexOf('void string_enumerate_components(');
  const componentsEnd = common.indexOf('\nint timespec_compare(', componentsStart);
  assert.ok(componentsStart >= 0 && componentsEnd > componentsStart);
  const offsets = read('BaseBin/systemhook/src/common/private.h')
    .match(/^#define POSIX_SPAWNATTR_OFF_MEMLIMIT_(?:ACTIVE|INACTIVE) .+$/gm).join('\n');
  const fixture = read('tests/fixtures/approved-spawn-memlimit-harness.c')
    .replace('/* PRODUCTION_OFFSETS */', () => offsets)
    .replace('/* PRODUCTION_ENVBUF */', () => read('BaseBin/systemhook/src/common/envbuf.c'))
    .replace('/* PRODUCTION_COMPONENTS */', () => common.slice(componentsStart, componentsEnd))
    .replace('/* PRODUCTION_SPAWN */', () => spawn);
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'rh-spawn-memlimit-'));
  try {
    const source = path.join(directory, 'test.c');
    const binary = path.join(directory, 'test');
    fs.writeFileSync(source, fixture);
    execFileSync('xcrun', ['clang', '-std=c11', '-fblocks', '-Wall', '-Wextra', '-Werror',
      '-Wno-unused-parameter', '-fsanitize=address,undefined', source, '-o', binary]);
    const output = execFileSync(binary, { encoding: 'utf8' });
    assert.match(output, /PASS approved spawn memlimit: 8640 calls/);
    t.diagnostic(output.trim());
  } finally {
    fs.rmSync(directory, { recursive: true, force: true });
  }
});

const springboard = read('BaseBin/roothidehooks/src/springboard.x');
function snapshotMethod(signature) {
  const begin = springboard.indexOf(signature);
  const finish = springboard.indexOf('\n%end', begin);
  assert.ok(begin >= 0 && finish > begin);
  return springboard.slice(begin, finish);
}

test('approved snapshot backport targets the loaded RootHide hook and preserves service wiring', () => {
  assert.doesNotMatch(springboard, /%hookf\(int, fcntl/);
  assert.match(springboard, /%hook XBApplicationSnapshotManifestImpl/);
  assert.match(springboard, /path\.stringByStandardizingPath hasPrefix:snapshotRoot/);
  assert.match(springboard, /stringByAppendingString:@"\/"/);
  assert.match(springboard, /is_apple_internal_identifier\(bundleIdentifier\.UTF8String\)/);
  assert.match(springboard, /rcScheduleServicesStartAfterLaunch\(\);/);
  assert.match(main, /dlopen\(JBROOT_PATH\("\/basebin\/roothidehooks\.dylib"\), RTLD_NOW\)/);
});

test('production snapshot methods preserve routing and write only within the test RootHide directory', {
  skip: process.platform !== 'darwin' ? 'Requires macOS Foundation; private SpringBoard objects are test doubles.' : false,
}, t => {
  const fixture = read('tests/fixtures/approved-snapshot-harness.m')
    .replace('/* PRODUCTION_CONTAINER_PATH */', () =>
      snapshotMethod('-(NSString *)snapshotContainerPath').replaceAll('%orig', 'self.originalPath'))
    .replace('/* PRODUCTION_SAVE */', () =>
      snapshotMethod('- (BOOL)_imageAccessQueue_saveData:')
        .replaceAll('%orig', '[self originalSaveData:data forSnapshot:snapshot]'));
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'rh-snapshot-'));
  try {
    const source = path.join(directory, 'test.m');
    const binary = path.join(directory, 'test');
    fs.writeFileSync(source, fixture);
    execFileSync('xcrun', ['clang', '-fobjc-arc', '-Wall', '-Wextra', '-Werror',
      '-Wno-incompatible-pointer-types', '-fsanitize=address,undefined',
      '-framework', 'Foundation', source, '-o', binary]);
    const output = execFileSync(binary, { encoding: 'utf8' });
    assert.match(output, /PASS approved snapshot routing/);
    t.diagnostic(output.trim());
  } finally {
    fs.rmSync(directory, { recursive: true, force: true });
  }
});
