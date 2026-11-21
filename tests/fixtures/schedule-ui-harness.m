// Real schedule controllers, with only file/daemon I/O replaced by a small fake.
#include <notify.h>
/* PRODUCTION_SCHEDULE_RUNTIME_HEADERS */
/* PRODUCTION_SCHEDULE_HEADERS */

@interface DOEnvironmentManager : NSObject
@property(nonatomic, strong) NSDictionary *lowConfig;
@property(nonatomic) BOOL rejectSave;
@property(nonatomic, strong) NSDictionary *lowState;
@property(nonatomic, strong) NSDictionary *batteryConfig;
@property(nonatomic, strong) NSDictionary *batteryState;
+ (instancetype)sharedManager;
- (NSDictionary *)lowPowerScheduleConfiguration;
- (NSDictionary *)lowPowerScheduleStatus;
- (NSDictionary *)batteryRecordConfiguration;
- (NSDictionary *)batteryRecordStatus;
- (BOOL)saveLowPowerScheduleConfiguration:(NSDictionary *)configuration error:(NSError **)error;
- (BOOL)saveBatteryRecordConfiguration:(NSDictionary *)configuration error:(NSError **)error;
- (NSString *)sendBatteryRecordCommand:(NSString *)command error:(NSError **)error;
@end
@implementation DOEnvironmentManager
+ (instancetype)sharedManager { static id manager; if (!manager) manager = [self new]; return manager; }
- (NSDictionary *)lowPowerScheduleConfiguration { return self.lowConfig ?: rcLowPowerDefaultConfiguration(); }
- (NSDictionary *)lowPowerScheduleStatus { return self.lowState ?: @{}; }
- (NSDictionary *)batteryRecordConfiguration { return self.batteryConfig ?: rcBatteryDefaultConfiguration(); }
- (NSDictionary *)batteryRecordStatus { return self.batteryState ?: @{}; }
- (BOOL)saveLowPowerScheduleConfiguration:(NSDictionary *)configuration error:(NSError **)error
{
    if (self.rejectSave) return NO;
    self.lowConfig = configuration;
    return YES;
}
- (BOOL)saveBatteryRecordConfiguration:(NSDictionary *)configuration error:(NSError **)error { self.batteryConfig = configuration; return YES; }
- (NSString *)sendBatteryRecordCommand:(NSString *)command error:(NSError **)error { return NSUUID.UUID.UUIDString; }
@end

static NSString *ScheduleLocalizedString(NSString *key)
{
    static NSDictionary *strings;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ strings = @{ /* PRODUCTION_SCHEDULE_STRINGS */ }; });
    return strings[key] ?: key;
}
#undef DOLocalizedString
#define DOLocalizedString(key) ScheduleLocalizedString(key)
/* PRODUCTION_SCHEDULE_CONTROLLERS */

static void ScheduleLabels(UIView *view, NSString *text, NSMutableArray<UILabel *> *labels)
{
    if (view.hidden || view.alpha == 0) return;
    if ([view isKindOfClass:UILabel.class] && [((UILabel *)view).text isEqual:text]) [labels addObject:(id)view];
    for (UIView *child in view.subviews) ScheduleLabels(child, text, labels);
}

