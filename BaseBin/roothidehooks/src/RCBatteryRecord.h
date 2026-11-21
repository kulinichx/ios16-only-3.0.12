#pragma once
#import "RCLowPowerSchedule.h"
#include <math.h>

#define RC_BATTERY_CHANGED "com.dopaminerh.rc9.battery-record.changed"
#define RC_BATTERY_QUERY "com.dopaminerh.rc9.battery-record.query"
#define RC_BATTERY_STATUS "com.dopaminerh.rc9.battery-record.status"

static inline NSString *rcBatteryPath(NSString *root, NSString *suffix)
{
    NSString *base = rcLowPowerConfigurationPath(root);
    return base ? [[base.stringByDeletingLastPathComponent stringByAppendingPathComponent:
        @"com.dopaminerh.rc9.battery-record"] stringByAppendingString:suffix] : nil;
}

static inline NSDictionary *rcBatteryDefaultConfiguration(void)
{
    NSMutableDictionary *value = [rcLowPowerDefaultConfiguration() mutableCopy];
    value[@"Repeat"] = @NO;
    value[@"FirstStart"] = [NSDate distantFuture];
    return value;
}

static inline BOOL rcBatteryConfigurationValid(id value)
{
    return rcLowPowerConfigurationValid(value) &&
        [value[@"Repeat"] isKindOfClass:NSNumber.class] &&
        CFGetTypeID((__bridge CFTypeRef)value[@"Repeat"]) == CFBooleanGetTypeID() &&
        [value[@"FirstStart"] isKindOfClass:NSDate.class];
}

static inline BOOL rcBatterySnapshotValid(id point)
{
    if (![point isKindOfClass:NSDictionary.class] || ![point[@"Date"] isKindOfClass:NSDate.class] ||
        ![point[@"Boot"] isKindOfClass:NSString.class]) return NO;
    for (NSString *key in @[@"Continuous", @"Level", @"BatteryState", @"LowPower", @"Thermal"])
        if (![point[key] isKindOfClass:NSNumber.class]) return NO;
    return isfinite([point[@"Level"] doubleValue]) && [point[@"Level"] doubleValue] >= 0 &&
        [point[@"Level"] doubleValue] <= 100 && isfinite([point[@"Continuous"] doubleValue]);
}

static inline BOOL rcBatteryRecordValid(id row)
{
    if (![row isKindOfClass:NSDictionary.class] || ![row[@"ID"] isKindOfClass:NSString.class]) return NO;
    for (NSString *key in @[@"Start", @"End"])
        if (row[key] && !rcBatterySnapshotValid(row[key])) return NO;
    for (NSString *key in @[@"PlannedStart", @"PlannedEnd", @"Recorded"])
        if (row[key] && ![row[key] isKindOfClass:NSDate.class]) return NO;
    return YES;
}

static inline NSDictionary *rcBatteryReadState(NSString *root)
{
    NSString *path = rcScheduleReadPath(rcBatteryPath(root, @".state"));
    if (!path) return nil;
    NSDictionary *attributes = [NSFileManager.defaultManager attributesOfItemAtPath:path error:nil];
    if (![attributes[NSFileType] isEqual:NSFileTypeRegular] ||
        [attributes[NSFileSize] unsignedLongLongValue] > 262144) return nil;
    NSData *data = [NSData dataWithContentsOfFile:path];
    id value = data ? [NSPropertyListSerialization propertyListWithData:data options:0 format:nil error:nil] : nil;
    if (![value isKindOfClass:NSDictionary.class] || ![value[@"History"] isKindOfClass:NSArray.class] ||
        [value[@"History"] count] > 60) return nil;
    for (id row in value[@"History"]) {
        if (!rcBatteryRecordValid(row) || ![row[@"Result"] isKindOfClass:NSString.class]) return nil;
    }
    if (value[@"Active"] && (!rcBatteryRecordValid(value[@"Active"]) ||
        !rcBatterySnapshotValid(value[@"Active"][@"Start"]) ||
        ![@[@"manual", @"scheduled"] containsObject:value[@"Active"][@"Source"]])) return nil;
    if (value[@"NextStart"] && ![value[@"NextStart"] isKindOfClass:NSDate.class]) return nil;
    if (value[@"Completed"] && ![value[@"Completed"] isKindOfClass:NSNumber.class]) return nil;
    return value;
}

// Rates are meaningful only for complete, non-charging endpoint observations.
// This never claims that the device remained locked or unplugged between them.
static inline NSNumber *rcBatteryDropRate(NSDictionary *record)
{
    if (![record[@"Result"] isEqual:@"complete"]) return nil;
    NSDictionary *a = record[@"Start"], *b = record[@"End"];
    if (!rcBatterySnapshotValid(a) || !rcBatterySnapshotValid(b)) return nil;
    for (NSDictionary *point in @[a, b]) {
        if (![point[@"Level"] isKindOfClass:NSNumber.class] ||
            ![point[@"Continuous"] isKindOfClass:NSNumber.class] ||
            ![point[@"BatteryState"] isEqual:@1]) return nil;
        double level = [point[@"Level"] doubleValue];
        if (!isfinite(level) || level < 0 || level > 100) return nil;
    }
    double seconds = [b[@"Continuous"] doubleValue] - [a[@"Continuous"] doubleValue];
    double drop = [a[@"Level"] doubleValue] - [b[@"Level"] doubleValue];
    if (!isfinite(seconds) || seconds < 60 || drop < 0 || ![a[@"Boot"] isEqual:b[@"Boot"]]) return nil;
    return @(drop * 3600.0 / seconds);
}

static inline NSDate *rcBatteryEndDate(NSDictionary *configuration, NSDate *start)
{
    NSCalendar *calendar = rcLowPowerLocalCalendar();
    NSDate *day = [calendar startOfDayForDate:start];
    NSInteger startMinute = [configuration[@"StartMinute"] integerValue];
    NSInteger endMinute = [configuration[@"EndMinute"] integerValue];
    if (endMinute < startMinute) day = [calendar dateByAddingUnit:NSCalendarUnitDay value:1 toDate:day options:0];
    NSDate *end = rcLowPowerDateForMinute(endMinute, [day dateByAddingTimeInterval:-0.001], calendar, YES);
    // Two missing DST times may both normalize to the same instant. Skip that
    // window instead of accidentally turning it into an almost 24-hour record.
    return end && [end compare:start] == NSOrderedDescending ? end : nil;
}
