#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <signal.h>
#include <unistd.h>
#include <sys/types.h>
#include <mach/machine.h>
#include <xpc/xpc.h>
#define NBINPREFS 4
#define POSIX_SPAWN_PROC_TYPE_DRIVER 0x700
#define POSIX_SPAWN_START_SUSPENDED 0x80
#define POSIX_SPAWN_SETEXEC 0x40
#undef assert
#define assert(...) do { if (!(__VA_ARGS__)) { fprintf(stderr, "fixture regression: shared-region line %d\n", __LINE__); _Exit(86); } } while (0)
typedef void *posix_spawnattr_t;
struct _posix_spawn_args_desc { posix_spawnattr_t attrp; void *file_actions; };
typedef unsigned kSpawnConfig;
enum { kSpawnConfigTrust=2 };
static int spawnResult, initError;
static unsigned patched, publicSpawns;
static short savedFlags;
static bool dyldPatchEnabled = true;
static char observedCache[32], observedRegion[32], observedInjection[128];
static bool sawCache, sawRegion, sawInjection;
static unsigned traceStarts, traceCancels;
static void capture_environment(char *const env[]);
static bool jbclient_dyld_patch_enabled(void) { return dyldPatchEnabled; }
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
    (void)path;(void)desc;(void)args; capture_environment(env); if(spawnResult==0 && pid)*pid=123; errno=ENOTTY; return spawnResult;
}
static int posix_spawn_hook_shared(pid_t *pid,const char *path,struct _posix_spawn_args_desc *desc,char *const args[],char *const env[],void *orig,
    int (*trust)(const char *),int (*debug)(uint64_t,bool),double multiplier) {
    (void)pid;(void)path;(void)desc;(void)args;(void)env;(void)orig;(void)trust;(void)debug;(void)multiplier; return 0;
}
static int jbdSpawnExecStart(const char *path,bool resume) { (void)path;(void)resume; return 0; }
static void jbdSpawnExecCancel(const char *path) { (void)path; errno=EIO; }
static int jbdSpawnPatchChild(pid_t pid,bool resume) { assert(pid==123 && resume); patched++; errno=EIO; return 0; }
static int jbdExecTraceStart(const char *path, bool *traced) { (void)path; traceStarts++; *traced=true; return 0; }
static int jbdExecTraceCancel(const char *path, bool *detached) { (void)path; traceCancels++; *detached=true; errno=EIO; return 0; }
static int __execve_inline(const char *path, char *const args[], char *const env[]) {
    (void)path; (void)args; capture_environment(env); errno=ENOEXEC; return -1;
}
static void trust_insert_libraries(char **env) { (void)env; }
/* PRODUCTION_ENVBUF */
static void capture_environment(char *const env[]) {
    const char *cache=envbuf_getenv((const char **)env, "DYLD_IN_CACHE");
    const char *region=envbuf_getenv((const char **)env, "DYLD_SHARED_REGION");
    const char *injection=envbuf_getenv((const char **)env, "DYLD_INSERT_LIBRARIES");
    sawCache=cache!=NULL; sawRegion=region!=NULL; sawInjection=injection!=NULL;
    snprintf(observedCache,sizeof(observedCache),"%s",cache ?: "");
    snprintf(observedRegion,sizeof(observedRegion),"%s",region ?: "");
    snprintf(observedInjection,sizeof(observedInjection),"%s",injection ?: "");
    assert(strcmp(envbuf_getenv((const char **)env,"KEEP"),"untouched")==0);
}
/* PRODUCTION_POSTHOOK */
/* PRODUCTION_LAUNCHD_ATTRIBUTE_SETUP */

