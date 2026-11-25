#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <limits.h>
#include <math.h>
#include <sys/param.h>
#define HOOK_DYLIB_PATH "/test/systemhook.dylib"
#define POSIX_SPAWN_PROC_TYPE_DRIVER 0x700
#define POSIX_SPAWN_START_SUSPENDED 0x80
typedef void *posix_spawnattr_t;
struct _posix_spawn_args_desc { posix_spawnattr_t attrp; };
typedef enum { kSpawnConfigInject=1, kSpawnConfigTrust=2 } kSpawnConfig;
static kSpawnConfig spawn_config_for_executable(const char *path, char *const argv[]) { (void)path; (void)argv; return 3; }
static bool allowInjectWithSafeMode(const char *path) { (void)path; return false; }
static int zqbb_getJetsamAddend(const char *path) { (void)path; return 10; }
static int mock_access(const char *path, int flags) { (void)path; (void)flags; return 0; }
static int posix_spawnattr_getprocesstype_np(posix_spawnattr_t *attr, int *type) { (void)attr; *type=0; return 0; }
static int posix_spawnattr_getflags(posix_spawnattr_t *attr, short *flags) { (void)attr; *flags=POSIX_SPAWN_START_SUSPENDED; errno=ERANGE; return 0; }
/* PRODUCTION_ENVBUF */
static void cleanup_with_errno(char **env) { envbuf_free(env); errno=EBUSY; }
#define access mock_access
#define envbuf_free cleanup_with_errno
/* PRODUCTION_SPAWN */
#undef envbuf_free
#undef access
static int spawnResult, spawnErrno;
static unsigned debugCalls;
static int trust(const char *path) { (void)path; errno=ENOENT; return 0; }
static int debug(uint64_t pid, bool fully) { assert(pid==123 && !fully); debugCalls++; errno=EIO; return 0; }
static int original(pid_t *pid, const char *path, struct _posix_spawn_args_desc *desc, char *const argv[], char *const env[]) {
    (void)path; (void)desc; (void)argv;
    assert(envbuf_getenv((const char **)env,"DYLD_INSERT_LIBRARIES"));
    if (spawnResult==0 && pid) *pid=123;
    errno=spawnErrno; return spawnResult;
}
int main(void) {
    union { int align; uint8_t bytes[256]; } storage={0};
    *(int *)(storage.bytes+POSIX_SPAWNATTR_OFF_MEMLIMIT_ACTIVE)=100;
    *(int *)(storage.bytes+POSIX_SPAWNATTR_OFF_MEMLIMIT_INACTIVE)=200;
    struct _posix_spawn_args_desc desc={.attrp=storage.bytes};
    char *empty[]={NULL}, *inserted[]={"DYLD_INSERT_LIBRARIES=" HOOK_DYLIB_PATH,NULL};
    for (unsigned changed=0; changed<2; changed++) for (unsigned failed=0; failed<2; failed++) {
        spawnResult=failed ? -1 : 0; spawnErrno=failed ? ENOEXEC : ENOTTY; debugCalls=0;
        pid_t pid=-1;
        assert(posix_spawn_hook_shared(&pid,"/test/bin",&desc,NULL,changed ? empty : inserted,
            (void *)original,trust,debug,3)==spawnResult);
        assert(errno==spawnErrno && debugCalls==(failed ? 0u : 1u));
        assert(*(int *)(storage.bytes+POSIX_SPAWNATTR_OFF_MEMLIMIT_ACTIVE)==100);
        assert(*(int *)(storage.bytes+POSIX_SPAWNATTR_OFF_MEMLIMIT_INACTIVE)==200);
    }
    puts("PASS actual spawn functions preserve result/errno through environment cleanup, attribute restoration and debug RPC");
}
