#import "RCLowPowerSchedule.h"
#import <objc/runtime.h>
#include <dlfcn.h>
#include <notify.h>
#include <os/log.h>
#include <string.h>
#include <sys/sysctl.h>
#include <sys/time.h>
#ifndef RC_LOW_POWER_TEST
#include <libjailbreak/jbclient_xpc.h>
#else
extern const char *jbclient_get_jbroot(void);
extern NSDate *rcLowPowerTestNow(void);
extern NSString *rcLowPowerTestBootSession(void);
#endif

@protocol RCLowPowerModeAPI <NSObject>
+ (instancetype)sharedInstance;
- (void)setPowerMode:(NSInteger)mode fromSource:(NSString *)source;
@end

@protocol RCPersistentTimerAPI <NSObject>
- (instancetype)initWithFireDate:(NSDate *)date serviceIdentifier:(NSString *)identifier
                         target:(id)target selector:(SEL)selector userInfo:(id)userInfo;
- (void)setDisableSystemWaking:(BOOL)value;
- (void)setUserVisible:(BOOL)value;
- (void)setMinimumEarlyFireProportion:(double)value;
- (void)setEarlyFireConstantInterval:(double)value;
- (void)scheduleInRunLoop:(NSRunLoop *)runLoop;
- (void)invalidate;
- (BOOL)isValid;
@end

static BOOL rcLowPowerMethodMatches(Method method, const char *returns, const char *arguments)
{
    if (!method || !method_getTypeEncoding(method)) return NO;
    NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
    if (signature.numberOfArguments != strlen(arguments) + 2 ||
        !strchr(returns, signature.methodReturnType[0])) return NO;
    for (NSUInteger index = 0; index < strlen(arguments); index++) {
        char type = [signature getArgumentTypeAtIndex:index + 2][0];
        if (arguments[index] == 'b' ? !strchr("Bc", type) : type != arguments[index]) return NO;
    }
    return YES;
}

static BOOL rcPowerSetterMatches(Class power)
{
    return rcLowPowerMethodMatches(class_getClassMethod(power, @selector(sharedInstance)), "@", "") &&
        rcLowPowerMethodMatches(class_getInstanceMethod(power, @selector(setPowerMode:fromSource:)), "vBc", "q@");
}

static BOOL rcSubmitPowerMode(id<RCLowPowerModeAPI> power, NSInteger mode)
{
    SEL selector = @selector(setPowerMode:fromSource:);
    Method setter = class_getInstanceMethod(object_getClass(power), selector);
    if (!rcLowPowerMethodMatches(setter, "vBc", "q@")) return NO;
    NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(setter)];
    NSString *source = @"SpringBoard";
    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
    invocation.selector = selector;
    [invocation setArgument:&mode atIndex:2];
    [invocation setArgument:&source atIndex:3];
    [invocation invokeWithTarget:power];
    if (signature.methodReturnLength == 0) return YES;
    unsigned char accepted = 0;
    [invocation getReturnValue:&accepted];
    return accepted != 0;
}

static BOOL rcPowerSetterAvailable(void)
{
    return rcPowerSetterMatches(NSClassFromString(@"_PMLowPowerMode"));
}

static BOOL rcLowPowerAPIsAvailable(void)
{
    Class timer = NSClassFromString(@"PCPersistentTimer");
    return rcLowPowerMethodMatches(class_getInstanceMethod(timer,
            @selector(initWithFireDate:serviceIdentifier:target:selector:userInfo:)), "@", "@@@:@") &&
        rcLowPowerMethodMatches(class_getInstanceMethod(timer, @selector(setDisableSystemWaking:)), "v", "b") &&
        rcLowPowerMethodMatches(class_getInstanceMethod(timer, @selector(setMinimumEarlyFireProportion:)), "v", "d") &&
        rcLowPowerMethodMatches(class_getInstanceMethod(timer, @selector(setEarlyFireConstantInterval:)), "v", "d") &&
        rcLowPowerMethodMatches(class_getInstanceMethod(timer, @selector(scheduleInRunLoop:)), "v", "@") &&
        rcLowPowerMethodMatches(class_getInstanceMethod(timer, @selector(invalidate)), "v", "") &&
        rcLowPowerMethodMatches(class_getInstanceMethod(timer, @selector(isValid)), "Bc", "");
}

