#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <limits.h>
#include <math.h>
#define min(a, b) ((a) < (b) ? (a) : (b))
#define HOOK_DYLIB_PATH "/test/systemhook.dylib"
#define POSIX_SPAWN_PROC_TYPE_DRIVER 0x700
typedef void *posix_spawnattr_t;
struct _posix_spawn_args_desc { posix_spawnattr_t attrp; };
typedef enum { kSpawnConfigInject = 1, kSpawnConfigTrust = 2 } kSpawnConfig;
static bool configuredInjection, driverProcess, missingHook;
static double configuredAddend;
static kSpawnConfig spawn_config_for_executable(const char *path, char *const argv[]) {
    (void)path; (void)argv;
    return (configuredInjection ? kSpawnConfigInject : 0) | kSpawnConfigTrust;
}
static bool allowInjectWithSafeMode(const char *path) { (void)path; return false; }
static double zqbb_getJetsamAddend(const char *path) { (void)path; return configuredAddend; }
static int mock_access(const char *path, int mode) {
    assert(!strcmp(path, HOOK_DYLIB_PATH) && mode == F_OK);
    return missingHook ? -1 : 0;
}
static int posix_spawnattr_getprocesstype_np(const posix_spawnattr_t *attr, int *type) {
    (void)attr;
    *type = driverProcess ? POSIX_SPAWN_PROC_TYPE_DRIVER : 0;
    return 0;
}
static int trust_binary(const char *path) { assert(!strcmp(path, "/test/app")); return 0; }

/* PRODUCTION_OFFSETS */
/* PRODUCTION_ENVBUF */
/* PRODUCTION_COMPONENTS */
#define access mock_access
/* PRODUCTION_SPAWN */
#undef access

static unsigned invocations, originalEnvCalls, changedEnvCalls;
static int expected_limit(int input, int boost) {
    if (input == -1) return -1;
    int64_t value = (int64_t)input + boost;
    return value > INT_MAX ? INT_MAX : (int)value;
}

int main(void) {
    const struct { int active, inactive; } limits[] = {
        {100, 200}, {-1, 200}, {100, -1}, {-1, -1}, {0, 0}, {INT_MAX - 5, INT_MAX - 7}
    };
    const struct { double multiplier, addend; int boost; } settings[] = {
        {3, 20, 50}, {0, 20, 50}, {NAN, 20, 50}, {INFINITY, 20, 50}, {-INFINITY, 20, 50},
        {1, 20, 0}, {0.5, 20, 0}, {-2, 20, 0}, {2.5, 20, 45}, {3, (double)INT_MAX + 50, INT_MAX}
    };
    for (unsigned l = 0; l < sizeof(limits) / sizeof(limits[0]); l++)
    for (unsigned s = 0; s < sizeof(settings) / sizeof(settings[0]); s++)
    for (unsigned mode = 0; mode < 6; mode++)
    for (unsigned inserted = 0; inserted < 2; inserted++)
    for (unsigned attrMode = 0; attrMode < 3; attrMode++)
    for (unsigned failed = 0; failed < 2; failed++) {
        union { int alignment; uint8_t bytes[256]; } storage;
        memset(storage.bytes, 0xa5, sizeof(storage.bytes));
        memcpy(storage.bytes + POSIX_SPAWNATTR_OFF_MEMLIMIT_ACTIVE, &limits[l].active, sizeof(int));
        memcpy(storage.bytes + POSIX_SPAWNATTR_OFF_MEMLIMIT_INACTIVE, &limits[l].inactive, sizeof(int));
        uint8_t before[sizeof(storage.bytes)];
        memcpy(before, storage.bytes, sizeof(before));
        uint8_t *bytes = storage.bytes;
        struct _posix_spawn_args_desc desc = { .attrp = attrMode == 0 ? bytes : NULL };
        struct _posix_spawn_args_desc *descriptor = attrMode == 2 ? NULL : &desc;
        configuredInjection = mode != 1;
        driverProcess = mode == 4;
        missingHook = mode == 5;
        configuredAddend = settings[s].addend;
        char *env[5];
        unsigned i = 0;
        if (inserted) env[i++] = "DYLD_INSERT_LIBRARIES=" HOOK_DYLIB_PATH;
        if (mode == 2) env[i++] = "_SafeMode=1";
        if (mode == 3) env[i++] = "_MSSafeMode=1";
        env[i++] = "PRESERVE_ME=original";
        env[i] = NULL;
        char *const *originalEnvironment = env;
        bool inject = mode == 0;
        bool direct = mode != 2 && mode != 3 && inject == (bool)inserted;
        int boost = inject ? settings[s].boost : 0;
        int expectedActive = expected_limit(limits[l].active, boost);
        int expectedInactive = expected_limit(limits[l].inactive, boost);
        int result = failed ? 5 : 0;
        __block unsigned callbacks = 0;
        // Reuse exactly the same descriptor and backing storage across calls.
        for (unsigned repeat = 0; repeat < 2; repeat++) {
            int actual = spawn_exec_hook_common(false, "/test/app", NULL, env, descriptor,
                trust_binary, settings[s].multiplier, ^int(pid_t *pid, char *const receivedEnv[]) {
                    assert(pid != NULL);
                    callbacks++;
                    if (attrMode == 0) {
                        assert(*(int *)(bytes + POSIX_SPAWNATTR_OFF_MEMLIMIT_ACTIVE) == expectedActive);
                        assert(*(int *)(bytes + POSIX_SPAWNATTR_OFF_MEMLIMIT_INACTIVE) == expectedInactive);
                    }
                    assert((receivedEnv == originalEnvironment) == direct);
                    if (direct) originalEnvCalls++; else changedEnvCalls++;
                    const char *library = envbuf_getenv((const char **)receivedEnv, "DYLD_INSERT_LIBRARIES");
                    assert(inject ? library && !strcmp(library, HOOK_DYLIB_PATH) : library == NULL);
                    assert(!strcmp(envbuf_getenv((const char **)receivedEnv, "PRESERVE_ME"), "original"));
                    assert(envbuf_getenv((const char **)receivedEnv, "_SafeMode") == NULL);
                    assert(envbuf_getenv((const char **)receivedEnv, "_MSSafeMode") == NULL);
                    return result;
                });
            assert(actual == result);
            assert(memcmp(before, storage.bytes, sizeof(before)) == 0);
            assert(descriptor == NULL || descriptor->attrp == (attrMode == 0 ? bytes : NULL));
            invocations++;
        }
        assert(callbacks == 2);
    }
    assert(invocations == 8640 && originalEnvCalls > 0 && changedEnvCalls > 0);
    printf("PASS approved spawn memlimit: %u calls, both environment branches, child limits and full caller bytes verified\n", invocations);
    return 0;
}
