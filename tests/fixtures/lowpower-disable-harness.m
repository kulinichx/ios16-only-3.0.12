#define RC_LOW_POWER_TEST 1
#import "lowpowerschedule.m"

static NSString *root;
static NSUInteger requests;
static BOOL modeOn, accepts;
const char *jbclient_get_jbroot(void) { return root.UTF8String; }
NSDate *rcLowPowerTestNow(void) { return NSDate.date; }
NSString *rcLowPowerTestBootSession(void) { return @"test"; }
@interface TestScheduler : RCLowPowerScheduler @end
@implementation TestScheduler
- (BOOL)requestPowerOff { requests++; return accepts; }
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
        CHECK(requests == 2 && [state() isEqual:@"applyFailed"]);
        accepts = NO; writePlan(YES); [s refresh];
        CHECK(requests == 3 && [state() isEqual:@"applyFailed"]);
    }
    return 0;
}
