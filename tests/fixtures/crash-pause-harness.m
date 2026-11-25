#import <Foundation/Foundation.h>
#include <pthread.h>
#include <limits.h>
#include <stdlib.h>
#undef assert
#define assert(...) do { if (!(__VA_ARGS__)) { fprintf(stderr, "fixture regression: crash pause line %d\n", __LINE__); _Exit(86); } } while (0)
/* PRODUCTION_STATE_TYPE */
static crash_reporter_state gCrashReporterState = kCrashReporterStateNotActive;
static NSUncaughtExceptionHandler *defaultNSExceptionHandler, *installedHandler;
static int gExceptionPort = 77, installedPort, disables, restores, badKeys;
static void crashreporter_catch_objc(NSException *exception) { (void)exception; }
static void prior_handler(NSException *exception) { (void)exception; }
static NSUncaughtExceptionHandler *fixture_get_handler(void) { return installedHandler; }
static void fixture_set_handler(NSUncaughtExceptionHandler *handler) { installedHandler = handler; }
static int fixture_set_ports(int task, int mask, int port, int behavior, int flavor) {
    (void)task; (void)mask; (void)behavior; (void)flavor;
    installedPort = port;
    if (port) restores++; else disables++;
    return 0;
}
#define NSGetUncaughtExceptionHandler fixture_get_handler
#define NSSetUncaughtExceptionHandler fixture_set_handler
#define task_set_exception_ports fixture_set_ports
#define mach_task_self_ 1
#define EXC_MASK_CRASH_RELATED 1
#define MACH_PORT_NULL 0
#define EXCEPTION_DEFAULT 1
#define MACH_EXCEPTION_CODES 2
#define ARM_THREAD_STATE64 6
#define JBLogError(...) do { badKeys++; } while (0)
/* PRODUCTION_PAUSE */
static dispatch_semaphore_t aPaused, bDone, releaseA;
static void wait_signal(dispatch_semaphore_t signal) {
    assert(dispatch_semaphore_wait(signal, dispatch_time(DISPATCH_TIME_NOW, 5*NSEC_PER_SEC)) == 0);
}
static void *spawn_a(void *input) {
    (void)input;
    @autoreleasepool {
        int key = crashreporter_pause();
        dispatch_semaphore_signal(aPaused);
        wait_signal(releaseA);
        crashreporter_resume(key);
    }
    return NULL;
}
static void *spawn_b(void *input) {
    (void)input;
    @autoreleasepool {
        wait_signal(aPaused);
        int key = crashreporter_pause();
        crashreporter_resume(key);
        dispatch_semaphore_signal(bDone);
    }
    return NULL;
}
static void *churn(void *input) {
    (void)input;
    for (unsigned i = 0; i < 500; i++) @autoreleasepool {
        int key = crashreporter_pause();
        @synchronized(@"CrashReporterStateKey") {
            assert(installedPort == 0 && installedHandler == prior_handler);
        }
        crashreporter_resume(key);
    }
    return NULL;
}
int main(void) {
    @autoreleasepool {
        installedHandler = prior_handler;
        assert(crashreporter_pause() == 0);
        crashreporter_resume(0);
        assert(!disables && !restores);
        gCrashReporterState = kCrashReporterStatePaused;
        crashreporter_activate_locked();
        assert(installedPort == 77 && installedHandler == crashreporter_catch_objc);
        int first = crashreporter_pause(), second = crashreporter_pause();
        int before = restores;
        crashreporter_resume(first);
        assert(installedPort == 0 && restores == before);
        crashreporter_resume(second);
        assert(installedPort == 77 && restores == before + 1);
        int next = crashreporter_pause();
        crashreporter_resume(first);
        assert(installedPort == 0 && badKeys == 1);
        crashreporter_resume(next);
        aPaused = dispatch_semaphore_create(0);
        bDone = dispatch_semaphore_create(0);
        releaseA = dispatch_semaphore_create(0);
        pthread_t a, b;
        assert(!pthread_create(&a, NULL, spawn_a, NULL));
        assert(!pthread_create(&b, NULL, spawn_b, NULL));
        wait_signal(bDone);
        assert(installedPort == 0 && installedHandler == prior_handler);
        dispatch_semaphore_signal(releaseA);
        assert(!pthread_join(a, NULL) && !pthread_join(b, NULL));
        assert(installedPort == 77 && installedHandler == crashreporter_catch_objc);
        pthread_t threads[4];
        for (unsigned i = 0; i < 4; i++) assert(!pthread_create(&threads[i], NULL, churn, NULL));
        for (unsigned i = 0; i < 4; i++) assert(!pthread_join(threads[i], NULL));
        assert(installedPort == 77 && gCrashReporterPauseDepth == 0);
        gCrashReporterStateKey = INT_MAX;
        int wrapped = crashreporter_pause();
        assert(wrapped > 0);
        crashreporter_resume(wrapped);
        assert(installedPort == 77 && restores == disables + 1);
    }
    puts("PASS production exception-port scopes: nested, overlapping, stale, inactive and key rollover");
}