static NSString *rcLowPowerRoot(void)
{
    const char *root = jbclient_get_jbroot();
    return root && root[0] == '/' ? [NSString stringWithUTF8String:root] : nil;
}

static NSDate *rcLowPowerNow(void)
{
#ifdef RC_LOW_POWER_TEST
    return rcLowPowerTestNow();
#else
    return NSDate.date;
#endif
}

static NSString *rcLowPowerBootSession(void)
{
#ifdef RC_LOW_POWER_TEST
    return rcLowPowerTestBootSession();
#else
    static NSString *session;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        struct timeval bootTime = {0};
        size_t length = sizeof(bootTime);
        if (sysctlbyname("kern.boottime", &bootTime, &length, NULL, 0) == 0 &&
            length == sizeof(bootTime) && bootTime.tv_sec > 0)
            session = [NSString stringWithFormat:@"%lld.%d",
                (long long)bootTime.tv_sec, (int)bootTime.tv_usec];
    });
    return session;
#endif
}

#ifndef RC_LOW_POWER_TEST
extern void rcBatteryRecordBeforePowerChange(void);
extern void rcBatteryRecordAfterPowerChange(void);
#endif
static id rcSharedLowPowerScheduler;

@interface RCLowPowerScheduler : NSObject
@property(nonatomic, strong) id<RCPersistentTimerAPI> timer;
@property(nonatomic, copy) NSDictionary *lastHandled;
@property(nonatomic, copy) NSString *disableRequest;
@property(nonatomic, copy) NSString *disableState;
@property(nonatomic) BOOL awaitingReadback;
@property(nonatomic) NSUInteger disableAttempts;
@property(nonatomic, strong) NSDictionary *readbackEvent;
@property(nonatomic) BOOL awaitingEventReadback;
@property(nonatomic, copy) NSString *retryKey;
@property(nonatomic) NSUInteger retryCount;
@property(nonatomic, strong) NSDate *retryAfter;
- (void)refresh;
- (void)timerFired:(id)timer;
@end

@implementation RCLowPowerScheduler

- (void)publishStatus:(NSString *)state configuration:(NSDictionary *)configuration
                root:(NSString *)root next:(NSDictionary *)next
{
    NSMutableDictionary *status = [@{@"State": state, @"Updated": rcLowPowerNow()} mutableCopy];
    if (configuration[@"Revision"]) status[@"Revision"] = configuration[@"Revision"];
    if (next) status[@"Next"] = next;
    if (self.lastHandled) status[@"LastHandled"] = self.lastHandled;
    if (self.disableRequest) status[@"DisableRequest"] = self.disableRequest;
    NSString *bootSession = rcLowPowerBootSession();
    if (bootSession) status[@"BootSession"] = bootSession;
    NSError *error = nil;
    if (rcLowPowerWriteDictionary(status, rcLowPowerStatusPath(root), &error)) {
        notify_post(RC_LOW_POWER_STATUS_CHANGED);
    } else {
        os_log_error(OS_LOG_DEFAULT, "Dopamine low power schedule could not publish %{public}@: %{public}@ (%ld)",
            state, error.domain, (long)error.code);
    }
}

