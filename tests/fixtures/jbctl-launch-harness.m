#import <Foundation/Foundation.h>
#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <spawn.h>
#include <sys/wait.h>
#include <unistd.h>
extern char **environ;
static const char *selfPath;
#define JBROOT_PATH(path) selfPath
static bool inRoot, inSandbox, skipPrivilege;
static bool failSpawn, failActions, interruptWrite;
static unsigned spawnCalls, waits;
static int cmd_wait_for_exit(pid_t pid) {
    assert(!inRoot && !inSandbox); waits++;
    int status; pid_t waited;
    do { waited=waitpid(pid,&status,0); } while(waited<0 && errno==EINTR);
    return waited==pid && WIFEXITED(status) ? WEXITSTATUS(status) : -1;
}
static int test_spawn(pid_t *pid, const char *path, const posix_spawn_file_actions_t *actions,
    const posix_spawnattr_t *attributes, char *const args[], char *const env[]) {
    assert(inRoot && inSandbox); spawnCalls++;
    if(failSpawn) return EACCES;
    return posix_spawn(pid,path,actions,attributes,args,env);
}
static int test_actions_init(posix_spawn_file_actions_t *actions) {
    return failActions ? ENOMEM : posix_spawn_file_actions_init(actions);
}
static ssize_t test_write(int fd,const void *buffer,size_t length) {
    assert(!inRoot && !inSandbox);
    if(interruptWrite) { interruptWrite=false; errno=EINTR; return -1; }
    return write(fd,buffer,length);
}
@interface DOEnvironmentManager : NSObject
@property(nonatomic,copy) NSString *jailbrokenVersion;
- (void)runAsRoot:(void (^)(void))block;
- (void)runUnsandboxed:(void (^)(void))block;
- (int)spawnJbctlAsRootWithArgs:(NSArray *)args;
@end
@implementation DOEnvironmentManager
- (void)runAsRoot:(void (^)(void))block { if(skipPrivilege)return; inRoot=true; block(); inRoot=false; }
- (void)runUnsandboxed:(void (^)(void))block { inSandbox=true; block(); inSandbox=false; }
#define posix_spawn test_spawn
#define posix_spawn_file_actions_init test_actions_init
#define write test_write
/* PRODUCTION_LAUNCH */
#undef write
#undef posix_spawn_file_actions_init
#undef posix_spawn
@end
static bool interruptRead;
static ssize_t test_read(int fd,void *buffer,size_t length) {
    if(interruptRead) { interruptRead=false; errno=EINTR; return -1; }
    return read(fd,buffer,length);
}
static int wait_for_release(int fd) {
#define read test_read
/* PRODUCTION_WAIT */
#undef read
    return 0;
}
int main(int argc, const char **argv) {
    if(argc==4 && !strcmp(argv[1],"--child")) return wait_for_release(atoi(argv[3]));
    if(argc==2 && !strcmp(argv[1],"--child")) return 0;
    assert(argc==1); selfPath=argv[0];
    @autoreleasepool {
        DOEnvironmentManager *env=[DOEnvironmentManager new]; env.jailbrokenVersion=@"3.0.13";
        interruptWrite=true;
        assert([env spawnJbctlAsRootWithArgs:@[@"--child"]]==0 && spawnCalls==1 && waits==1);
        failSpawn=true;
        assert([env spawnJbctlAsRootWithArgs:@[@"--child"]]==EACCES && waits==1); failSpawn=false;
        failActions=true;
        assert([env spawnJbctlAsRootWithArgs:@[@"--child"]]==ENOMEM && spawnCalls==2); failActions=false;
        skipPrivilege=true;
        assert([env spawnJbctlAsRootWithArgs:@[@"--child"]]==EPERM && waits==1); skipPrivilege=false;
        env.jailbrokenVersion=@"3.0.4";
        assert([env spawnJbctlAsRootWithArgs:@[@"--child"]]==0 && waits==2);
        int fds[2]; assert(pipe(fds)==0); interruptRead=true;
        assert(write(fds[1],"w",1)==1 && wait_for_release(fds[0])==0); close(fds[1]);
        assert(pipe(fds)==0); close(fds[1]); assert(wait_for_release(fds[0])==1);
        assert(pipe(fds)==0); assert(write(fds[1],"x",1)==1 && wait_for_release(fds[0])==1); close(fds[1]);
    }
    puts("PASS production App/jbctl launch with real child, privilege ordering, EINTR, EOF, bad byte and setup/spawn failures");
}
