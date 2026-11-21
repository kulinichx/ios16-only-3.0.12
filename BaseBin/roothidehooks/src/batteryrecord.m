#import "RCBatteryRecord.h"
#ifndef RC_BATTERY_TEST
#import <UIKit/UIKit.h>
#endif
#import <objc/runtime.h>
#include <dlfcn.h>
#include <notify.h>
#include <sys/sysctl.h>
#include <mach/mach_time.h>
#include <string.h>
#ifndef RC_BATTERY_TEST
#include <libjailbreak/jbclient_xpc.h>
#else
extern const char *jbclient_get_jbroot(void);
extern NSDate *rcBatteryTestNow(void);
extern NSDictionary *rcBatteryTestSnapshot(void);
#endif

static NSDate *rcBatteryNow(void)
{
#ifdef RC_BATTERY_TEST
    return rcBatteryTestNow();
#else
    return NSDate.date;
#endif
}

@protocol RCBatteryTimerAPI <NSObject>
- (instancetype)initWithFireDate:(NSDate *)date serviceIdentifier:(NSString *)identifier target:(id)target selector:(SEL)selector userInfo:(id)info;
- (void)setDisableSystemWaking:(BOOL)value;
- (void)setUserVisible:(BOOL)value;
- (void)setMinimumEarlyFireProportion:(double)value;
- (void)setEarlyFireConstantInterval:(double)value;
- (void)scheduleInRunLoop:(NSRunLoop *)runLoop;
- (void)invalidate;
- (BOOL)isValid;
@end

extern void rcLowPowerScheduleRefresh(void);

static BOOL rcBatteryTimerMethod(Class cls, SEL selector, const char *returns, const char *arguments)
{
    Method method = class_getInstanceMethod(cls, selector);
    if (!method) return NO;
    NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
    if (signature.numberOfArguments != strlen(arguments) + 2 || !strchr(returns, signature.methodReturnType[0])) return NO;
    for (NSUInteger index = 0; index < strlen(arguments); index++) {
        char type = [signature getArgumentTypeAtIndex:index + 2][0];
        if (arguments[index] == 'b' ? !strchr("Bc", type) : type != arguments[index]) return NO;
    }
    return YES;
}

static NSString *rcBatteryRoot(void)
{
    const char *root = jbclient_get_jbroot();
    return root && root[0] == '/' ? [NSString stringWithUTF8String:root] : nil;
}

#ifndef RC_BATTERY_TEST
static NSString *rcBatteryBoot(void)
{
    char session[128] = {0};
    size_t size = sizeof(session);
    return sysctlbyname("kern.bootsessionuuid", session, &size, NULL, 0) == 0 ?
        [NSString stringWithUTF8String:session] : nil;
}
#endif

static NSDictionary *rcBatterySnapshot(void)
{
#ifdef RC_BATTERY_TEST
    return rcBatteryTestSnapshot();
#else
    UIDevice *device = UIDevice.currentDevice;
    BOOL wasMonitoring = device.batteryMonitoringEnabled;
    device.batteryMonitoringEnabled = YES;
    float level = device.batteryLevel;
    UIDeviceBatteryState state = device.batteryState;
    device.batteryMonitoringEnabled = wasMonitoring;
    mach_timebase_info_data_t timebase;
    mach_timebase_info(&timebase);
    NSString *boot = rcBatteryBoot();
    // Unavailable readings stay unavailable; never synthesize a battery percentage.
    if (!isfinite(level) || level < 0 || level > 1 || state == UIDeviceBatteryStateUnknown || !boot || !timebase.denom) return nil;
    double seconds = (double)mach_continuous_time() * timebase.numer / timebase.denom / NSEC_PER_SEC;
    return @{@"Date": NSDate.date, @"Continuous": @(seconds), @"Boot": boot,
        @"Level": @(round(level * 100.0)), @"BatteryState": @(state),
        @"LowPower": @(NSProcessInfo.processInfo.lowPowerModeEnabled),
        @"Thermal": @(NSProcessInfo.processInfo.thermalState)};
#endif
}

