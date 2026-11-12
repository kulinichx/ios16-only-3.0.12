#pragma once

#import "DOSupporterLicense.h"
#import <objc/runtime.h>

// Display-only snapshot. Protected actions must still call IsVerified directly.
static inline BOOL DORHSupporterRenderIsVerified(void)
{
    @synchronized (NSUserDefaults.class) {
        const void *key = (const void *)NSSelectorFromString(@"dorh_supporterRenderAuthorizationState");
        NSMutableDictionary *state = objc_getAssociatedObject(NSUserDefaults.class, key);
        if (!state) {
            state = [NSMutableDictionary dictionary];
            objc_setAssociatedObject(NSUserDefaults.class, key, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            NSMutableArray *observers = [NSMutableArray array];
            for (NSString *name in @[DORHSupporterLicenseDidChangeNotification,
                                     UIApplicationWillResignActiveNotification, UIApplicationDidBecomeActiveNotification]) {
                id observer = [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:nil
                    usingBlock:^(__unused NSNotification *notification) {
                    @synchronized (NSUserDefaults.class) {
                        [state removeObjectForKey:@"verified"];
                    }
                }];
                [observers addObject:observer];
            }
            state[@"observers"] = observers;
        }
        NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
        // Bound staleness even if the external state changes without a notification.
        if (!state[@"verified"] || now - [state[@"checkedAt"] doubleValue] >= 1.0) {
            state[@"verified"] = @(DORHSupporterIsVerified());
            state[@"checkedAt"] = @(now);
        }
        return [state[@"verified"] boolValue];
    }
}
