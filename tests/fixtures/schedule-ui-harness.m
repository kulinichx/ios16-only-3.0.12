// Real schedule controllers, with only file/daemon I/O replaced by a small fake.
#include <notify.h>
/* PRODUCTION_SCHEDULE_RUNTIME_HEADERS */
/* PRODUCTION_SCHEDULE_HEADERS */

@interface DOEnvironmentManager : NSObject
@property(nonatomic, strong) NSDictionary *lowConfig;
@property(nonatomic, strong) NSDictionary *batteryConfig;
@property(nonatomic, strong) NSDictionary *batteryState;
+ (instancetype)sharedManager;
- (NSDictionary *)lowPowerScheduleConfiguration;
- (NSDictionary *)lowPowerScheduleStatus;
- (NSDictionary *)batteryRecordConfiguration;
- (NSDictionary *)batteryRecordStatus;
- (BOOL)saveLowPowerScheduleEnabled:(BOOL)enabled startMinute:(NSInteger)start endMinute:(NSInteger)end error:(NSError **)error;
- (BOOL)saveBatteryRecordConfiguration:(NSDictionary *)configuration error:(NSError **)error;
- (NSString *)sendBatteryRecordCommand:(NSString *)command error:(NSError **)error;
@end
@implementation DOEnvironmentManager
+ (instancetype)sharedManager { static id manager; if (!manager) manager = [self new]; return manager; }
- (NSDictionary *)lowPowerScheduleConfiguration { return self.lowConfig ?: rcLowPowerDefaultConfiguration(); }
- (NSDictionary *)lowPowerScheduleStatus { return @{}; }
- (NSDictionary *)batteryRecordConfiguration { return self.batteryConfig ?: rcBatteryDefaultConfiguration(); }
- (NSDictionary *)batteryRecordStatus { return self.batteryState ?: @{}; }
- (BOOL)saveLowPowerScheduleEnabled:(BOOL)enabled startMinute:(NSInteger)start endMinute:(NSInteger)end error:(NSError **)error
{
    self.lowConfig = @{@"Version": @1, @"Enabled": @(enabled), @"StartMinute": @(start), @"EndMinute": @(end), @"Revision": NSUUID.UUID.UUIDString};
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
    low.lastStartMinute = 60;
    low.lastEndMinute = 390;
    [low draftChanged];
    CHECK(low.hasChanges && low.saveEnabled);
    [container selectPage:1];
    [container finishPageTransition];
    DOBatteryRecordController *battery = (id)container.selectedPage;
    CHECK(battery != (id)low && !battery.enabledSwitch.on);
    [container selectPage:0];
    [container finishPageTransition];
    CHECK(low.hasChanges && low.lastStartMinute == 60);
    [low savePressed];
    CHECK(!low.hasChanges && !low.saveEnabled);
    CHECK([low.feedbackLabel.text isEqual:DOLocalizedString(@"PowerSchedule_Saved")]);
    CHECK(![low.statusText containsString:@"Waiting"]);
    [container selectPage:1];
    [container finishPageTransition];
    [battery tableView:battery.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:5 inSection:0]];
    CHECK(battery.lastStartMinute == 60 && battery.lastEndMinute == 390);
    battery.enabledSwitch.on = YES;
    [battery draftChanged];
    [battery tableView:battery.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:1 inSection:0]];
    [battery.tableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:3 inSection:0]
        atScrollPosition:UITableViewScrollPositionMiddle animated:NO];
    [battery.tableView layoutIfNeeded];
    CHECK(battery.timePickerExpanded && battery.timePicker.superview != nil);
    [battery savePressed];
    CHECK(!battery.timePickerExpanded && !battery.hasChanges && !battery.saveEnabled);
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
            [page refreshScheduleGlassFrames];
            CHECK(page.sectionGlassViews.count >= 2);
            for (NSInteger section = 0; section < page.tableView.numberOfSections; section++) {
                DOCustomLiquidGlassView *glass = page.sectionGlassViews[@(section)];
                CHECK(glass && !glass.hidden);
                CGRect footer = [page.tableView rectForFooterInSection:section];
                CHECK(CGRectGetMaxY(glass.frame) <= CGRectGetMinY(footer) + 0.5);
                CHECK([page tableView:page.tableView heightForFooterInSection:section] >= 36);
                CHECK(![page respondsToSelector:@selector(tableView:titleForFooterInSection:)]);
                // Inspect actual mounted labels; geometry alone missed the duplicate footer.
                [page.tableView scrollRectToVisible:footer animated:NO];
                [page.tableView layoutIfNeeded];
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
            [page refreshScheduleGlassFrames];
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
    [nav willMoveToParentViewController:nil];
    [nav.view removeFromSuperview];
    [nav removeFromParentViewController];
    return cases;
}