@interface RCBatteryRecorder : NSObject
@property(nonatomic, strong) id<RCBatteryTimerAPI> timer;
@property(nonatomic, strong) NSMutableDictionary *state;
@property(nonatomic) BOOL refreshing;
- (void)refresh;
- (void)refreshRecords;
- (void)finishDueRecord;
@end

static RCBatteryRecorder *recorder;
@implementation RCBatteryRecorder

- (void)archive:(NSMutableDictionary *)record result:(NSString *)result
{
    record[@"Result"] = result;
    record[@"Recorded"] = rcBatteryNow();
    NSMutableArray *history = [self.state[@"History"] mutableCopy] ?: [NSMutableArray new];
    [history insertObject:record atIndex:0];
    if (history.count > 60) [history removeObjectsInRange:NSMakeRange(60, history.count - 60)];
    self.state[@"History"] = history;
}

- (void)finishActive:(NSString *)result sample:(BOOL)sample
{
    NSMutableDictionary *active = [self.state[@"Active"] mutableCopy];
    if (!active) return;
    NSDictionary *point = sample ? rcBatterySnapshot() : nil;
    if (point) active[@"End"] = point;
    if (sample && !point) result = @"sampleFailed";
    if (point && ![point[@"Boot"] isEqual:active[@"Start"][@"Boot"]]) result = @"interrupted";
    if (point && [result isEqual:@"complete"]) {
        double elapsed = [point[@"Continuous"] doubleValue] - [active[@"Start"][@"Continuous"] doubleValue];
        double wall = [point[@"Date"] timeIntervalSinceDate:active[@"Start"][@"Date"]];
        if (elapsed < 0 || fabs(wall - elapsed) > 120) result = @"clockChanged";
    }
    [self archive:active result:result];
    [self.state removeObjectForKey:@"Active"];
}

- (void)finishDueRecord
{
    NSDictionary *active = self.state[@"Active"];
    NSDate *end = active[@"PlannedEnd"];
    if ([end isKindOfClass:NSDate.class] && [end timeIntervalSinceDate:rcBatteryNow()] <= 0)
        [self finishActive:[end timeIntervalSinceDate:rcBatteryNow()] < -120 ? @"late" : @"complete" sample:YES];
}

- (void)publish
{
    self.state[@"Updated"] = rcBatteryNow();
    if (rcLowPowerWriteDictionary(self.state, rcBatteryPath(rcBatteryRoot(), @".state"), nil))
        notify_post(RC_BATTERY_STATUS);
    else {
        // Stop rather than continue a measurement whose starting point was not saved.
        [self.timer invalidate];
        self.timer = nil;
    }
}

- (BOOL)arm:(NSDate *)date
{
    if (!date) return YES;
#ifndef RC_BATTERY_TEST
    static dispatch_once_t once;
    dispatch_once(&once, ^{ dlopen("/System/Library/PrivateFrameworks/PersistentConnection.framework/PersistentConnection", RTLD_LAZY | RTLD_LOCAL); });
#endif
    Class cls = NSClassFromString(@"PCPersistentTimer");
    if (!rcBatteryTimerMethod(cls, @selector(initWithFireDate:serviceIdentifier:target:selector:userInfo:), "@", "@@@:@") ||
        !rcBatteryTimerMethod(cls, @selector(setDisableSystemWaking:), "v", "b") ||
        !rcBatteryTimerMethod(cls, @selector(setUserVisible:), "v", "b") ||
        !rcBatteryTimerMethod(cls, @selector(setMinimumEarlyFireProportion:), "v", "d") ||
        !rcBatteryTimerMethod(cls, @selector(setEarlyFireConstantInterval:), "v", "d") ||
        !rcBatteryTimerMethod(cls, @selector(scheduleInRunLoop:), "v", "@") ||
        !rcBatteryTimerMethod(cls, @selector(invalidate), "v", "") ||
        !rcBatteryTimerMethod(cls, @selector(isValid), "Bc", "")) return NO;
    id<RCBatteryTimerAPI> timer = [(id<RCBatteryTimerAPI>)[cls alloc] initWithFireDate:date
        serviceIdentifier:@"com.dopaminerh.rc9.battery-record" target:self selector:@selector(timerFired:) userInfo:nil];
    [timer setDisableSystemWaking:NO];
    [timer setUserVisible:YES];
    [timer setMinimumEarlyFireProportion:0];
    [timer setEarlyFireConstantInterval:0];
    [timer scheduleInRunLoop:NSRunLoop.mainRunLoop];
    if (![timer isValid]) { [timer invalidate]; return NO; }
    self.timer = timer;
    return YES;
}

