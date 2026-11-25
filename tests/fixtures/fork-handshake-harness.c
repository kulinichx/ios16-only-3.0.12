#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <setjmp.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <signal.h>
#include <sys/wait.h>

static int nextFd, pipeCalls, failPipeCall, failFcntlCall, fcntlCalls;
static int closed[32], closeCount, fixResult, fixCalls, killCalls, waitCalls;
static int readInterrupts, writeInterrupts;
static ssize_t readResult, writeResult;
static pid_t forkResult;
static jmp_buf childExit;
static int exitStatus;
static int mock_pipe(int out[2])
{ if (++pipeCalls == failPipeCall) { errno = EMFILE; return -1; } out[0] = nextFd++; out[1] = nextFd++; return 0; }
static int mock_fcntl(int fd, int command, ...)
{ assert(fd >= 10); assert(command == F_SETNOSIGPIPE); if (++fcntlCalls == failFcntlCall) { errno = EIO; return -1; } return 0; }
static int ffsys_close(int fd) { assert(fd >= 10 && fd < 32); assert(!closed[fd]++); closeCount++; return 0; }
static pid_t ffsys_fork(void) { if (forkResult < 0) errno = EAGAIN; return forkResult; }
static ssize_t ffsys_read(int fd, void *data, size_t size)
{ (void)fd; (void)data; assert(size == 1); if (readInterrupts-- > 0) return -EINTR; return readResult; }
static ssize_t ffsys_write(int fd, const void *data, size_t size)
{ (void)fd; (void)data; assert(size == 1); if (writeInterrupts-- > 0) return -EINTR; return writeResult; }
static int jbclient_mach_fork_fix(pid_t pid) { assert(pid == 123); fixCalls++; return fixResult; }
static int mock_kill(pid_t pid, int sig) { assert(pid == 123 && sig == SIGKILL); killCalls++; return 0; }
static pid_t mock_waitpid(pid_t pid, int *status, int flags)
{ (void)status; assert(pid == 123 && flags == 0); if (++waitCalls == 1) { errno = EINTR; return -1; } return pid; }
__attribute__((noreturn)) static void ffsys_exit(int status) { exitStatus = status; longjmp(childExit, 1); }
#define pipe mock_pipe
#define fcntl mock_fcntl
#define kill mock_kill
#define waitpid mock_waitpid
/* PRODUCTION_FORK */
#undef pipe
#undef fcntl
#undef kill
#undef waitpid
static void reset(void)
{
 nextFd = 10; pipeCalls = failPipeCall = failFcntlCall = fcntlCalls = closeCount = fixResult = fixCalls = killCalls = waitCalls = 0;
 readInterrupts = writeInterrupts = 0; readResult = writeResult = 1; forkResult = 123; memset(closed,0,sizeof(closed));
}
int main(void)
{
 reset(); assert(forkfix___fork() == 123); assert(closeCount == 4 && fixCalls == 1 && !killCalls);
 reset(); readInterrupts = writeInterrupts = 2; assert(forkfix___fork() == 123); assert(closeCount == 4 && fixCalls == 1);
 reset(); forkResult = -1; assert(forkfix___fork() == -1 && errno == EAGAIN); assert(closeCount == 4 && !fixCalls);
 for (int n=1;n<=2;n++) { reset(); failPipeCall=n; assert(forkfix___fork() == -1 && errno == EMFILE); assert(closeCount == (n-1)*2); }
 for (int n=1;n<=2;n++) { reset(); failFcntlCall=n; assert(forkfix___fork() == -1 && errno == EIO); assert(closeCount == 4); }
 reset(); readResult = 0; assert(forkfix___fork() == -1 && errno == EPIPE); assert(!fixCalls && killCalls == 1 && waitCalls == 2 && closeCount == 4);
 reset(); fixResult = 5; assert(forkfix___fork() == -1 && errno == EIO); assert(fixCalls == 1 && killCalls == 1 && closeCount == 4);
 reset(); writeResult = -EPIPE; assert(forkfix___fork() == -1 && errno == EPIPE); assert(killCalls == 1 && closeCount == 4);
 reset(); forkResult = 0; assert(forkfix___fork() == 0); assert(!fixCalls && closeCount == 4);
 reset(); forkResult = 0; readResult = 0;
 if (setjmp(childExit) == 0) { forkfix___fork(); assert(!"child must exit on handshake EOF"); }
 assert(exitStatus == 127 && closeCount == 2);
 // Two overlapping forks must hold independent endpoints.
 reset(); struct fork_pipes a = {{-1,-1},{-1,-1}}, b = a;
 assert(open_pipes(&a) == 0 && open_pipes(&b) == 0);
 assert(a.parentToChild[0] != b.parentToChild[0]); close_pipes(&a); close_pipes(&b); assert(closeCount == 8);
 puts("PASS production fork handshake failure, EINTR, EOF, child cleanup and per-call ownership");
}
