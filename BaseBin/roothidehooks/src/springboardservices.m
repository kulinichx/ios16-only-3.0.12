#import "RCScheduleRuntime.h"
#include <TargetConditionals.h>
#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#else
// The Foundation harness supplies the lifecycle notification on macOS.
extern NSNotificationName const UIApplicationDidFinishLaunchingNotification;
#endif

extern void rcLowPowerScheduleStart(void);
extern void rcLowPowerScheduleRefresh(void);
extern void rcBatteryRecordStart(void);
extern void rcBatteryRecordRefresh(void);

void rcScheduleServicesStartAfterLaunch(void)
{
    // systemhook loads this dylib during SpringBoard's constructors. At that
    // point only observe UIKit launch; do not restore plans or open their files.
    static dispatch_once_t observeOnce;
    dispatch_once(&observeOnce, ^{
        static id observer;
        observer = [NSNotificationCenter.defaultCenter
            addObserverForName:UIApplicationDidFinishLaunchingNotification object:nil
            queue:nil usingBlock:^(__unused NSNotification *notification) {
                [NSNotificationCenter.defaultCenter removeObserver:observer];
                observer = nil;
                // Leave the launch notification stack before starting services.
                dispatch_async(dispatch_get_main_queue(), ^{
                    static dispatch_once_t startOnce;
                    dispatch_once(&startOnce, ^{
                        rcLowPowerScheduleStart();
                        rcBatteryRecordStart();
                        // Set up both objects before a power event can sample the
                        // recorder. Restore the power plan once, then recording.
                        rcLowPowerScheduleRefresh();
                        rcBatteryRecordRefresh();
                    });
                });
            }];
    });
}