- (BOOL)armForDate:(NSDate *)date
{
    id<RCPersistentTimerAPI> timer = [(id<RCPersistentTimerAPI>)[NSClassFromString(@"PCPersistentTimer") alloc]
        initWithFireDate:date serviceIdentifier:@"com.dopaminerh.rc9.low-power-schedule"
        target:self selector:@selector(timerFired:) userInfo:nil];
    if (!timer) return NO;
    [timer setDisableSystemWaking:NO];
    if (rcLowPowerMethodMatches(class_getInstanceMethod([timer class], @selector(setUserVisible:)), "v", "b"))
        [timer setUserVisible:YES];
    [timer setMinimumEarlyFireProportion:0.0];
    [timer setEarlyFireConstantInterval:0.0];
    [timer scheduleInRunLoop:NSRunLoop.mainRunLoop];
    if ([timer isValid]) {
        [self.timer invalidate];
        self.timer = timer;
        return YES;
    }
    [timer invalidate];
    return NO;
}

- (void)timerFired:(id)timer
{
    if (timer == self.timer) [self refresh];
}

- (BOOL)systemLowPowerEnabled { return NSProcessInfo.processInfo.lowPowerModeEnabled; }

- (BOOL)configurationIsCurrent:(NSDictionary *)configuration root:(NSString *)root
{
    NSDictionary *latest = rcLowPowerReadDictionary(rcLowPowerConfigurationPath(root));
    return [latest isEqualToDictionary:configuration];
}

- (BOOL)requestPowerMode:(BOOL)enabled
{
    if (!rcPowerSetterAvailable()) return NO;
    id<RCLowPowerModeAPI> power = [(Class<RCLowPowerModeAPI>)NSClassFromString(@"_PMLowPowerMode") sharedInstance];
    if (!power) return NO;
#ifndef RC_LOW_POWER_TEST
    rcBatteryRecordBeforePowerChange();
#endif
    // A completed invocation still requires delayed system readback.
    BOOL submitted = rcSubmitPowerMode(power, enabled ? 1 : 0);
#ifndef RC_LOW_POWER_TEST
    rcBatteryRecordAfterPowerChange();
#endif
    return submitted;
}

- (BOOL)requestPowerOff
{
    static dispatch_once_t once;
    dispatch_once(&once, ^{ dlopen("/System/Library/PrivateFrameworks/LowPowerMode.framework/LowPowerMode", RTLD_LAZY | RTLD_LOCAL); });
    return [self requestPowerMode:NO];
}

- (void)disableWithConfiguration:(NSDictionary *)configuration root:(NSString *)root
{
    NSString *request = configuration[@"DisableRequest"];
    if (![request isKindOfClass:NSString.class]) {
        self.disableRequest = nil;
        self.disableState = nil;
        self.awaitingReadback = NO;
        [self publishStatus:@"disabled" configuration:configuration root:root next:nil];
        return;
    }
    if (![request isEqual:self.disableRequest]) {
        NSDictionary *saved = rcLowPowerReadDictionary(rcLowPowerStatusPath(root));
        self.disableRequest = request;
        self.disableAttempts = 0;
        self.awaitingReadback = NO;
        NSString *state = [saved[@"DisableRequest"] isEqual:request] &&
            [saved[@"BootSession"] isEqual:rcLowPowerBootSession()] ? saved[@"State"] : nil;
        self.disableState = [@[@"disabled", @"applyFailed"] containsObject:state ?: @""] ? state : nil;
        // An interrupted verification has no completion to reuse after a respring.
    }
    if ([self.disableState isEqual:@"verifying"] && !self.awaitingReadback) {
        if (!self.systemLowPowerEnabled) self.disableState = @"disabled";
        else if (self.disableAttempts >= 3) self.disableState = @"applyFailed";
    }
    if (!self.awaitingReadback && ![@[@"disabled", @"applyFailed"] containsObject:self.disableState ?: @""]) {
        if (![self configurationIsCurrent:configuration root:root]) return;
        // Send OFF even when readback is already off: an earlier ON can still be in flight.
        [self requestPowerOff];
        self.disableAttempts++;
        self.disableState = @"verifying";
        self.awaitingReadback = YES;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            if (![request isEqual:self.disableRequest]) return;
            self.awaitingReadback = NO;
            [self refresh];
        });
    }
    [self publishStatus:self.disableState configuration:configuration root:root next:nil];
}

