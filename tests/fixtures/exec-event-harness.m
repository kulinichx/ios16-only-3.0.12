#import <Foundation/Foundation.h>
#include <assert.h>
#include <errno.h>
#include <stdbool.h>
#include <stdint.h>
#include <signal.h>
#include <sys/event.h>

static int kq = 42, patchCalls, killSignal, changeCalls, interruptCalls, failAdd;
static uintptr_t kernelGeneration;
static dispatch_queue_t gExecPatchDataQueue;
static NSMutableDictionary *gExecPatchArray;
static uintptr_t gExecPatchGeneration;
static void audit_log(const char *format, ...) { (void)format; }
#define JBLogError(...) audit_log(__VA_ARGS__)
#define JBLogDebug(...) audit_log(__VA_ARGS__)
static void initExecPatch(void) {}
static int roothide_patch_proc(pid_t pid) { assert(pid == 123); patchCalls++; return 0; }
static int mock_kill(pid_t pid, int sig) { assert(pid == 123); killSignal = sig; return 0; }
static int mock_kevent(int queue, const struct kevent *changes, int count, struct kevent *events, int eventCount, const struct timespec *timeout)
{
    assert(queue == 42 && count == 1 && !events && !eventCount && !timeout); changeCalls++;
    if (interruptCalls-- > 0) { errno = EINTR; return -1; }
    if (changes->flags & EV_DELETE) {
        if (!kernelGeneration) { errno = ENOENT; return -1; }
        kernelGeneration = 0; return 0;
    }
    assert(changes->flags & EV_ADD);
    if (failAdd) { errno = ESRCH; return -1; }
    kernelGeneration = (uintptr_t)changes->udata;
    return 0;
}
#define kevent(...) mock_kevent(__VA_ARGS__)
#define kill mock_kill
/* PRODUCTION_EXEC */
#undef kevent
#undef kill
static struct kevent eventFor(uintptr_t generation, unsigned flags)
{
    struct kevent event;
    EV_SET(&event,123,EVFILT_PROC,0,flags,0,(void *)generation);
    return event;
}
int main(void)
{
 @autoreleasepool {
    gExecPatchArray = [NSMutableDictionary dictionary];
    gExecPatchDataQueue = dispatch_queue_create("test.exec",DISPATCH_QUEUE_SERIAL);
    assert(spawnExecPatchAdd(123,true) == 0);
    uintptr_t old = kernelGeneration; assert(old && gExecPatchArray.count == 1);
    assert(spawnExecPatchAdd(123,false) == 0);
    uintptr_t fresh = kernelGeneration; assert(fresh != old);
    struct kevent stale = eventFor(old,NOTE_EXEC); handle_exec_patch_event(&stale);
    assert(gExecPatchArray.count == 1 && !patchCalls && !killSignal);
    struct kevent active = eventFor(fresh,NOTE_EXEC); handle_exec_patch_event(&active);
    assert(!gExecPatchArray.count && patchCalls == 1 && !killSignal);
    kernelGeneration = 0;
    interruptCalls = 2; assert(spawnExecPatchAdd(123,true) == 0);
    active = eventFor(kernelGeneration,NOTE_EXEC); handle_exec_patch_event(&active);
    assert(patchCalls == 2 && killSignal == SIGCONT && !gExecPatchArray.count);
    kernelGeneration = 0; assert(spawnExecPatchAdd(123,true) == 0);
    active = eventFor(kernelGeneration,NOTE_EXIT); handle_exec_patch_event(&active);
    assert(!gExecPatchArray.count && patchCalls == 2);
    kernelGeneration = 0; failAdd = 1;
    assert(spawnExecPatchAdd(123,true) == -1 && errno == ESRCH); assert(!gExecPatchArray.count);
    failAdd = 0; assert(spawnExecPatchAdd(123,true) == 0);
    // The one-shot event may already be removed by the kernel when cancellation arrives.
    kernelGeneration = 0;
    assert(spawnExecPatchDel(123) == -1 && errno == ENOENT); assert(!gExecPatchArray.count);
    assert(spawnExecPatchAdd(123,true) == 0); assert(spawnExecPatchDel(123) == 0); assert(!gExecPatchArray.count);
    assert(changeCalls > 10);
    puts("PASS production exec event generations, NOTE_EXIT cleanup, registration failure and EINTR");
 }
 return 0;
}
