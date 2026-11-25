#import "RCScheduleRuntime.h"
#import "RCLowPowerSchedule.h"

#define CHECK(value) do { if (!(value)) { NSLog(@"FAIL line %d: %s", __LINE__, #value); abort(); } } while (0)
NSNotificationName const UIApplicationDidFinishLaunchingNotification = @"test.springboard.didFinishLaunching";
char *JB_RootPath;
static NSUInteger lowStarts, batteryStarts, lowRefreshes, batteryRefreshes;
static BOOL postingLaunch;

void rcLowPowerScheduleStart(void) { CHECK(NSThread.isMainThread && !postingLaunch); lowStarts++; }
void rcBatteryRecordStart(void) { CHECK(NSThread.isMainThread && !postingLaunch); batteryStarts++; }
void rcLowPowerScheduleRefresh(void) { CHECK(batteryStarts == 1); lowRefreshes++; }
void rcBatteryRecordRefresh(void) { CHECK(lowRefreshes == 1); batteryRefreshes++; }

static void pumpUntil(BOOL (^done)(void))
{
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:5];
    while (!done() && limit.timeIntervalSinceNow > 0)
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    CHECK(done());
}

int main(int argc, const char *argv[])
{
    (void)argc;
    @autoreleasepool {
        NSString *root = [NSString stringWithUTF8String:argv[1]];
        CHECK(rcScheduleRuntimeRoot() == nil);
        JB_RootPath = "/"; CHECK(rcScheduleRuntimeRoot() == nil);
        JB_RootPath = (char *)root.UTF8String;
        CHECK([rcScheduleRuntimeRoot() isEqual:root]);

        rcScheduleServicesStartAfterLaunch(); rcScheduleServicesStartAfterLaunch();
        __block BOOL idle = NO;
        dispatch_async(dispatch_get_main_queue(), ^{ idle = YES; });
        pumpUntil(^BOOL { return idle; });
        CHECK(lowStarts == 0 && batteryStarts == 0);
        postingLaunch = YES;
        [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationDidFinishLaunchingNotification object:nil];
        CHECK(lowStarts == 0 && batteryStarts == 0);
        postingLaunch = NO;
        pumpUntil(^BOOL { return batteryRefreshes == 1; });
        [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationDidFinishLaunchingNotification object:nil];
        rcScheduleServicesStartAfterLaunch();
        idle = NO; dispatch_async(dispatch_get_main_queue(), ^{ idle = YES; });
        pumpUntil(^BOOL { return idle; });
        CHECK(lowStarts == 1 && batteryStarts == 1 && lowRefreshes == 1 && batteryRefreshes == 1);

        // Block the real I/O queue to simulate slow storage. The UI queue must
        // still run, and publishers must snapshot nested mutable state first.
        dispatch_semaphore_t gate = dispatch_semaphore_create(0);
        dispatch_async(rcScheduleIOQueue(), ^{
            CHECK(!NSThread.isMainThread);
            CHECK(dispatch_semaphore_wait(gate, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) == 0);
        });
        NSString *path = [root stringByAppendingPathComponent:@"status.plist"];
        NSMutableDictionary *record = [@{@"State": @"original"} mutableCopy];
        NSMutableDictionary *status = [@{@"Records": [NSMutableArray arrayWithObject:record]} mutableCopy];
        __block BOOL published = NO;
        rcSchedulePublishDictionary(status, path, NULL, ^(BOOL success, NSError *error) {
            CHECK(NSThread.isMainThread && success && !error); published = YES;
        });
        record[@"State"] = @"mutated";
        idle = NO; dispatch_async(dispatch_get_main_queue(), ^{ idle = YES; });
        pumpUntil(^BOOL { return idle; });
        CHECK(!published && ![NSFileManager.defaultManager fileExistsAtPath:path]);
        dispatch_semaphore_signal(gate);
        pumpUntil(^BOOL { return published; });
        CHECK([rcLowPowerReadDictionary(path)[@"Records"][0][@"State"] isEqual:@"original"]);

        // Writes commit in submission order; failures complete on the main
        // queue and never produce a success callback for an uncommitted status.
        __block NSUInteger completions = 0;
        for (NSUInteger revision = 1; revision <= 2; revision++)
            rcSchedulePublishDictionary(@{@"Revision": @(revision)}, path, NULL, ^(BOOL success, NSError *error) {
                CHECK(NSThread.isMainThread && success && !error);
                CHECK(++completions == revision);
            });
        pumpUntil(^BOOL { return completions == 2; });
        CHECK([rcLowPowerReadDictionary(path)[@"Revision"] unsignedIntegerValue] == 2);
        __block BOOL failed = NO;
        rcSchedulePublishDictionary(@{}, nil, NULL, ^(BOOL success, NSError *error) {
            CHECK(NSThread.isMainThread && !success && error != nil); failed = YES;
        });
        pumpUntil(^BOOL { return failed; });
    }
    return 0;
}