- (NSString *)applyEvent:(NSDictionary *)event configuration:(NSDictionary *)configuration
                   root:(NSString *)root now:(NSDate *)now
{
    if ([self.lastHandled isEqual:event]) return @"scheduled";
    NSString *key = [NSString stringWithFormat:@"%@:%@:%@", event[@"Revision"], event[@"Date"], event[@"PowerMode"]];
    if (![self.retryKey isEqual:key]) {
        self.retryKey = key;
        self.retryCount = 0;
        self.retryAfter = nil;
        self.readbackEvent = nil;
        self.awaitingEventReadback = NO;
    }
    BOOL target = [event[@"PowerMode"] boolValue];
    if (self.readbackEvent) {
        if (self.awaitingEventReadback) return @"verifying";
        self.readbackEvent = nil;
        self.awaitingEventReadback = NO;
        if (self.systemLowPowerEnabled == target) {
            self.lastHandled = event;
            self.retryAfter = nil;
            return @"scheduled";
        }
        self.retryAfter = [now dateByAddingTimeInterval:60.0 * self.retryCount];
    }
    if (self.retryCount >= 4 || (self.retryAfter && [now compare:self.retryAfter] == NSOrderedAscending))
        return @"applyFailed";
    // A save from the app can supersede this callback while it is arming its timer.
    if (![self configurationIsCurrent:configuration root:root]) return nil;
    self.retryCount++;
    if (![self requestPowerMode:target] && self.systemLowPowerEnabled != target) {
        self.retryAfter = [now dateByAddingTimeInterval:60.0 * self.retryCount];
        return @"applyFailed";
    }
    self.retryAfter = nil;
    self.readbackEvent = event;
    self.awaitingEventReadback = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if (self.readbackEvent != event) return;
        self.awaitingEventReadback = NO;
        [self refresh];
    });
    return @"verifying";
}

