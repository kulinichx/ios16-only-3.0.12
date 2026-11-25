#import <Foundation/Foundation.h>
#include <assert.h>
#include <atomic>
#include <map>
#include <pthread.h>
#include <stdint.h>
#include <limits.h>
#include <stdlib.h>
#undef assert
#define assert(...) do { if (!(__VA_ARGS__)) { fprintf(stderr, "fixture regression: identity line %d\n", __LINE__); _Exit(86); } } while (0)
static std::atomic<uint64_t> liveIdentity[16];
static uint64_t proc_get_uniqueid(pid_t pid) { return pid > 0 && pid < 16 ? liveIdentity[pid].load() : 0; }
/* PRODUCTION_IDENTITY_CACHE */
static int proc_get_path(pid_t pid, char *path) { return snprintf(path, PATH_MAX, "/app/%llu", (unsigned long long)proc_get_uniqueid(pid)); }
static int proc_get_identifier(pid_t pid, char *identifier) { return snprintf(identifier, 255, "app.%llu", (unsigned long long)proc_get_uniqueid(pid)); }
/* PRODUCTION_JOB_INFO */
static void *churn(void *input) {
    pid_t pid = (pid_t)(uintptr_t)input;
    for (unsigned i = 1; i <= 1000; i++) @autoreleasepool {
        uint64_t identity = (uint64_t)pid * 10000 + i;
        liveIdentity[pid] = identity;
        assert(get_job_cache(pid) == 0);
        register_job(pid);
        assert(get_job_cache(pid) == identity);
        assert([cachedJobInfo(pid, false)[@"identifier"] isEqual:[NSString stringWithFormat:@"app.%llu", (unsigned long long)identity]]);
    }
    return NULL;
}
int main(void) {
    @autoreleasepool {
        assert(!get_job_cache(0) && !get_job_cache(-1));
        register_job(0); register_job(-1);
        liveIdentity[1] = 101; register_job(1);
        assert(get_job_cache(1) == 101);
        NSDictionary *old = cachedJobInfo(1, false);
        assert([old[@"identifier"] isEqual:@"app.101"]);
        liveIdentity[1] = 102;
        assert(!get_job_cache(1) && !cachedJobInfo(1, false));
        NSDictionary *replacement = cachedJobInfo(1, true);
        assert([replacement[@"identifier"] isEqual:@"app.102"]);
        assert([old[@"identifier"] isEqual:@"app.101"]);
        liveIdentity[1] = 0;
        assert(!get_job_cache(1));
        register_job(1); assert(jobCache->find(1) == jobCache->end());
        pthread_t threads[4];
        for (uintptr_t i = 0; i < 4; i++) assert(!pthread_create(&threads[i], NULL, churn, (void *)(i + 2)));
        for (unsigned i = 0; i < 4; i++) assert(!pthread_join(threads[i], NULL));
    }
    puts("PASS production job identity: PID reuse, exit, refresh and concurrent registration");
}
