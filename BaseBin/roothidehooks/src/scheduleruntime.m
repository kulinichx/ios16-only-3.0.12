#import "RCScheduleRuntime.h"
#import "RCLowPowerSchedule.h"
#include <dlfcn.h>
#include <notify.h>

NSString *rcScheduleRuntimeRoot(void)
{
    // systemhook sets this before loading roothidehooks. Resolve its unique
    // cached data symbol: get_jbroot also exists in libjailbreak, whose copy
    // need not have a root in an injected process. Never fall back to IPC.
    char **cachedRoot = (char **)dlsym(RTLD_DEFAULT, "JB_RootPath");
    const char *root = cachedRoot ? *cachedRoot : NULL;
    if (!root || root[0] != '/' || root[1] == '\0') return nil;
    return [NSString stringWithUTF8String:root];
}

dispatch_queue_t rcScheduleIOQueue(void)
{
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        queue = dispatch_queue_create("com.dopaminerh.rc9.schedule-io", DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

void rcSchedulePublishDictionary(NSDictionary *dictionary, NSString *path,
    const char *notification, void (^completion)(BOOL success, NSError *error))
{
    // Recorder records contain mutable nested dictionaries. A shallow copy
    // would allow the main thread to mutate data while the writer serializes it.
    NSDictionary *snapshot = dictionary ? CFBridgingRelease(CFPropertyListCreateDeepCopy(
        kCFAllocatorDefault, (__bridge CFPropertyListRef)dictionary, kCFPropertyListImmutable)) : nil;
    NSString *destination = [path copy];
    NSString *name = notification ? [NSString stringWithUTF8String:notification] : nil;
    dispatch_async(rcScheduleIOQueue(), ^{
        @autoreleasepool {
            NSError *error = nil;
            BOOL success = snapshot && rcLowPowerWriteDictionary(snapshot, destination, &error);
            if (!success && !error)
                error = [NSError errorWithDomain:NSPOSIXErrorDomain code:EINVAL userInfo:nil];
            // Readers may observe a status only after its atomic write succeeds.
            if (success && name) notify_post(name.UTF8String);
            if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(success, error); });
        }
    });
}
