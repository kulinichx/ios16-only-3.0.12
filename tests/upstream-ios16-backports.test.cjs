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
