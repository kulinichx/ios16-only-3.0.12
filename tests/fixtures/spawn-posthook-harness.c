#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <signal.h>
#include <sys/types.h>
#include <mach/machine.h>
#include <xpc/xpc.h>
#define NBINPREFS 4
#define POSIX_SPAWN_PROC_TYPE_DRIVER 0x700
#define POSIX_SPAWN_START_SUSPENDED 0x80
#define POSIX_SPAWN_SETEXEC 0x40
typedef void *posix_spawnattr_t;
struct _posix_spawn_args_desc { posix_spawnattr_t attrp; void *file_actions; };
typedef unsigned kSpawnConfig;
enum { kSpawnConfigTrust=2 };
static int spawnResult, initError;
static unsigned patched, publicSpawns;
static short savedFlags;
static bool jbclient_dyld_patch_enabled(void) { return true; }
static int __no_need_to_trust_now__(const char *path) { (void)path; return 0; }
static kSpawnConfig roothide_spawn_config_for_executable(const char *path,char *const args[]) { (void)path; (void)args; return 0; }
static int posix_spawnattr_getarchpref_np(posix_spawnattr_t *a,size_t count,cpu_type_t *types,cpu_subtype_t *subtypes,size_t *out) {
    (void)a;(void)count;(void)types;(void)subtypes; *out=0; return 0;
}
static void jbclient_trust_executable_recurse(const char *path,xpc_object_t archs) { (void)path;(void)archs; }
static int posix_spawnattr_getflags(posix_spawnattr_t *a,short *flags) { (void)a; *flags=savedFlags; return 0; }
static int posix_spawnattr_setflags(posix_spawnattr_t *a,short flags) { (void)a; savedFlags=flags; errno=EBUSY; return 0; }
static int posix_spawnattr_getprocesstype_np(posix_spawnattr_t *a,int *type) { (void)a; *type=0; return 0; }
static int posix_spawnattr_init(posix_spawnattr_t *a) { if(!initError)*a=(void *)1; return initError; }
static int posix_spawnattr_destroy(posix_spawnattr_t *a) { (void)a; errno=ERANGE; return 0; }
static int posix_spawn(pid_t *pid,const char *path,void *actions,posix_spawnattr_t *attr,char *const args[],char *const env[]) {
    (void)pid;(void)path;(void)actions;(void)attr;(void)args;(void)env; publicSpawns++; errno=ENOEXEC; return ENOEXEC;
}
static int __posix_spawn_inline(pid_t *pid,const char *path,struct _posix_spawn_args_desc *desc,char *const args[],char *const env[]) {
    (void)path;(void)desc;(void)args;(void)env; if(spawnResult==0 && pid)*pid=123; errno=ENOTTY; return spawnResult;
}
static int posix_spawn_hook_shared(pid_t *pid,const char *path,struct _posix_spawn_args_desc *desc,char *const args[],char *const env[],void *orig,
    int (*trust)(const char *),int (*debug)(uint64_t,bool),double multiplier) {
    (void)pid;(void)path;(void)desc;(void)args;(void)env;(void)orig;(void)trust;(void)debug;(void)multiplier; return 0;
}
static int jbdSpawnExecStart(const char *path,bool resume) { (void)path;(void)resume; return 0; }
static void jbdSpawnExecCancel(const char *path) { (void)path; errno=EIO; }
static int jbdSpawnPatchChild(pid_t pid,bool resume) { assert(pid==123 && resume); patched++; errno=EIO; return 0; }
static void trust_insert_libraries(char **env) { (void)env; }
/* PRODUCTION_ENVBUF */
/* PRODUCTION_POSTHOOK */
int main(void) {
    struct _posix_spawn_args_desc desc={.attrp=(void *)1};
    char *env[]={NULL};
    for(unsigned fail=0;fail<2;fail++) {
        spawnResult=fail ? -1 : 0; patched=0; savedFlags=0;
        pid_t pid=999;
        assert(roothide_systemhook___posix_spawn_posthook(&pid,"/test/bin",&desc,NULL,env)==spawnResult);
        assert(errno==ENOTTY && savedFlags==0 && patched==(fail ? 0u : 1u));
    }
    initError=ENOMEM;
    assert(roothide_systemhook___posix_spawn_prehook(NULL,"/test/bin",NULL,NULL,env,NULL,NULL,NULL,0)==ENOMEM && publicSpawns==0);
    initError=0;
    assert(roothide_systemhook___posix_spawn_prehook(NULL,"/test/bin",NULL,NULL,env,NULL,NULL,NULL,0)==ENOEXEC);
    assert(errno==ENOEXEC && publicSpawns==1);
    puts("PASS production spawn pre/post hooks stop failed initialization and preserve syscall errno through child RPC and cleanup");
}