- (void)refresh
{
    // All entry points run on SpringBoard's main queue; disabling cannot race an
    // already queued callback into applying a stale configuration.
    [self.timer invalidate];
    self.timer = nil;
    NSString *root = rcLowPowerRoot();
    if (!root) {
        os_log_error(OS_LOG_DEFAULT, "Dopamine low power schedule could not locate the active RootHide environment");
        return;
    }
    NSDictionary *configuration = rcLowPowerReadDictionary(rcLowPowerConfigurationPath(root));
    if (!configuration) {
        BOOL exists = [NSFileManager.defaultManager fileExistsAtPath:rcScheduleReadPath(rcLowPowerConfigurationPath(root))];
        [self publishStatus:exists ? @"invalidConfiguration" : @"disabled"
              configuration:nil root:root next:nil];
        return;
    }
    if (!rcLowPowerConfigurationValid(configuration)) {
        [self publishStatus:@"invalidConfiguration" configuration:nil root:root next:nil];
        return;
    }
    if (![configuration[@"Enabled"] boolValue]) {
        self.retryKey = nil;
        self.retryCount = 0;
        self.retryAfter = nil;
        self.readbackEvent = nil;
        self.awaitingEventReadback = NO;
        @try { [self disableWithConfiguration:configuration root:root]; }
        @catch (__unused NSException *exception) {
            self.disableState = @"runtimeFailed";
            [self publishStatus:self.disableState configuration:configuration root:root next:nil];
        }
        return;
    }
    self.disableRequest = nil;
    self.disableState = nil;
    self.awaitingReadback = NO;
    @try {
        static dispatch_once_t frameworksOnce;
        dispatch_once(&frameworksOnce, ^{
            // Keep handles alive while cached Objective-C classes are in use.
            dlopen("/System/Library/PrivateFrameworks/LowPowerMode.framework/LowPowerMode", RTLD_LAZY | RTLD_LOCAL);
            dlopen("/System/Library/PrivateFrameworks/PersistentConnection.framework/PersistentConnection", RTLD_LAZY | RTLD_LOCAL);
        });
        if (!rcPowerSetterAvailable()) {
            os_log_error(OS_LOG_DEFAULT, "Dopamine low power schedule system setter unavailable");
            [self publishStatus:@"unsupported" configuration:configuration root:root next:nil];
            return;
        }
        if (!rcLowPowerAPIsAvailable()) {
            os_log_error(OS_LOG_DEFAULT, "Dopamine low power schedule persistent timer API unavailable");
            [self publishStatus:@"timerFailed" configuration:configuration root:root next:nil];
            return;
        }
        NSDate *now = rcLowPowerNow();
        NSCalendar *calendar = rcLowPowerLocalCalendar();
        NSDictionary *previous = rcLowPowerEvent(configuration, now, calendar, NO);
        NSDictionary *next = rcLowPowerNextScheduledEvent(configuration, now, calendar);
        if (!previous || !next) {
            [self publishStatus:@"calendarFailed" configuration:configuration root:root next:nil];
            return;
        }
        NSDictionary *event = @{@"Revision": configuration[@"Revision"],
            @"Date": previous[@"Date"], @"PowerMode": previous[@"PowerMode"]};
        // Do not enable a mode if its corresponding OFF event cannot be armed.
        if (![self armForDate:next[@"Date"]]) {
            [self publishStatus:@"timerFailed" configuration:configuration root:root next:next];
            return;
        }
        if (rcLowPowerEventIsDeferred(configuration, previous)) {
            [self publishStatus:@"scheduled" configuration:configuration root:root next:next];
            return;
        }
        if (!self.lastHandled) {
            NSDictionary *saved = rcLowPowerReadDictionary(rcLowPowerStatusPath(root));
            // Preserve manual overrides across a respring, but catch up after
            // a full reboot that may have reset the system's power-mode state.
            NSString *bootSession = rcLowPowerBootSession();
            if (bootSession && [saved[@"BootSession"] isEqual:bootSession] &&
                [saved[@"LastHandled"] isKindOfClass:NSDictionary.class])
                self.lastHandled = saved[@"LastHandled"];
        }
        NSString *state = [self applyEvent:event configuration:configuration root:root now:now];
        if (!state) return;
        // Retry before the next edge only. The OFF timer stays armed during readback.
        if ([state isEqual:@"applyFailed"] && self.retryCount < 4 && self.retryAfter &&
            [self.retryAfter compare:next[@"Date"]] == NSOrderedAscending)
            [self armForDate:self.retryAfter];
        [self publishStatus:state configuration:configuration root:root next:next];
    }
    @catch (__unused NSException *exception) {
        [self.timer invalidate];
        self.timer = nil;
        [self publishStatus:@"runtimeFailed" configuration:configuration root:root next:nil];
    }
}
@end

void rcLowPowerScheduleRefresh(void) { [rcSharedLowPowerScheduler refresh]; }

void rcLowPowerScheduleStart(void)
{
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        static RCLowPowerScheduler *scheduler;
        scheduler = [RCLowPowerScheduler new];
        rcSharedLowPowerScheduler = scheduler;
        int changeToken, queryToken;
        notify_register_dispatch(RC_LOW_POWER_CHANGED, &changeToken, dispatch_get_main_queue(),
            ^(__unused int token) { [scheduler refresh]; });
        notify_register_dispatch(RC_LOW_POWER_QUERY, &queryToken, dispatch_get_main_queue(),
            ^(__unused int token) { [scheduler refresh]; });
        for (NSString *name in @[NSSystemClockDidChangeNotification, NSSystemTimeZoneDidChangeNotification]) {
            [NSNotificationCenter.defaultCenter addObserverForName:name object:nil
                queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *notification) {
                    [scheduler refresh];
                }];
        }
        dispatch_async(dispatch_get_main_queue(), ^{ [scheduler refresh]; });
    });
}
