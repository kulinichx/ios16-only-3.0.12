#import <Foundation/Foundation.h>
#include <assert.h>
#include <pthread.h>
#include <string.h>
#include <limits.h>
static uint64_t get_job_cache(pid_t pid) { return pid > 0 ? (uint64_t)pid : 0; }
static void register_job(pid_t pid) { (void)pid; }
static int proc_get_path(pid_t pid, char *path) { return snprintf(path,PATH_MAX,"/app/%d",pid); }
static int proc_get_identifier(pid_t pid, char *identifier) { return snprintf(identifier,255,"app.%d",pid); }
/* PRODUCTION_CACHE */
static void *churn(void *input) {
    unsigned first=(unsigned)(uintptr_t)input;
    for (unsigned i=first;i<first+2000;i++) @autoreleasepool {
        NSDictionary *value=cachedJobInfo((pid_t)i,false);
        assert(([value[@"identifier"] isEqualToString:[NSString stringWithFormat:@"app.%u",i]]));
    }
    return NULL;
}
int main(void) {
    @autoreleasepool {
        assert(!cachedJobInfo(0,false));
        __weak NSDictionary *weakOld;
        @autoreleasepool {
            __attribute__((objc_precise_lifetime)) NSDictionary *held=cachedJobInfo(1,false);
            weakOld=held;
            const char *identifier=[held[@"identifier"] UTF8String];
            pthread_t threads[4];
            for(unsigned i=0;i<4;i++) assert(!pthread_create(&threads[i],NULL,churn,(void *)(uintptr_t)(10000+3000*i)));
            for(unsigned i=0;i<4;i++) assert(!pthread_join(threads[i],NULL));
            assert(!strcmp(identifier,"app.1") && weakOld);
        }
        // The evicted entry must be releasable after its last active user finishes.
        assert(!weakOld);
        assert([cachedJobInfo(1,false)[@"identifier"] isEqualToString:@"app.1"]);
    }
    puts("PASS production bounded cache: concurrent churn, eviction and held UTF8String lifetime");
}
