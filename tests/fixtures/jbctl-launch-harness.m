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
static bool failSpawn, failActions, failInherit, interruptWrite, interruptWait;
static int pipeLayout;
static unsigned spawnCalls, waits, reapedChildren;
static pid_t test_waitpid(pid_t pid, int *status, int options) {
    if (interruptWait) { interruptWait=false; errno=EINTR; return -1; }
    pid_t result=waitpid(pid,status,options);
    if(result==pid && (WIFEXITED(*status) || WIFSIGNALED(*status))) reapedChildren++;
    return result;
}
#define waitpid test_waitpid
/* PRODUCTION_WAIT_STATUS */
#undef waitpid
static int cmd_wait_for_exit(pid_t pid) {
    assert(!inRoot && !inSandbox); waits++;
    return production_cmd_wait_for_exit(pid);
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
static int test_dup2(posix_spawn_file_actions_t *actions, int source, int destination) {
    // XNU 8792 records PSFA_DUP2 and its kernel dup2(fd, fd) is a no-op.
    // Emulate that behavior even if the macOS runner implements newer rules.
    if (source == destination) return 0;
    return posix_spawn_file_actions_adddup2(actions,source,destination);
}
static int test_inherit(posix_spawn_file_actions_t *actions, int fd) {
    assert(fd==3);
    return failInherit ? ENOMEM : posix_spawn_file_actions_addinherit_np(actions,fd);
}
static int test_pipe(int fds[2]) {
    int original[2]; if(pipe(original)!=0) return -1;
    int reader=fcntl(original[0],F_DUPFD_CLOEXEC,64);
    int writer=fcntl(original[1],F_DUPFD_CLOEXEC,64);
    assert(reader>=64 && writer>=64); close(original[0]); close(original[1]);
    if(pipeLayout==1) { assert(dup2(reader,3)==3); close(reader); reader=3; }
    if(pipeLayout==2) { assert(dup2(writer,3)==3); close(writer); writer=3; }
    fds[0]=reader; fds[1]=writer; return 0;
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
#define posix_spawn_file_actions_adddup2 test_dup2
#define posix_spawn_file_actions_addinherit_np test_inherit
#define pipe test_pipe
#define write test_write
/* PRODUCTION_LAUNCH */
#undef write
#undef pipe
#undef posix_spawn_file_actions_addinherit_np
#undef posix_spawn_file_actions_adddup2
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
    if(argc>=2 && !strcmp(argv[1],"--child")) {
        alarm(5); // A broken descriptor must not leave the test child blocked.
        if(argc>=4 && !strcmp(argv[argc-2],"--waitfor")) {
            int result=wait_for_release(atoi(argv[argc-1])); if(result) return result;
        }
        alarm(0);
        if(argc>=3 && !strcmp(argv[2],"exit1")) return 1;
        if(argc>=3 && !strcmp(argv[2],"signal")) raise(SIGTERM);
        return 0;
    }
    assert(argc==1); selfPath=argv[0];
    @autoreleasepool {
        DOEnvironmentManager *env=[DOEnvironmentManager new]; env.jailbrokenVersion=@"3.0.12";
        int saved3=fcntl(3,F_DUPFD_CLOEXEC,100); close(3);
        interruptWrite=true; interruptWait=true; pipeLayout=1;
        int firstStatus=[env spawnJbctlAsRootWithArgs:@[@"--child"]];
        if(firstStatus!=0) {
            fprintf(stderr,"fd3 handshake regression: status=%d\n",firstStatus);
            fflush(stderr); _exit(86); // Avoid macOS crash-report handling in the mutant run.
        }
        assert(spawnCalls==1 && waits==1);
        assert(reapedChildren==1);
        assert(fcntl(3,F_GETFD)==-1 && errno==EBADF);
        pipeLayout=2;
        assert([env spawnJbctlAsRootWithArgs:@[@"--child"]]==0 && spawnCalls==2 && waits==2);
        pipeLayout=0;
        assert([env spawnJbctlAsRootWithArgs:@[@"--child"]]==0 && spawnCalls==3 && waits==3);
        assert(([env spawnJbctlAsRootWithArgs:@[@"--child",@"exit1"]]==256 && waits==4));
        int signaled=[env spawnJbctlAsRootWithArgs:@[@"--child",@"signal"]];
        assert(WIFSIGNALED(signaled) && WTERMSIG(signaled)==SIGTERM && waits==5);
        env.jailbrokenVersion=@"3.0.13";
        assert([env spawnJbctlAsRootWithArgs:@[@"--child"]]==0 && waits==6);
        failSpawn=true;
        assert([env spawnJbctlAsRootWithArgs:@[@"--child"]]==EACCES && waits==6); failSpawn=false;
        failActions=true;
        assert([env spawnJbctlAsRootWithArgs:@[@"--child"]]==ENOMEM && spawnCalls==7); failActions=false;
        failInherit=true;
        assert([env spawnJbctlAsRootWithArgs:@[@"--child"]]==ENOMEM && spawnCalls==7); failInherit=false;
        skipPrivilege=true;
        assert([env spawnJbctlAsRootWithArgs:@[@"--child"]]==EPERM && waits==6); skipPrivilege=false;
        env.jailbrokenVersion=@"3.0.4";
        assert([env spawnJbctlAsRootWithArgs:@[@"--child"]]==0 && waits==7);
        if(saved3>=0) { assert(dup2(saved3,3)==3); close(saved3); }
        int fds[2]; assert(pipe(fds)==0); interruptRead=true;
        assert(write(fds[1],"w",1)==1 && wait_for_release(fds[0])==0); close(fds[1]);
        assert(pipe(fds)==0); close(fds[1]); assert(wait_for_release(fds[0])==1);
        assert(pipe(fds)==0); assert(write(fds[1],"x",1)==1 && wait_for_release(fds[0])==1); close(fds[1]);
    }
    puts("PASS production App/jbctl launch: iOS 16 fd-3 inheritance, all pipe layouts, raw exit/signal status, EINTR and failures");
}