static void CheckScheduleBackdrops(DOLowPowerScheduleController *page)
{
    // Do not call refreshScheduleGlassFrames here: UIKit must trigger alignment
    // itself, including when estimated heights change during scrolling.
    [page.tableView layoutIfNeeded];
    CHECK(page.sectionGlassViews.count == page.tableView.numberOfSections);
    for (NSInteger section = 0; section < page.tableView.numberOfSections; section++) {
        DOCustomLiquidGlassView *glass = page.sectionGlassViews[@(section)];
        CHECK(glass && !glass.hidden && glass.superview == page.tableView.backgroundView);
        NSInteger rows = [page.tableView numberOfRowsInSection:section];
        CGRect first = [page.tableView rectForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:section]];
        CGRect last = [page.tableView rectForRowAtIndexPath:[NSIndexPath indexPathForRow:rows - 1 inSection:section]];
        CGRect expected = CGRectInset(CGRectUnion(first, last), 1, 0.5);
        CGRect actual = [glass convertRect:glass.bounds toView:page.tableView];
        CHECK(fabs(CGRectGetMinY(actual) - CGRectGetMinY(expected)) < 0.5);
        CHECK(fabs(CGRectGetMaxY(actual) - CGRectGetMaxY(expected)) < 0.5);
        CHECK(fabs(CGRectGetMinX(actual) - CGRectGetMinX(expected)) < 0.5);
        CHECK(fabs(CGRectGetWidth(actual) - CGRectGetWidth(expected)) < 0.5);
        CGRect header = [page.tableView rectForHeaderInSection:section];
        CGRect footer = [page.tableView rectForFooterInSection:section];
        CHECK(CGRectGetMinY(actual) >= CGRectGetMaxY(header) - 0.5);
        CHECK(CGRectGetMaxY(actual) <= CGRectGetMinY(footer) + 0.5);
    }
    for (UITableViewCell *cell in page.tableView.visibleCells) {
        NSIndexPath *path = [page.tableView indexPathForCell:cell];
        if (!path || CGRectGetHeight(cell.bounds) < 2) continue;
        DOCustomLiquidGlassView *glass = page.sectionGlassViews[@(path.section)];
        CGRect actual = [glass convertRect:glass.bounds toView:page.tableView];
        CGRect row = [cell convertRect:cell.bounds toView:page.tableView];
        CHECK(CGRectGetMinY(actual) <= CGRectGetMinY(row) + 1);
        CHECK(CGRectGetMaxY(actual) >= CGRectGetMaxY(row) - 1);
    }
    CHECK(page.tableView.backgroundView.subviews.count == page.sectionGlassViews.count);
}