- (void)timerFired:(id)timer
{
    if (timer != self.timer) return;
    // The power scheduler calls finishDueRecord before changing power mode.
    // Its ON event therefore precedes the start snapshot, and OFF follows the end.
    rcLowPowerScheduleRefresh();
    [self refresh];
}

- (void)refresh
{
    if (self.refreshing) return;
    self.refreshing = YES;
    @try { [self refreshRecords]; }
    @catch (__unused NSException *exception) {
        [self.timer invalidate]; self.timer = nil;
        self.state[@"State"] = @"runtimeFailed";
        [self publish];
    }
    self.refreshing = NO;
}

- (void)refreshRecords
{
    [self.timer invalidate]; self.timer = nil;
    NSString *root = rcBatteryRoot();
    if (!root) return;
    if (!self.state) {
        self.state = [rcBatteryReadState(root) mutableCopy] ?: [@{@"History": @[]} mutableCopy];
        // A respring/reboot interrupts measurement continuity; preserve the endpoints we have.
        if (self.state[@"Active"]) [self finishActive:@"interrupted" sample:NO];
    }
    NSDictionary *config = rcLowPowerReadDictionary(rcBatteryPath(root, @".plist"));
    if (!rcBatteryConfigurationValid(config)) config = rcBatteryDefaultConfiguration();
    if (![self.state[@"Revision"] isEqual:config[@"Revision"]]) {
        BOOL stopping = ![config[@"Enabled"] boolValue] && config[@"DisableRequest"] != nil;
        if (stopping && self.state[@"Active"]) self.state[@"RecordEndedByStop"] = config[@"DisableRequest"];
        else if (![self.state[@"RecordEndedByStop"] isEqual:config[@"DisableRequest"]])
            [self.state removeObjectForKey:@"RecordEndedByStop"];
        if (stopping || [self.state[@"Active"][@"Source"] isEqual:@"scheduled"])
            [self finishActive:@"cancelled" sample:stopping];
        self.state[@"Revision"] = config[@"Revision"];
        self.state[@"NextStart"] = [config[@"Enabled"] boolValue] ? config[@"FirstStart"] : nil;
        [self.state removeObjectForKey:@"Completed"];
    }
    [self finishDueRecord];
    NSDictionary *command = rcLowPowerReadDictionary(rcBatteryPath(root, @".command"));
    if ([command[@"ID"] isKindOfClass:NSString.class] && ![self.state[@"CommandID"] isEqual:command[@"ID"]]) {
        self.state[@"CommandID"] = command[@"ID"];
        self.state[@"CommandResult"] = @"expired";
        NSDate *sent = command[@"Date"];
        if ([sent isKindOfClass:NSDate.class] && fabs([sent timeIntervalSinceDate:rcBatteryNow()]) <= 60) {
            NSString *action = command[@"Action"];
            if ([action isEqual:@"start"] && !self.state[@"Active"]) {
                NSDictionary *point = rcBatterySnapshot();
                if (point) {
                    self.state[@"Active"] = @{@"ID": command[@"ID"], @"Source": @"manual", @"Start": point};
                    self.state[@"CommandResult"] = @"started";
                } else self.state[@"CommandResult"] = @"sampleFailed";
            } else if ([action isEqual:@"stop"] && self.state[@"Active"]) {
                [self finishActive:@"complete" sample:YES];
                self.state[@"CommandResult"] = @"stopped";
            } else self.state[@"CommandResult"] = [action isEqual:@"stop"] ? @"noActive" : @"busy";
        }
    }
    BOOL enabled = [config[@"Enabled"] boolValue] && ![self.state[@"Completed"] boolValue];
    NSDate *start = self.state[@"NextStart"];
    if (enabled && [start isKindOfClass:NSDate.class] && [start timeIntervalSinceDate:rcBatteryNow()] <= 0) {
        NSDate *end = rcBatteryEndDate(config, start);
        NSMutableDictionary *record = [@{@"ID": NSUUID.UUID.UUIDString, @"Source": @"scheduled",
            @"PlannedStart": start, @"PlannedEnd": end ?: start} mutableCopy];
        NSString *result = nil;
        if (self.state[@"Active"]) result = @"busy";
        else if (!end || [end timeIntervalSinceDate:rcBatteryNow()] <= 0 || [start timeIntervalSinceDate:rcBatteryNow()] < -120) result = @"missed";
        else {
            NSDictionary *point = rcBatterySnapshot();
            if (point) { record[@"Start"] = point; self.state[@"Active"] = record; }
            else result = @"sampleFailed";
        }
        if (result) [self archive:record result:result];
        if ([config[@"Repeat"] boolValue]) {
            self.state[@"NextStart"] = rcLowPowerDateForMinute([config[@"StartMinute"] integerValue], rcBatteryNow(), rcLowPowerLocalCalendar(), YES);
        } else {
            self.state[@"Completed"] = @YES;
            enabled = NO;
        }
    }
    NSDate *next = enabled ? self.state[@"NextStart"] : nil;
    NSDate *end = self.state[@"Active"][@"PlannedEnd"];
    if (end && (!next || [end compare:next] == NSOrderedAscending)) next = end;
    self.state[@"State"] = self.state[@"Active"] ? @"recording" : (enabled ? @"scheduled" : @"idle");
    if (![self arm:next]) {
        self.state[@"State"] = @"timerFailed";
        if ([self.state[@"Active"][@"Source"] isEqual:@"scheduled"]) [self finishActive:@"timerFailed" sample:NO];
    }
    [self publish];
}
@end

