#include <assert.h>
#include <errno.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#undef assert
#define assert(...) do { if (!(__VA_ARGS__)) { fprintf(stderr, "fixture regression: exec setup line %d\n", __LINE__); _Exit(86); } } while (0)
typedef void *posix_spawnattr_t;
#define POSIX_SPAWN_SETEXEC 64
#define SANDBOX_CHECK_NO_REPORT 0
#define X_OK 1
static int initError, flagError, spawnError, accessError, sandboxError;
static int initialized, flagsSet, spawned, destroyed, fallback;
static int posix_spawnattr_init(posix_spawnattr_t *attr) {
    initialized++;
    if (initError) return initError;
    *attr = (void *)0x1234;
    return 0;
}
static int posix_spawnattr_setflags(posix_spawnattr_t *attr, short flags) {
    assert(*attr == (void *)0x1234 && flags == POSIX_SPAWN_SETEXEC);
    flagsSet++;
    return flagError;
}
static int posix_spawn(int *pid, const char *path, void *actions, posix_spawnattr_t *attr, char *const argv[], char *const envp[]) {
    (void)pid; (void)path; (void)actions; (void)argv; (void)envp;
    assert(*attr == (void *)0x1234 && !flagError);
    spawned++; errno = EIO;
    return spawnError;
}
static int posix_spawnattr_destroy(posix_spawnattr_t *attr) {
    assert(*attr == (void *)0x1234);
    destroyed++; *attr = NULL; errno = ECHILD;
    return 0;
}
static int access(const char *path, int flags) { (void)path; (void)flags; return accessError; }
static int getpid(void) { return 123; }
static int sandbox_check(int pid, const char *op, int flags, void *filter) {
    (void)pid; (void)op; (void)flags; (void)filter; return sandboxError;
}
static int __no_need_to_trust_now__(const char *path) { (void)path; return 0; }
static int execve_hook_shared(const char *path, char *const argv[], char *const envp[], void *orig, int (*trust)(const char *)) {
    (void)path; (void)argv; (void)envp; (void)orig;
    assert(trust == __no_need_to_trust_now__);
    fallback++; errno = ENOEXEC; return -1;
}
/* PRODUCTION_EXEC_SETUP */
static void reset(void) {
    initError=flagError=accessError=sandboxError=0; spawnError=ENOENT;
    initialized=flagsSet=spawned=destroyed=fallback=0; errno=0;
}
static int run(void) { return roothide_systemhook___execve_prehook("/fixture", NULL, NULL, NULL, NULL); }
int main(void) {
    reset(); initError=ENOMEM;
    assert(run()==-1 && errno==ENOMEM && initialized==1 && !flagsSet && !spawned && !destroyed);
    reset(); flagError=EINVAL;
    assert(run()==-1 && errno==EINVAL && initialized==1 && flagsSet==1 && !spawned && destroyed==1);
    reset();
    assert(run()==-1 && errno==ENOENT && spawned==1 && destroyed==1 && !fallback);
    reset(); spawnError=EPERM;
    assert(run()==-1 && errno==ENOEXEC && fallback==1 && destroyed==1);
    reset(); spawnError=EPERM; sandboxError=1;
    assert(run()==-1 && errno==EPERM && !fallback);
    reset(); spawnError=EPERM; accessError=-1;
    assert(run()==-1 && errno==EPERM && !fallback);
    puts("PASS production exec setup: initialization/flags failure and existing permission fallback");
}
