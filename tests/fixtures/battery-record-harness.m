#define RC_BATTERY_TEST 1
#import "RCBatteryRecord.h"
#import <Foundation/Foundation.h>
#define CHECK(value) do { if (!(value)) { NSLog(@"FAIL line %d: %s", __LINE__, #value); abort(); } } while (0)
static NSString *testRoot;
static NSDate *now;
static NSDate *epoch;
static double level = 82;
static BOOL charging, lowPower, failSample, failTimer;
static NSUInteger samples;
const char *jbclient_get_jbroot(void) { return testRoot.UTF8String; }
NSDate *rcBatteryTestNow(void) { return now; }
NSDictionary *rcBatteryTestSnapshot(void)
{
    samples++;
    if (failSample) return nil;
    return @{@"Date": now, @"Continuous": @([now timeIntervalSinceDate:epoch]), @"Boot": @"test-boot",
        @"Level": @(level), @"BatteryState": charging ? @2 : @1, @"LowPower": @(lowPower), @"Thermal": @1};
}
void rcLowPowerScheduleRefresh(void) {}

// Only the OS timer is replaced. No polling or real system wake is scheduled.
@interface PCPersistentTimer : NSObject
@property(nonatomic) BOOL valid;
@end
@implementation PCPersistentTimer
- (instancetype)initWithFireDate:(NSDate *)date serviceIdentifier:(NSString *)identifier target:(id)target selector:(SEL)selector userInfo:(id)info
{ if ((self = [super init])) self.valid = !failTimer; return self; }
- (void)setDisableSystemWaking:(BOOL)value {}
- (void)setUserVisible:(BOOL)value {}
- (void)setMinimumEarlyFireProportion:(double)value {}
- (void)setEarlyFireConstantInterval:(double)value {}
- (void)scheduleInRunLoop:(NSRunLoop *)runLoop {}
- (void)invalidate { self.valid = NO; }
- (BOOL)isValid { return self.valid; }
@end

/* RUNTIME */