static char **NXArgv;
static int NXArgc, roothider_inline_version;
static bool dyld_patch_fallback_enabled;
static const char *HOOK_DYLIB_PATH;
extern void *__dso_handle;
#define jbdSystemwideLog(...) ((void)0)
static void dopamine_fixsugids(char **argv, int argc) { (void)argv; (void)argc; }
static int parse_dyldhook_jbinfo(void *a, void *b, void *c, void *d) { (void)a; (void)b; (void)c; (void)d; return 0; }
static void resolve_dyld_symbol_callback(void) {}
static const void *get_dyld_mach_header(void) { return NULL; }
static void roothider_inline_init_dyld_symbols(void (*callback)(void), void *header) { (void)callback; (void)header; }
static const char *dyld_image_path_containing_address(const void *address) { (void)address; return "/fixture/systemhook.dylib"; }
/* PRODUCTION_INITIALIZATION */
#define JBROOT_PATH(path) (path)
static void app_environment(void) {
/* PRODUCTION_APP_ENVIRONMENT */
}
static void check_value(const char *name, const char *expected) {
    const char *value=getenv(name);
    assert(expected ? value && strcmp(value,expected)==0 : value==NULL);
}
static void environment_matrix(void) {
    const char *regions[]={NULL,"use","private","avoid","other"};
    const char *caches[]={NULL,"0","1"};
    const char *injections[]={NULL,"","/fixture/systemhook.dylib"};
    struct _posix_spawn_args_desc desc={.attrp=(void *)1};
    unsigned cases=0;
    for(unsigned patch=0;patch<2;patch++)
    for(unsigned injected=0;injected<3;injected++)
    for(unsigned region=0;region<5;region++)
    for(unsigned cache=0;cache<3;cache++) {
        char regionEntry[64],cacheEntry[64],injectionEntry[160];
        char *env[5]={"KEEP=untouched",NULL};
        unsigned count=1;
        if(regions[region]) { snprintf(regionEntry,sizeof(regionEntry),"DYLD_SHARED_REGION=%s",regions[region]); env[count++]=regionEntry; }
        if(caches[cache]) { snprintf(cacheEntry,sizeof(cacheEntry),"DYLD_IN_CACHE=%s",caches[cache]); env[count++]=cacheEntry; }
        if(injections[injected]) { snprintf(injectionEntry,sizeof(injectionEntry),"DYLD_INSERT_LIBRARIES=%s",injections[injected]); env[count++]=injectionEntry; }
        env[count]=NULL;
        char **before=envbuf_mutcopy((const char **)env);
        dyldPatchEnabled=patch;
        for(unsigned route=0;route<3;route++) {
            spawnResult=route==1 ? -1 : 0; savedFlags=0;
            if(route<2) {
                pid_t pid=999;
                assert(roothide_systemhook___posix_spawn_posthook(&pid,"/fixture/bin",&desc,NULL,env)==spawnResult);
                assert(errno==ENOTTY && savedFlags==0);
            } else {
                unsigned starts=traceStarts,cancels=traceCancels;
                assert(roothide_systemhook___execve_posthook("/fixture/bin",NULL,env)==-1 && errno==ENOEXEC);
                assert(traceStarts==starts+1 && traceCancels==cancels+1);
            }
            assert(sawInjection==(injections[injected]!=NULL));
            assert(strcmp(observedInjection,injections[injected] ?: "")==0);
            assert(sawRegion==((injections[injected] ?: regions[region])!=NULL));
            assert(strcmp(observedRegion,injections[injected] ? "use" : (regions[region] ?: ""))==0);
            assert(sawCache==((injections[injected] ?: caches[cache])!=NULL));
            assert(strcmp(observedCache,injections[injected] ? "0" : (caches[cache] ?: ""))==0);
            for(unsigned i=0;i<count;i++) assert(strcmp(env[i],before[i])==0);
            assert(env[count]==NULL);
            cases++;
        }
        envbuf_free(before);
    }
    assert(cases==270);
}
static void initialization_matrix(void) {
    const char *regions[]={NULL,"use","private","avoid","other"};
    const char *caches[]={NULL,"0","1"};
    const char *injections[]={NULL,"","/fixture/systemhook.dylib"};
    for(unsigned injected=0;injected<3;injected++)
    for(unsigned region=0;region<5;region++)
    for(unsigned cache=0;cache<3;cache++) {
        if(injections[injected]) setenv("DYLD_INSERT_LIBRARIES",injections[injected],1); else unsetenv("DYLD_INSERT_LIBRARIES");
        if(regions[region]) setenv("DYLD_SHARED_REGION",regions[region],1); else unsetenv("DYLD_SHARED_REGION");
        if(caches[cache]) setenv("DYLD_IN_CACHE",caches[cache],1); else unsetenv("DYLD_IN_CACHE");
        setenv("KEEP","untouched",1);
        roothide_init();
        free((void *)HOOK_DYLIB_PATH);
        check_value("DYLD_INSERT_LIBRARIES",injections[injected]);
        check_value("DYLD_SHARED_REGION",injected && region==1 ? NULL : regions[region]);
        check_value("DYLD_IN_CACHE",injected && cache==1 ? NULL : caches[cache]);
        check_value("KEEP","untouched");
        assert(roothider_inline_version==16 && !dyld_patch_fallback_enabled);
    }
    for(unsigned region=0;region<5;region++) {
        if(regions[region]) setenv("DYLD_SHARED_REGION",regions[region],1); else unsetenv("DYLD_SHARED_REGION");
        app_environment();
        check_value("DYLD_SHARED_REGION","use");
        check_value("DYLD_IN_CACHE","0");
        check_value("DISABLE_TWEAKS","1");
        check_value("DYLD_INSERT_LIBRARIES","/basebin/systemhook.dylib");
    }
}
int main(void) {
    struct _posix_spawn_args_desc desc={.attrp=(void *)1};
    char *env[]={"KEEP=untouched",NULL};
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
    publicSpawns=0; initError=ENOMEM;
    assert(roothide_launchd___posix_spawn_prehook(NULL,"/test/bin",NULL,NULL,env)==ENOMEM && publicSpawns==0);
    initError=0;
    assert(roothide_launchd___posix_spawn_prehook(NULL,"/test/bin",NULL,NULL,env)==ENOEXEC);
    assert(errno==ENOEXEC && publicSpawns==1);
    environment_matrix();
    initialization_matrix();
    puts("PASS production ZQBB environment policy: 270 spawn/exec cases, 45 initialization cases, 5 App setup cases and cleanup errno");
}