static NSUInteger CheckScheduleUI(UIViewController *host, NSString *documents)
{
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:[UIViewController new]];
    nav.navigationBarHidden = YES;
    [host addChildViewController:nav];
    nav.view.frame = host.view.bounds;
    [host.view addSubview:nav.view];
    [nav didMoveToParentViewController:host];
    DOPowerScheduleController *container = [DOPowerScheduleController new];
    [nav pushViewController:container animated:NO];
    [nav.view layoutIfNeeded];
    DOLowPowerScheduleController *low = container.pages[0];
    low.enabledSwitch.on = YES;
    [low.enabledSwitch sendActionsForControlEvents:UIControlEventValueChanged];
    CHECK([DOEnvironmentManager.sharedManager.lowConfig[@"Enabled"] boolValue]);
    for (NSInteger field = 0; field < 2; field++) {
        low.editingTime = field;
        low.timePicker.date = [low dateForMinute:field ? 390 : 60];
        [low.timePicker sendActionsForControlEvents:UIControlEventValueChanged];
    }
    CHECK(!low.hasChanges && [low.savedConfiguration[@"EndMinute"] integerValue] == 390);
    [container selectPage:1];
    [container finishPageTransition];
    DOBatteryRecordController *battery = (id)container.selectedPage;
    CHECK(battery != (id)low && !battery.enabledSwitch.on);
    [container selectPage:0];
    [container finishPageTransition];
    CHECK(!low.hasChanges && low.lastStartMinute == 60);
    CHECK(![low.statusText containsString:@"Waiting"]);
    for (NSString *state in @[@"timerFailed", @"calendarFailed", @"runtimeFailed"]) {
        DOEnvironmentManager.sharedManager.lowState = @{@"Revision": low.savedConfiguration[@"Revision"],
            @"Updated": NSDate.date, @"State": state};
        [low refreshStatus];
        CHECK([low.statusText isEqual:DOLocalizedString(@"LowPowerSchedule_RuntimeFailed")]);
    }
    DOEnvironmentManager.sharedManager.lowState = nil;
    [low refreshStatus];
    [container selectPage:1];
    [container finishPageTransition];
    [battery tableView:battery.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:5 inSection:0]];
    CHECK(battery.lastStartMinute == 60 && battery.lastEndMinute == 390);
    battery.enabledSwitch.on = YES;
    [battery.enabledSwitch sendActionsForControlEvents:UIControlEventValueChanged];
    CHECK([battery.savedConfiguration[@"Enabled"] boolValue]);
    battery.repeatSwitch.on = YES;
    [battery.repeatSwitch sendActionsForControlEvents:UIControlEventValueChanged];
    CHECK([battery.savedConfiguration[@"Repeat"] boolValue]);
    [battery tableView:battery.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:1 inSection:0]];
    [battery.tableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:3 inSection:0]
        atScrollPosition:UITableViewScrollPositionMiddle animated:NO];
    [battery.tableView layoutIfNeeded];
    CHECK(battery.timePickerExpanded && battery.timePicker.superview != nil);
    [battery tableView:battery.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:1 inSection:0]];
    CHECK(!battery.timePickerExpanded && !battery.hasChanges);
    CHECK([battery.statusText isEqual:[NSString stringWithFormat:DOLocalizedString(@"BatteryRecord_PlannedAt"), DOScheduleDateText(battery.savedConfiguration[@"FirstStart"])]]);
    CHECK(![battery.statusText containsString:@"Unavailable"]);
    CHECK([DOEnvironmentManager.sharedManager.lowConfig[@"StartMinute"] integerValue] == 60);
    CHECK(![battery.savedConfiguration[@"Revision"] isEqual:low.savedConfiguration[@"Revision"]]);
    BOOL edgeFound = NO;
    for (UIGestureRecognizer *gesture in battery.view.gestureRecognizers)
        if ([gesture isKindOfClass:UIScreenEdgePanGestureRecognizer.class]) edgeFound = YES;
    CHECK(edgeFound);
    // An acknowledged command produces feedback; no command is needed to preview a plan.
    battery.pendingCommand = @"test-command";
    DOEnvironmentManager.sharedManager.batteryState = @{@"Revision": battery.savedConfiguration[@"Revision"],
        @"Updated": NSDate.date, @"CommandID": @"test-command", @"CommandResult": @"stopped", @"History": @[]};
    [battery refreshStatus];
    CHECK(battery.pendingCommand == nil);
    CHECK([battery.feedbackLabel.text isEqual:DOLocalizedString(@"BatteryRecord_Result_stopped")]);
    CHECK([battery tableView:battery.tableView numberOfRowsInSection:1] == 1);
    UITableViewCell *status = [battery tableView:battery.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:1]];
    CHECK(status.accessoryView == nil && status.selectionStyle == UITableViewCellSelectionStyleNone);
    CHECK(status.detailTextLabel.text.length == 0);
    CHECK(!(status.accessibilityTraits & UIAccessibilityTraitButton));
    // Rapid switching and interruption must leave one visible page and one shared control.
    DOScheduleModeControl *mode = container.modeControl;
    for (NSUInteger i = 0; i < 8; i++) [container selectPage:i % 2];
    [container finishPageTransition];
    CHECK(container.modeControl == mode && container.children.count == 2);
    CHECK(container.contentView.userInteractionEnabled);
    CHECK(container.selectedPage.view.maskView == nil && container.pageAnimator == nil);
    CHECK(low.view.hidden != battery.view.hidden);
    CHECK(low.hasChanges == NO && battery.hasChanges == NO);
    NSMutableArray *history = [NSMutableArray new];
    for (NSUInteger index = 0; index < 60; index++)
        [history addObject:@{@"Recorded": [NSDate dateWithTimeIntervalSinceNow:-(double)index * 3600],
            @"Result": @"interrupted"}];
    DOEnvironmentManager.sharedManager.batteryState = @{@"Revision": battery.savedConfiguration[@"Revision"],
        @"Updated": NSDate.date, @"History": history};
    [battery refreshStatus];
    NSUInteger cases = 0;
    for (NSValue *size in @[[NSValue valueWithCGSize:CGSizeMake(320, 568)],
        [NSValue valueWithCGSize:CGSizeMake(393, 852)], [NSValue valueWithCGSize:CGSizeMake(834, 1194)]]) {
        nav.view.frame = (CGRect){CGPointZero, size.CGSizeValue};
        [nav.view layoutIfNeeded];
        for (NSInteger pageIndex = 0; pageIndex < 2; pageIndex++) {
            [container selectPage:pageIndex];
            [container finishPageTransition];
            DOLowPowerScheduleController *page = container.selectedPage;
            [page.view layoutIfNeeded];
            [page.tableView reloadData];
            [page.tableView layoutIfNeeded];
            CheckScheduleBackdrops(page);
            CHECK(page.sectionGlassViews.count >= 2);
            for (NSInteger section = 0; section < page.tableView.numberOfSections; section++) {
                DOCustomLiquidGlassView *glass = page.sectionGlassViews[@(section)];
                CHECK(glass && !glass.hidden);
                CGRect footer = [page.tableView rectForFooterInSection:section];
                CHECK(CGRectGetMaxY([glass convertRect:glass.bounds toView:page.tableView]) <= CGRectGetMinY(footer) + 0.5);
                CHECK([page tableView:page.tableView heightForFooterInSection:section] >= 36);
                CHECK(![page respondsToSelector:@selector(tableView:titleForFooterInSection:)]);
                // Inspect actual mounted labels; geometry alone missed the duplicate footer.
                [page.tableView scrollRectToVisible:footer animated:NO];
                [page.tableView layoutIfNeeded];
                CheckScheduleBackdrops(page);
                footer = [page.tableView rectForFooterInSection:section];
                NSMutableArray<UILabel *> *labels = [NSMutableArray new];
                ScheduleLabels(page.tableView, [page footerTextForSection:section], labels);
                CHECK(labels.count == 1);
                UILabel *label = labels.firstObject;
                CGRect textFrame = [label convertRect:label.bounds toView:page.tableView];
                CHECK(CGRectGetMinY(textFrame) >= CGRectGetMinY(footer) + 15);
                CHECK(CGRectGetMaxY(textFrame) <= CGRectGetMaxY(footer) - 19);
                [page refreshStatus];
                NSMutableArray<UILabel *> *after = [NSMutableArray new];
                ScheduleLabels(page.tableView, [page footerTextForSection:section], after);
                CHECK(after.count == 1 && after.firstObject == label);
            }
            [page.tableView setContentOffset:CGPointMake(0, 100) animated:NO];
            CheckScheduleBackdrops(page);
            NSDictionary *backdrops = [page.sectionGlassViews copy];
            for (NSUInteger pass = 0; pass < 12; pass++) {
                [page setTimePickerExpanded:pass % 2 == 0 animated:NO];
                [page.tableView setContentOffset:CGPointMake(0, pass % 2 ? 0 : 100) animated:NO];
                CheckScheduleBackdrops(page);
                CHECK([page.sectionGlassViews isEqualToDictionary:backdrops]);
            }
            if (pageIndex == 1) {
                CHECK([page.tableView numberOfRowsInSection:2] == 60);
                for (NSInteger row = 0; row < 60; row += 7) {
                    [page.tableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:row inSection:2]
                        atScrollPosition:UITableViewScrollPositionMiddle animated:NO];
                    CheckScheduleBackdrops(page);
                    CHECK([page.sectionGlassViews isEqualToDictionary:backdrops]);
                }
            }
            CHECK(!page.view.hasAmbiguousLayout);
            [mode layoutIfNeeded];
            CHECK(fabs(mode.layer.cornerRadius - CGRectGetHeight(mode.bounds) / 2) < 0.5);
            CHECK(fabs(mode.selectionView.layer.cornerRadius - CGRectGetHeight(mode.selectionView.bounds) / 2) < 0.5);
            [page.tableView setContentOffset:CGPointZero animated:NO];
            [page.view layoutIfNeeded];
            Snapshot(container, [NSString stringWithFormat:@"schedule-%ld-%.0fx%.0f.png", (long)pageIndex, size.CGSizeValue.width, size.CGSizeValue.height], documents);
            cases++;
        }
    }
    DOEnvironmentManager *env = DOEnvironmentManager.sharedManager;
    low.editingTime = 1;
    low.timePicker.date = [low dateForMinute:low.lastStartMinute];
    [low.timePicker sendActionsForControlEvents:UIControlEventValueChanged];
    CHECK(low.lastEndMinute == 390 && DOSchedulePickerMinute(low.timePicker) == 390);
    env.rejectSave = YES;
    low.enabledSwitch.on = NO;
    [low.enabledSwitch sendActionsForControlEvents:UIControlEventValueChanged];
    CHECK(low.enabledSwitch.on && [env.lowConfig[@"Enabled"] boolValue]);
    env.rejectSave = NO;
    low.enabledSwitch.on = NO;
    [low.enabledSwitch sendActionsForControlEvents:UIControlEventValueChanged];
    CHECK(![env.lowConfig[@"Enabled"] boolValue] && !low.hasChanges);
    CHECK([env.lowConfig[@"EndMinute"] integerValue] == 390);
    CHECK([low.statusText isEqual:DOLocalizedString(NSProcessInfo.processInfo.lowPowerModeEnabled ? @"LowPowerSchedule_SystemOn" : @"LowPowerSchedule_Disabled")]);
    NSString *stopID = env.lowConfig[@"DisableRequest"];
    env.lowState = @{@"Revision": env.lowConfig[@"Revision"], @"Updated": NSDate.date, @"State": @"disabled", @"DisableRequest": @"older"};
    [low finishStopWait:stopID];
    CHECK([[low disabledStatusWithSystemLowPower:NO] isEqual:DOLocalizedString(@"LowPowerSchedule_Disabled")]);
    CHECK([[low disabledStatusWithSystemLowPower:YES] isEqual:DOLocalizedString(@"LowPowerSchedule_SystemOn")]);
    env.lowState = @{@"Revision": env.lowConfig[@"Revision"], @"Updated": NSDate.date, @"State": @"disabled", @"DisableRequest": stopID};
    [low refreshStatus];
    CHECK([[low disabledStatusWithSystemLowPower:NO] isEqual:DOLocalizedString(@"LowPowerSchedule_Disabled")]);
    env.lowState = @{@"Revision": env.lowConfig[@"Revision"], @"Updated": NSDate.date, @"State": @"applyFailed", @"DisableRequest": stopID};
    [low refreshStatus];
    CHECK([[low disabledStatusWithSystemLowPower:YES] isEqual:DOLocalizedString(@"LowPowerSchedule_DisableFailed")]);
    CHECK([[low disabledStatusWithSystemLowPower:NO] isEqual:DOLocalizedString(@"LowPowerSchedule_Disabled")]);
    env.batteryState = @{@"Revision": battery.savedConfiguration[@"Revision"], @"Updated": NSDate.date,
        @"Active": @{@"Source": @"scheduled"}, @"History": @[]};
    battery.enabledSwitch.on = NO;
    [battery.enabledSwitch sendActionsForControlEvents:UIControlEventValueChanged];
    CHECK(![env.batteryConfig[@"Enabled"] boolValue] && env.batteryConfig[@"DisableRequest"]);
    CHECK([battery.statusText isEqual:DOLocalizedString(@"BatteryRecord_EndUnconfirmed")]);
    [battery finishStopWait:env.batteryConfig[@"DisableRequest"]];
    CHECK([battery.statusText isEqual:DOLocalizedString(@"BatteryRecord_EndUnconfirmed")]);
    env.batteryState = nil; [battery refreshStatus];
    CHECK([battery.statusText isEqual:DOLocalizedString(@"BatteryRecord_Paused")]);
    NSMutableDictionary *idle = [@{@"Revision": env.batteryConfig[@"Revision"], @"Updated": NSDate.date,
        @"State": @"idle", @"History": @[@{@"Result": @"cancelled", @"Recorded": NSDate.date}]} mutableCopy];
    env.batteryState = idle; [battery refreshStatus];
    CHECK([battery.statusText isEqual:DOLocalizedString(@"BatteryRecord_Paused")]);
    idle[@"RecordEndedByStop"] = env.batteryConfig[@"DisableRequest"]; [battery refreshStatus];
    CHECK([battery.statusText isEqual:DOLocalizedString(@"BatteryRecord_StoppedAndDisabled")]);
    [nav willMoveToParentViewController:nil];
    [nav.view removeFromSuperview];
    [nav removeFromParentViewController];
    // The table's layout callback and notification handlers must not retain pages.
    __weak DOPowerScheduleController *releasedContainer;
    __weak DOLowPowerScheduleController *releasedLow;
    __weak DOLowPowerScheduleController *releasedBattery;
    @autoreleasepool {
        DOPowerScheduleController *temporary = [DOPowerScheduleController new];
        [temporary loadViewIfNeeded];
        [temporary.view layoutIfNeeded];
        releasedContainer = temporary;
        releasedLow = temporary.pages[0];
        releasedBattery = temporary.pages[1];
    }
    CHECK(!releasedContainer && !releasedLow && !releasedBattery);
    return cases;
}