static void command(NSString *action)
{
    CHECK(rcLowPowerWriteDictionary(@{@"ID": NSUUID.UUID.UUIDString, @"Date": now, @"Action": action}, rcBatteryPath(testRoot, @".command"), nil));
    [recorder refresh];
}
static void config(BOOL enabled, BOOL repeat, NSInteger start, NSInteger end, NSDate *first)
{
    NSMutableDictionary *value = [@{@"Version": @1, @"Enabled": @(enabled), @"Repeat": @(repeat),
        @"StartMinute": @(start), @"EndMinute": @(end), @"FirstStart": first, @"Revision": NSUUID.UUID.UUIDString} mutableCopy];
    if (!enabled) value[@"DisableRequest"] = value[@"Revision"];
    CHECK(rcBatteryConfigurationValid(value));
    CHECK(rcLowPowerWriteDictionary(value, rcBatteryPath(testRoot, @".plist"), nil));
    [recorder refresh];
}
static NSDictionary *last(void) { return [recorder.state[@"History"] firstObject]; }
int main(int argc, const char *argv[])
{
    @autoreleasepool {
        testRoot = [NSString stringWithUTF8String:argv[1]];
        NSString *primary = rcLowPowerConfigurationPath(testRoot);
        NSString *legacy = rcScheduleReadPath(primary);
        CHECK(![primary isEqual:legacy]);
        NSDictionary *old = rcLowPowerDefaultConfiguration();
        CHECK(rcLowPowerWriteDictionary(old, legacy, nil));
        CHECK(chmod(legacy.stringByDeletingLastPathComponent.fileSystemRepresentation, 0500) == 0);
        CHECK([rcLowPowerReadDictionary(primary) isEqual:old]);
        NSMutableDictionary *updated = [old mutableCopy]; updated[@"Enabled"] = @YES;
        CHECK(rcLowPowerWriteDictionary(updated, primary, nil));
        CHECK([rcLowPowerReadDictionary(primary) isEqual:updated]);
        CHECK([rcLowPowerReadDictionary(legacy) isEqual:old]);
        CHECK(chmod(legacy.stringByDeletingLastPathComponent.fileSystemRepresentation, 0700) == 0);
        [NSTimeZone setDefaultTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
        NSCalendar *calendar = rcLowPowerLocalCalendar();
        NSDateComponents *parts = [NSDateComponents new]; parts.year = 2030; parts.month = 1; parts.day = 2; parts.hour = 3;
        epoch = [calendar dateFromComponents:parts]; now = epoch;
        recorder = [RCBatteryRecorder new]; [recorder refresh];
        CHECK(recorder.timer == nil && samples == 0);
        command(@"start"); CHECK(recorder.state[@"Active"] != nil && samples == 1);
        [recorder refresh]; CHECK(samples == 1); // Persisted command ID is idempotent.
        now = [epoch dateByAddingTimeInterval:3600]; level = 76;
        command(@"stop"); CHECK(samples == 2);
        CHECK(fabs(rcBatteryDropRate(last()).doubleValue - 6) < 0.001);
        CHECK([last()[@"Start"][@"LowPower"] isEqual:@NO]);
        CHECK([last()[@"End"][@"Thermal"] isEqual:@1]);

        // Charging endpoints remain visible but cannot be compared as drain.
        charging = YES; command(@"start"); now = [now dateByAddingTimeInterval:3600]; command(@"stop");
        CHECK(rcBatteryDropRate(last()) == nil); charging = NO;
        failSample = YES; command(@"start"); CHECK(recorder.state[@"Active"] == nil);
        CHECK([recorder.state[@"CommandResult"] isEqual:@"sampleFailed"]); failSample = NO;

        // One-shot starts only at its real endpoint; low power is already on.
        now = epoch; level = 82; lowPower = YES;
        config(YES, NO, 180, 240, epoch);
        CHECK(recorder.state[@"Active"] != nil && recorder.timer != nil);
        CHECK([recorder.state[@"Active"][@"Start"][@"LowPower"] boolValue]);
        now = [epoch dateByAddingTimeInterval:3600]; level = 80;
        rcBatteryRecordBeforePowerChange(); lowPower = NO; rcBatteryRecordAfterPowerChange();
        CHECK([last()[@"End"][@"LowPower"] boolValue]);
        CHECK([last()[@"Result"] isEqual:@"complete"] && recorder.timer == nil);
        CHECK([recorder.state[@"Completed"] boolValue]);

        // Missed windows do not fabricate an endpoint at app launch.
        NSUInteger previousSamples = samples;
        now = [epoch dateByAddingTimeInterval:7200]; config(YES, NO, 180, 240, epoch);
        CHECK([last()[@"Result"] isEqual:@"missed"] && samples == previousSamples);
        CHECK(last()[@"Start"] == nil);

        // Daily and overnight windows retain independent end and next-start events.
        now = epoch; config(YES, YES, 180, 120, epoch);
        CHECK([recorder.state[@"Active"][@"PlannedEnd"] timeIntervalSinceDate:epoch] == 23 * 3600);
        now = [epoch dateByAddingTimeInterval:23 * 3600 + 121]; [recorder refresh];
        CHECK([last()[@"Result"] isEqual:@"late"] && rcBatteryDropRate(last()) == nil);
        CHECK(recorder.timer != nil && ![recorder.state[@"Completed"] boolValue]);
        config(NO, NO, 180, 240, epoch); CHECK(recorder.timer == nil);

        // Restarting the SpringBoard recorder never completes an interrupted sample.
        command(@"start"); recorder = [RCBatteryRecorder new]; [recorder refresh];
        CHECK([last()[@"Result"] isEqual:@"interrupted"] && recorder.state[@"Active"] == nil);
        failTimer = YES; now = epoch; config(YES, NO, 180, 240, epoch);
        CHECK([recorder.state[@"State"] isEqual:@"timerFailed"] && recorder.timer == nil);
        CHECK([last()[@"Result"] isEqual:@"timerFailed"]);
        CHECK(rcBatteryReadState(testRoot) != nil);
        failTimer = NO;
        config(NO, NO, 180, 240, epoch);
        command(@"start");
        NSUInteger beforeBusy = samples;
        config(YES, NO, 180, 240, epoch);
        CHECK([last()[@"Result"] isEqual:@"busy"] && samples == beforeBusy);
        CHECK([recorder.state[@"Active"][@"Source"] isEqual:@"manual"]);
        now = [now dateByAddingTimeInterval:1800]; command(@"stop");
        CHECK([last()[@"Result"] isEqual:@"complete"]);
        now = epoch; config(YES, YES, 180, 240, epoch);
        config(NO, NO, 180, 240, epoch);
        CHECK([last()[@"Result"] isEqual:@"cancelled"] && recorder.timer == nil);
        CHECK(last()[@"End"] != nil && recorder.state[@"NextStart"] == nil);
        CHECK([recorder.state[@"RecordEndedByStop"] isEqual:recorder.state[@"Revision"]]);
        now = [epoch dateByAddingTimeInterval:86400]; [recorder refresh];
        CHECK(!recorder.state[@"Active"] && !recorder.timer);
        for (NSUInteger index = 0; index < 65; index++)
            [recorder archive:[@{@"ID": NSUUID.UUID.UUIDString} mutableCopy] result:@"missed"];
        CHECK([recorder.state[@"History"] count] == 60);
        [recorder publish]; CHECK(rcBatteryReadState(testRoot) != nil);
        CHECK(!rcBatterySnapshotValid(@{@"Level": @-1}));
        CHECK(rcBatteryDropRate(@{@"Result": @"complete", @"Start": @[], @"End": @[]}) == nil);
        [NSTimeZone setDefaultTimeZone:[NSTimeZone timeZoneWithName:@"America/Los_Angeles"]];
        NSCalendar *dstCalendar = rcLowPowerLocalCalendar();
        NSDateComponents *gap = [NSDateComponents new]; gap.year = 2030; gap.month = 3; gap.day = 10; gap.hour = 3;
        CHECK(rcBatteryEndDate(@{@"StartMinute": @135, @"EndMinute": @165}, [dstCalendar dateFromComponents:gap]) == nil);
        NSLog(@"Battery recorder production state-machine checks passed");
    }
    return 0;
}
