#define RC_LOW_POWER_TEST 1
#import "lowpowerschedule.m"

static NSString *root;
static NSUInteger requests, onRequests;
static BOOL modeOn, accepts;
const char *jbclient_get_jbroot(void) { return root.UTF8String; }
NSDate *rcLowPowerTestNow(void) { return NSDate.date; }
NSString *rcLowPowerTestBootSession(void) { return @"test"; }
static NSInteger submittedMode = -1;
@interface TestIOS16PowerSetter : NSObject <RCLowPowerModeAPI>
+ (instancetype)sharedInstance;
- (void)setPowerMode:(NSInteger)mode fromSource:(NSString *)source;
@end
@implementation TestIOS16PowerSetter
+ (instancetype)sharedInstance { return [self new]; }
- (void)setPowerMode:(NSInteger)mode fromSource:(NSString *)source { submittedMode = mode; }
@end

@interface TestScheduler : RCLowPowerScheduler @end
@implementation TestScheduler
- (BOOL)requestPowerOff { requests++; return accepts; }
- (BOOL)requestPowerMode:(BOOL)enabled { if (enabled) onRequests++; return accepts; }
- (BOOL)systemLowPowerEnabled { return modeOn; }
@end

#define CHECK(x) do { if (!(x)) { NSLog(@"Failed at line %d", __LINE__); abort(); } } while (0)
static NSString *state(void) { return rcLowPowerReadDictionary(rcLowPowerStatusPath(root))[@"State"]; }
static void writePlan(BOOL stop)
{
    NSMutableDictionary *plan = [rcLowPowerDefaultConfiguration() mutableCopy];
    plan[@"Revision"] = NSUUID.UUID.UUIDString;
    if (stop) plan[@"DisableRequest"] = plan[@"Revision"];
    CHECK(rcLowPowerWriteDictionary(plan, rcLowPowerConfigurationPath(root), NULL));
}
static void waitForReadback(void)
{
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:4];
    while ([state() isEqual:@"verifying"] && limit.timeIntervalSinceNow > 0)
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
}
static void checkDeferredWindow(void)
{
    NSCalendar *calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    calendar.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:28800];
    NSISO8601DateFormatter *formatter = [NSISO8601DateFormatter new];
    NSDate *now = [formatter dateFromString:@"2026-11-22T00:33:00+08:00"];
    NSDate *end = [formatter dateFromString:@"2026-11-22T06:30:00+08:00"];
    NSDate *nextStart = [formatter dateFromString:@"2026-11-23T00:31:00+08:00"];
    NSMutableDictionary *plan = [rcLowPowerDefaultConfiguration() mutableCopy];
    [plan addEntriesFromDictionary:@{@"Enabled": @YES, @"StartMinute": @31, @"EndMinute": @390, @"SkipThrough": end}];
    for (NSDate *time in @[now, end, [end dateByAddingTimeInterval:60]]) {
        CHECK(rcLowPowerEventIsDeferred(plan, rcLowPowerEvent(plan, time, calendar, NO)));
        CHECK([rcLowPowerNextScheduledEvent(plan, time, calendar)[@"Date"] isEqual:nextStart]);
    }
    CHECK(!rcLowPowerEventIsDeferred(plan, rcLowPowerEvent(plan, nextStart, calendar, NO)));
    CHECK(![rcLowPowerNextScheduledEvent(plan, nextStart, calendar)[@"PowerMode"] boolValue]);
    plan[@"StartMinute"] = @1380; // The prior start is on the previous day.
    CHECK(rcLowPowerEventIsDeferred(plan, rcLowPowerEvent(plan, now, calendar, NO)));
    CHECK([rcLowPowerNextScheduledEvent(plan, now, calendar)[@"Date"] isEqual:
        [formatter dateFromString:@"2026-11-22T23:00:00+08:00"]]);
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        root = [NSString stringWithUTF8String:argv[1]];
        TestScheduler *s = [TestScheduler new];
        modeOn = accepts = YES;
        writePlan(NO); [s refresh]; CHECK(requests == 0);
        writePlan(YES); [s refresh]; [s refresh];
        CHECK(requests == 1 && [state() isEqual:@"verifying"] && !s.timer);
        modeOn = NO; waitForReadback(); CHECK([state() isEqual:@"disabled"]);
        modeOn = YES; s = [TestScheduler new]; [s refresh];
        CHECK(requests == 1 && [state() isEqual:@"disabled"]);
        writePlan(YES); [s refresh]; waitForReadback();
        CHECK(requests == 4 && [state() isEqual:@"applyFailed"]);
        accepts = NO; writePlan(YES); [s refresh];
        CHECK(requests == 5 && [state() isEqual:@"verifying"]);
        modeOn = NO; waitForReadback(); CHECK([state() isEqual:@"disabled"]);

        CHECK(rcPowerSetterMatches(TestIOS16PowerSetter.class));
        CHECK(rcSubmitPowerMode(TestIOS16PowerSetter.sharedInstance, 1) && submittedMode == 1);
        CHECK(rcSubmitPowerMode(TestIOS16PowerSetter.sharedInstance, 0) && submittedMode == 0);
        checkDeferredWindow();
        NSMutableDictionary *plan = [rcLowPowerDefaultConfiguration() mutableCopy];
        plan[@"Enabled"] = @YES;
        plan[@"Revision"] = NSUUID.UUID.UUIDString;
        NSDate *now = NSDate.date;
        NSDictionary *event = @{@"Revision": plan[@"Revision"], @"Date": now, @"PowerMode": @YES};
        CHECK(![s applyEvent:event configuration:plan root:root now:now] && onRequests == 0);
        CHECK(rcLowPowerWriteDictionary(plan, rcLowPowerConfigurationPath(root), NULL));
        accepts = YES;
        CHECK([[s applyEvent:event configuration:plan root:root now:now] isEqual:@"verifying"]);
        CHECK(onRequests == 1 && !s.lastHandled);
        s.awaitingEventReadback = NO;
        CHECK([[s applyEvent:event configuration:plan root:root now:now] isEqual:@"applyFailed"]);
        CHECK(!s.lastHandled);
        CHECK([[s applyEvent:event configuration:plan root:root now:[now dateByAddingTimeInterval:61]] isEqual:@"verifying"]);
        modeOn = YES;
        s.awaitingEventReadback = NO;
        CHECK([[s applyEvent:event configuration:plan root:root now:now] isEqual:@"scheduled"]);
        CHECK(onRequests == 2 && [s.lastHandled isEqual:event]);
    }
    return 0;
}