void rcBatteryRecordBeforePowerChange(void)
{
    // Recording failures must never prevent an independently configured power event.
    @try { [recorder finishDueRecord]; }
    @catch (__unused NSException *exception) {
        [recorder.timer invalidate]; recorder.timer = nil;
        recorder.state[@"State"] = @"runtimeFailed";
    }
}
void rcBatteryRecordAfterPowerChange(void)
{
    // An unused recorder needs no extra status writes on every power-plan event.
    if (recorder.timer || recorder.state[@"Active"]) [recorder refresh];
}
void rcBatteryRecordStart(void)
{
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        recorder = [RCBatteryRecorder new];
        int changed, query;
        notify_register_dispatch(RC_BATTERY_CHANGED, &changed, dispatch_get_main_queue(), ^(int token) {
            rcLowPowerScheduleRefresh(); [recorder refresh];
        });
        notify_register_dispatch(RC_BATTERY_QUERY, &query, dispatch_get_main_queue(), ^(int token) {
            rcLowPowerScheduleRefresh(); [recorder refresh];
        });
        for (NSString *name in @[NSSystemClockDidChangeNotification, NSSystemTimeZoneDidChangeNotification])
            [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:NSOperationQueue.mainQueue
                usingBlock:^(NSNotification *notification) {
                    // Clock/zone edits invalidate the scheduled interval, never invent a replacement endpoint.
                    if ([recorder.state[@"Active"][@"Source"] isEqual:@"scheduled"]) [recorder finishActive:@"clockChanged" sample:NO];
                    NSDictionary *config = rcLowPowerReadDictionary(rcBatteryPath(rcBatteryRoot(), @".plist"));
                    if (rcBatteryConfigurationValid(config) && [config[@"Enabled"] boolValue] && ![recorder.state[@"Completed"] boolValue]) {
                        NSDate *next = rcLowPowerDateForMinute([config[@"StartMinute"] integerValue], rcBatteryNow(), rcLowPowerLocalCalendar(), YES);
                        if (next) recorder.state[@"NextStart"] = next;
                    }
                    rcLowPowerScheduleRefresh(); [recorder refresh];
                }];
        dispatch_async(dispatch_get_main_queue(), ^{ rcLowPowerScheduleRefresh(); [recorder refresh]; });
    });
}
