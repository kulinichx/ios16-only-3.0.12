#pragma once
#import <UIKit/UIKit.h>

static inline NSString *DOScheduleDateText(id value)
{
    if (![value isKindOfClass:NSDate.class]) return @"—";
    NSDateFormatter *formatter = [NSDateFormatter new];
    // Include an explicit date so a midnight/overnight plan is never ambiguous.
    NSString *day = [NSDateFormatter dateFormatFromTemplate:@"MMMd" options:0 locale:NSLocale.currentLocale];
    formatter.dateFormat = [day stringByAppendingString:@" HH:mm"];
    return [formatter stringFromDate:value];
}

// Both plans edit wall-clock minutes with the same wheel, independent of today's DST.
static inline UIDatePicker *DOScheduleTimePicker(NSInteger minute, id target, SEL action)
{
    UIDatePicker *picker = [UIDatePicker new];
    picker.datePickerMode = UIDatePickerModeTime;
    picker.preferredDatePickerStyle = UIDatePickerStyleWheels;
    picker.minuteInterval = 1;
    picker.locale = [NSLocale localeWithLocaleIdentifier:@"en_GB"];
    picker.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    picker.date = [NSDate dateWithTimeIntervalSinceReferenceDate:minute * 60];
    picker.translatesAutoresizingMaskIntoConstraints = NO;
    [picker.heightAnchor constraintEqualToConstant:216].active = YES;
    [picker addTarget:target action:action forControlEvents:UIControlEventValueChanged];
    return picker;
}

static inline NSInteger DOSchedulePickerMinute(UIDatePicker *picker)
{
    NSCalendar *calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    calendar.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    NSDateComponents *parts = [calendar components:NSCalendarUnitHour | NSCalendarUnitMinute fromDate:picker.date];
    return parts.hour * 60 + parts.minute;
}
