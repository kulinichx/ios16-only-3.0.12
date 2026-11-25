#pragma once
#import <Foundation/Foundation.h>

// These helpers are only for the injected SpringBoard services, not the app.
NSString *rcScheduleRuntimeRoot(void);
dispatch_queue_t rcScheduleIOQueue(void);
void rcSchedulePublishDictionary(NSDictionary *dictionary, NSString *path,
    const char *notification, void (^completion)(BOOL success, NSError *error));
void rcScheduleServicesStartAfterLaunch(void);
