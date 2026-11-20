#import "DOLowPowerScheduleController.h"
#import "DOPowerScheduleController.h"
#import "DOBatteryRecordController.h"
#import "DOScheduleTimePicker.h"
#import "DOEnvironmentManager.h"
#import "DOUIManager.h"
#import "../DOSupporterLicense.h"
#import "../DOSupporterRenderAuthorization.h"
#import "../../../../BaseBin/roothidehooks/src/RCLowPowerSchedule.h"
#include <notify.h>

static NSString * const DOScheduleThemeDidChangeNotification = @"DOCustomGlassTheme.DidChange";

// Shared renderer implemented by the existing RC9 main page.
@interface DOCustomLiquidGlassView : UIView
@property(nonatomic, assign) CGFloat materialScale;
@property(nonatomic, assign) CGFloat preferredCornerRadius;
- (instancetype)initWithCornerRadius:(CGFloat)cornerRadius baseTintAlpha:(CGFloat)baseTintAlpha;
- (void)reloadMaterial;
@end

@interface DOPowerScheduleController ()
@property(nonatomic, strong) NSArray<DOLowPowerScheduleController *> *pages;
@property(nonatomic, strong) DOLowPowerScheduleController *selectedPage;
@end

@implementation DOPowerScheduleController
- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.clearColor;
    self.title = DOLocalizedString(@"PowerSchedule_Title");
    self.pages = @[[DOLowPowerScheduleController new], [DOBatteryRecordController new]];
    __weak typeof(self) weakSelf = self;
    for (DOLowPowerScheduleController *page in self.pages) {
        page.modeSelectionHandler = ^(NSInteger index) { [weakSelf selectPage:index]; };
        page.backHandler = ^{ [weakSelf backPressed]; };
    }
    [self selectPage:0];
}

- (void)selectPage:(NSInteger)index
{
    if (index < 0 || index >= self.pages.count || self.selectedPage == self.pages[index]) return;
    DOLowPowerScheduleController *previous = self.selectedPage;
    DOLowPowerScheduleController *next = self.pages[index];
    BOOL visible = self.viewIfLoaded.window != nil;
    if (previous) {
        [previous willMoveToParentViewController:nil];
        if (visible) [previous beginAppearanceTransition:NO animated:NO];
        [previous.view removeFromSuperview];
        if (visible) [previous endAppearanceTransition];
        [previous removeFromParentViewController];
    }
    self.selectedPage = next;
    [self addChildViewController:next];
    next.view.translatesAutoresizingMaskIntoConstraints = NO;
    if (visible) [next beginAppearanceTransition:YES animated:NO];
    [self.view addSubview:next.view];
    [NSLayoutConstraint activateConstraints:@[
        [next.view.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [next.view.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [next.view.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [next.view.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
    [next didMoveToParentViewController:self];
    if (visible) {
        [next endAppearanceTransition];
        [[[UISelectionFeedbackGenerator alloc] init] selectionChanged];
    }
}

- (void)backPressed
{
    if (self.presentedViewController) return;
    BOOL dirty = NO;
    for (DOLowPowerScheduleController *page in self.pages) dirty |= page.isViewLoaded && page.hasChanges;
    if (!dirty) { [self.navigationController popViewControllerAnimated:YES]; return; }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:self.title
        message:DOLocalizedString(@"PowerSchedule_Discard") preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:DOLocalizedString(@"Button_Cancel") style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:DOLocalizedString(@"LowPowerSchedule_DiscardButton")
        style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
            [self.navigationController popViewControllerAnimated:YES];
        }]];
    [self presentViewController:alert animated:YES completion:nil];
}
@end

@interface DOLowPowerScheduleController ()
@property(nonatomic, strong) UIButton *backButton;
@property(nonatomic, strong) UILabel *feedbackLabel;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, DOCustomLiquidGlassView *> *sectionGlassViews;
@property(nonatomic, strong) UIImpactFeedbackGenerator *timeFeedback;
@property(nonatomic, copy) NSArray<NSLayoutConstraint *> *timePickerCellConstraints;
@property(nonatomic) BOOL awaitingSaveConfirmation;
@property(nonatomic) int statusToken;
@end

@implementation DOLowPowerScheduleController

- (NSString *)scheduleTitle { return DOLocalizedString(@"LowPowerSchedule_Title"); }
- (NSInteger)scheduleMode { return 0; }
- (NSDictionary *)loadScheduleConfiguration { return [DOEnvironmentManager.sharedManager lowPowerScheduleConfiguration]; }
- (NSDictionary *)loadRuntimeStatus { return [DOEnvironmentManager.sharedManager lowPowerScheduleStatus]; }
- (const char *)scheduleStatusNotification { return RC_LOW_POWER_STATUS_CHANGED; }
- (const char *)scheduleQueryNotification { return RC_LOW_POWER_QUERY; }
- (BOOL)isScheduleVisible
{
    UIViewController *page = self;
    while (page.parentViewController && page.parentViewController != self.navigationController)
        page = page.parentViewController;
    return self.viewIfLoaded.window && self.navigationController.topViewController == page;
}
- (void)modeChanged:(UISegmentedControl *)sender
{
    if (self.modeSelectionHandler) self.modeSelectionHandler(sender.selectedSegmentIndex);
    sender.selectedSegmentIndex = self.scheduleMode;
}

- (UIButton *)chromeButton:(NSString *)image action:(SEL)action label:(NSString *)label
{
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.tintColor = UIColor.labelColor;
    UIImageSymbolConfiguration *configuration =
        [UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIImageSymbolWeightMedium];
    [button setImage:[UIImage systemImageNamed:image withConfiguration:configuration]
           forState:UIControlStateNormal];
    button.accessibilityLabel = label;
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (UIDatePicker *)timePickerForMinute:(NSInteger)minute
{
    return DOScheduleTimePicker(minute, self, @selector(timeChanged:));
}

- (NSInteger)minuteFromPicker:(UIDatePicker *)picker
{
    return DOSchedulePickerMinute(picker);
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.statusToken = -1;
    self.editingTime = 0;
    self.timePickerExpanded = NO;
    self.sectionGlassViews = [NSMutableDictionary new];
    self.title = self.scheduleTitle;
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.view.backgroundColor = UIColor.clearColor;
    self.savedConfiguration = [self loadScheduleConfiguration];
    if (!rcLowPowerConfigurationValid(self.savedConfiguration))
        self.savedConfiguration = rcLowPowerDefaultConfiguration();

    self.enabledSwitch = [UISwitch new];
    self.enabledSwitch.on = [self.savedConfiguration[@"Enabled"] boolValue];
    [self.enabledSwitch addTarget:self action:@selector(draftChanged)
                forControlEvents:UIControlEventValueChanged];
    self.lastStartMinute = [self.savedConfiguration[@"StartMinute"] integerValue];
    self.lastEndMinute = [self.savedConfiguration[@"EndMinute"] integerValue];
    self.timePicker = [self timePickerForMinute:self.lastStartMinute];
    self.timePicker.accessibilityLabel = DOLocalizedString(self.scheduleMode == 0 ? @"LowPowerSchedule_OnTime" : @"BatteryRecord_StartTime");

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.backgroundColor = UIColor.clearColor;
    self.tableView.backgroundView = nil;
    self.tableView.opaque = NO;
    self.tableView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    self.tableView.bounces = YES;
    self.tableView.alwaysBounceVertical = YES;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 60;
    [self refreshScheduleScrollInsets];
    [self.view addSubview:self.tableView];

    UIButton *back = [self chromeButton:@"chevron.left" action:@selector(backPressed)
        label:DOLocalizedString(@"Button_Cancel")];
    self.backButton = back;
    self.saveButton = [self chromeButton:@"checkmark" action:@selector(savePressed)
        label:DOLocalizedString(@"LowPowerSchedule_Save")];
    self.saveButton.enabled = NO;
    UILabel *title = [UILabel new];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.text = self.title;
    title.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    title.textColor = UIColor.labelColor;
    title.adjustsFontForContentSizeCategory = YES;
    title.numberOfLines = 2;
    title.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:back];
    [self.view addSubview:title];
    [self.view addSubview:self.saveButton];
    UISegmentedControl *mode = [[UISegmentedControl alloc] initWithItems:@[
        DOLocalizedString(@"LowPowerSchedule_Title"), DOLocalizedString(@"BatteryRecord_Title")]];
    mode.translatesAutoresizingMaskIntoConstraints = NO;
    mode.selectedSegmentIndex = self.scheduleMode;
    mode.accessibilityLabel = DOLocalizedString(@"PowerSchedule_Title");
    [mode addTarget:self action:@selector(modeChanged:) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:mode];
    self.feedbackLabel = [UILabel new];
    self.feedbackLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.feedbackLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    self.feedbackLabel.adjustsFontForContentSizeCategory = YES;
    self.feedbackLabel.textColor = UIColor.secondaryLabelColor;
    self.feedbackLabel.numberOfLines = 0;
    self.feedbackLabel.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:self.feedbackLabel];
    [NSLayoutConstraint activateConstraints:@[
        [back.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:10],
        [back.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:6],
        [back.widthAnchor constraintEqualToConstant:44],
        [back.heightAnchor constraintEqualToConstant:44],
        [self.saveButton.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-10],
        [self.saveButton.topAnchor constraintEqualToAnchor:back.topAnchor],
        [self.saveButton.widthAnchor constraintEqualToConstant:44],
        [self.saveButton.heightAnchor constraintEqualToConstant:44],
        [title.leadingAnchor constraintEqualToAnchor:back.trailingAnchor constant:8],
        [title.trailingAnchor constraintEqualToAnchor:self.saveButton.leadingAnchor constant:-8],
        [title.topAnchor constraintEqualToAnchor:back.topAnchor],
        [title.heightAnchor constraintGreaterThanOrEqualToConstant:44],
        [mode.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:12],
        [mode.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:20],
        [mode.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-20],
        [mode.heightAnchor constraintGreaterThanOrEqualToConstant:36],
        [self.feedbackLabel.topAnchor constraintEqualToAnchor:mode.bottomAnchor constant:10],
        [self.feedbackLabel.leadingAnchor constraintEqualToAnchor:mode.leadingAnchor],
        [self.feedbackLabel.trailingAnchor constraintEqualToAnchor:mode.trailingAnchor],
        [self.feedbackLabel.heightAnchor constraintGreaterThanOrEqualToConstant:18],
        [self.tableView.topAnchor constraintEqualToAnchor:self.feedbackLabel.bottomAnchor constant:4],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
    UIScreenEdgePanGestureRecognizer *edge = [[UIScreenEdgePanGestureRecognizer alloc]
        initWithTarget:self action:@selector(edgeBack:)];
    edge.edges = UIRectEdgeLeft;
    [self.view addGestureRecognizer:edge];
    [self.tableView.panGestureRecognizer requireGestureRecognizerToFail:edge];

    __weak typeof(self) weakSelf = self;
    int token = -1;
    if (notify_register_dispatch([self scheduleStatusNotification], &token, dispatch_get_main_queue(),
        ^(__unused int value) {
            if ([weakSelf isScheduleVisible]) [weakSelf refreshStatus];
        }) == NOTIFY_STATUS_OK)
        self.statusToken = token;
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(applicationDidBecomeActive:)
        name:UIApplicationDidBecomeActiveNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(applicationWillResignActive:)
        name:UIApplicationWillResignActiveNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(scheduleThemeDidChange:)
        name:DOScheduleThemeDidChangeNotification object:nil];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self refreshScheduleAppearance];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    [self requestStatus];
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    [self refreshScheduleScrollInsets];
    [self refreshScheduleGlassFrames];
}

- (void)viewDidDisappear:(BOOL)animated
{
    [super viewDidDisappear:animated];
    self.timeFeedback = nil;
    self.queryDate = nil;
    self.statusWaiting = NO;
}

- (void)dealloc
{
    if (self.isViewLoaded && self.statusToken >= 0) notify_cancel(self.statusToken);
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)scheduleThemeDidChange:(NSNotification *)notification
{
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        [weakSelf refreshScheduleAppearance];
    });
}

- (void)styleScheduleCell:(UITableViewCell *)cell
{
    cell.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    cell.backgroundColor = DORHSupporterRenderIsVerified() ? UIColor.clearColor :
        [UIColor.secondarySystemGroupedBackgroundColor colorWithAlphaComponent:0.82];
    cell.contentView.backgroundColor = UIColor.clearColor;
    cell.backgroundView = nil;
    cell.textLabel.textColor = UIColor.labelColor;
    cell.textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    cell.textLabel.adjustsFontForContentSizeCategory = YES;
    cell.textLabel.numberOfLines = 0;
    cell.detailTextLabel.numberOfLines = 0;
    cell.detailTextLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    cell.detailTextLabel.adjustsFontForContentSizeCategory = YES;
}

- (void)refreshScheduleScrollInsets
{
    if (!self.tableView) return;
    CGFloat bottom = self.view.safeAreaInsets.bottom + 24.0;
    UIEdgeInsets insets = self.tableView.contentInset;
    insets.bottom = bottom;
    if (!UIEdgeInsetsEqualToEdgeInsets(self.tableView.contentInset, insets))
        self.tableView.contentInset = insets;
    if (!UIEdgeInsetsEqualToEdgeInsets(self.tableView.scrollIndicatorInsets, insets))
        self.tableView.scrollIndicatorInsets = insets;
}

- (void)refreshScheduleGlassFrames
{
    for (NSNumber *key in self.sectionGlassViews.allKeys) {
        if (key.integerValue >= self.tableView.numberOfSections ||
            [self.tableView numberOfRowsInSection:key.integerValue] == 0) {
            [self.sectionGlassViews[key] removeFromSuperview];
            [self.sectionGlassViews removeObjectForKey:key];
        }
    }
    if (!DORHSupporterRenderIsVerified()) {
        for (DOCustomLiquidGlassView *glass in self.sectionGlassViews.allValues) glass.hidden = YES;
        return;
    }

    for (NSInteger section = 0; section < self.tableView.numberOfSections; section++) {
        NSInteger rows = [self.tableView numberOfRowsInSection:section];
        if (!rows) continue;
        CGRect first = [self.tableView rectForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:section]];
        CGRect last = [self.tableView rectForRowAtIndexPath:[NSIndexPath indexPathForRow:rows - 1 inSection:section]];
        CGRect frame = CGRectUnion(first, last);
        CGRect footer = [self.tableView rectForFooterInSection:section];
        if (CGRectGetHeight(footer) > 0 && CGRectGetMinY(footer) > CGRectGetMinY(frame))
            frame.size.height = MIN(frame.size.height, CGRectGetMinY(footer) - CGRectGetMinY(frame));
        // Keep the last valid frame during transient foreground/layout passes.
        if (CGRectIsEmpty(frame) || CGRectGetHeight(frame) < 2) continue;
        DOCustomLiquidGlassView *glass = self.sectionGlassViews[@(section)];
        BOOL created = NO;
        if (!glass) {
            glass = [[DOCustomLiquidGlassView alloc] initWithCornerRadius:18 baseTintAlpha:0.038];
            glass.userInteractionEnabled = NO;
            glass.materialScale = 0.88;
            glass.preferredCornerRadius = 18;
            glass.layer.cornerRadius = 18;
            glass.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner |
                kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner;
            self.sectionGlassViews[@(section)] = glass;
            [self.tableView insertSubview:glass atIndex:0];
            created = YES;
        }
        CGRect glassFrame = CGRectInset(frame, 1, 0.5);
        if (glass.hidden) glass.hidden = NO;
        if (!CGRectEqualToRect(glass.frame, glassFrame)) glass.frame = glassFrame;
        if (created) [self.tableView sendSubviewToBack:glass];
    }
}

- (void)refreshScheduleAppearance
{
    self.backButton.tintColor = UIColor.labelColor;
    self.saveButton.tintColor = UIColor.labelColor;
    for (UITableViewCell *cell in self.tableView.visibleCells) [self styleScheduleCell:cell];
    [self refreshScheduleGlassFrames];
    for (DOCustomLiquidGlassView *glass in self.sectionGlassViews.allValues)
        [glass reloadMaterial];
}

- (BOOL)hasChanges
{
    return self.enabledSwitch.on != [self.savedConfiguration[@"Enabled"] boolValue] ||
        self.lastStartMinute != [self.savedConfiguration[@"StartMinute"] integerValue] ||
        self.lastEndMinute != [self.savedConfiguration[@"EndMinute"] integerValue];
}

- (void)draftChanged
{
    self.saveButton.enabled = self.hasChanges || self.timePickerExpanded;
    if (self.hasChanges) [self showScheduleFeedback:DOLocalizedString(@"PowerSchedule_Unsaved") error:NO];
    else if ([self.feedbackLabel.text isEqual:DOLocalizedString(@"PowerSchedule_Unsaved")]) self.feedbackLabel.text = nil;
}

- (void)prepareTimeFeedback
{
    if (!self.timeFeedback)
        self.timeFeedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleRigid];
    [self.timeFeedback prepare];
}

- (void)timeChanged:(UIDatePicker *)picker
{
    NSInteger minute = [self minuteFromPicker:picker];
    NSInteger previous = self.editingTime == 0 ? self.lastStartMinute : self.lastEndMinute;
    if (self.editingTime == 0) self.lastStartMinute = minute;
    else self.lastEndMinute = minute;
    if (minute != previous && [self isScheduleVisible] &&
        UIApplication.sharedApplication.applicationState == UIApplicationStateActive) {
        // Match GlassFolders' crisp detent feedback, once per changed value.
        [self prepareTimeFeedback];
        [self.timeFeedback impactOccurredWithIntensity:0.68];
        [self.timeFeedback prepare];
    }
    [self updateTimeLabels];
    [self draftChanged];
}

- (NSDate *)dateForMinute:(NSInteger)minute
{
    return [NSDate dateWithTimeIntervalSinceReferenceDate:minute * 60];
}

- (void)attachTimePickerToCell:(UITableViewCell *)cell
{
    if (self.timePicker.superview == cell.contentView) {
        self.timePicker.hidden = NO;
        return;
    }
    [NSLayoutConstraint deactivateConstraints:self.timePickerCellConstraints ?: @[]];
    self.timePickerCellConstraints = nil;
    [self.timePicker removeFromSuperview];
    self.timePicker.translatesAutoresizingMaskIntoConstraints = NO;
    [cell.contentView addSubview:self.timePicker];
    self.timePickerCellConstraints = @[
        [self.timePicker.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor],
        [self.timePicker.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor],
        [self.timePicker.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:8],
        [self.timePicker.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-8],
    ];
    [NSLayoutConstraint activateConstraints:self.timePickerCellConstraints];
    self.timePicker.hidden = NO;
}

- (void)setTimePickerExpanded:(BOOL)expanded animated:(BOOL)animated
{
    if (self.timePickerExpanded == expanded) {
        [self draftChanged];
        return;
    }
    if (!expanded) {
        // Remove the fixed-height wheel before collapsing its zero-height row.
        [NSLayoutConstraint deactivateConstraints:self.timePickerCellConstraints ?: @[]];
        self.timePickerCellConstraints = nil;
        [self.timePicker removeFromSuperview];
        self.timePicker.hidden = YES;
    }
    self.timePickerExpanded = expanded;
    [self updateTimeLabels];
    void (^updates)(void) = ^{
        [self.tableView beginUpdates];
        [self.tableView endUpdates];
    };
    if (animated) {
        [UIView animateWithDuration:0.22 animations:updates];
    } else {
        updates();
    }
    if (expanded) {
        [self.tableView layoutIfNeeded];
        NSIndexPath *pickerPath = [NSIndexPath indexPathForRow:3 inSection:0];
        UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:pickerPath];
        if (cell) [self attachTimePickerToCell:cell];
    }
    [self refreshScheduleGlassFrames];
    [self draftChanged];
}

- (BOOL)isStartRow:(NSIndexPath *)indexPath
{
    return indexPath.section == 0 && indexPath.row == 1;
}

- (void)updateTimeLabels
{
    for (NSIndexPath *indexPath in self.tableView.indexPathsForVisibleRows) {
        if (indexPath.section != 0 || (indexPath.row != 1 && indexPath.row != 2)) continue;
        UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
        NSInteger minute = [self isStartRow:indexPath] ? self.lastStartMinute : self.lastEndMinute;
        cell.detailTextLabel.text =
            [NSString stringWithFormat:@"%02ld:%02ld", (long)(minute / 60), (long)(minute % 60)];
        BOOL selected = self.timePickerExpanded &&
            ((self.editingTime == 0 && [self isStartRow:indexPath]) ||
             (self.editingTime == 1 && ![self isStartRow:indexPath]));
        cell.accessoryType = selected ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
        cell.tintColor = UIColor.systemBlueColor;
    }
}

- (void)requestStatus
{
    NSDate *queryDate = NSDate.date;
    self.queryDate = queryDate;
    self.statusWaiting = YES;
    [self showScheduleFeedback:DOLocalizedString(self.awaitingSaveConfirmation ? @"PowerSchedule_Saved" : @"PowerSchedule_Refreshing") error:NO];
    [self refreshStatus];
    [self postStatusQuery];
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if ([weakSelf.queryDate isEqualToDate:queryDate] && [weakSelf isScheduleVisible] &&
            UIApplication.sharedApplication.applicationState == UIApplicationStateActive) {
            weakSelf.statusWaiting = NO;
            [weakSelf refreshStatus];
        }
    });
}

- (void)postStatusQuery { notify_post([self scheduleQueryNotification]); }

- (void)applicationDidBecomeActive:(NSNotification *)notification
{
    if ([self isScheduleVisible]) [self requestStatus];
}

- (void)applicationWillResignActive:(NSNotification *)notification
{
    self.timeFeedback = nil;
    self.queryDate = nil;
    self.statusWaiting = NO;
}

- (BOOL)statusFresh
{
    NSDate *updated = self.runtimeStatus[@"Updated"];
    return self.queryDate && [updated isKindOfClass:NSDate.class] &&
        [updated timeIntervalSinceDate:self.queryDate] >= 0 &&
        [self.runtimeStatus[@"Revision"] isEqual:self.savedConfiguration[@"Revision"]];
}

- (BOOL)runtimeHasError
{
    return [@[@"unsupported", @"applyFailed", @"runtimeFailed", @"timerFailed"] containsObject:self.runtimeStatus[@"State"] ?: @""];
}

- (void)refreshStatus
{
    self.runtimeStatus = [self loadRuntimeStatus];
    if (self.statusFresh) self.statusWaiting = NO;
    if (!self.statusWaiting) {
        BOOL error = self.statusFresh && self.runtimeHasError;
        NSString *key = self.hasChanges ? @"PowerSchedule_Unsaved" :
            (self.awaitingSaveConfirmation ? @"PowerSchedule_Saved" :
                (self.statusFresh ? @"PowerSchedule_Refreshed" : @"PowerSchedule_SavedPlan"));
        [self showScheduleFeedback:error ? self.statusText : DOLocalizedString(key) error:error];
        self.awaitingSaveConfirmation = NO;
    }
    [self didRefreshStatus];
    // Runtime updates must not rebuild or detach the inline time wheel.
    if (self.tableView.numberOfSections > 1) [UIView performWithoutAnimation:^{
        NSIndexSet *sections = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(1, self.tableView.numberOfSections - 1)];
        [self.tableView reloadSections:sections withRowAnimation:UITableViewRowAnimationNone];
        [self.tableView layoutIfNeeded];
        [self refreshScheduleGlassFrames];
    }];
}

- (void)didRefreshStatus {}

- (void)showScheduleFeedback:(NSString *)message error:(BOOL)error
{
    self.feedbackLabel.text = message;
    self.feedbackLabel.textColor = error ? UIColor.systemOrangeColor : UIColor.secondaryLabelColor;
}

- (void)didSaveConfiguration:(NSDictionary *)configuration
{
    self.savedConfiguration = configuration;
    self.awaitingSaveConfirmation = YES;
    [self setTimePickerExpanded:NO animated:YES];
    [self draftChanged];
    [[[UINotificationFeedbackGenerator alloc] init] notificationOccurred:UINotificationFeedbackTypeSuccess];
    UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, DOLocalizedString(@"PowerSchedule_Saved"));
    [self requestStatus];
}

- (NSString *)statusText
{
    if (![self.savedConfiguration[@"Enabled"] boolValue])
        return DOLocalizedString(@"LowPowerSchedule_Disabled");
    NSDictionary *status = self.runtimeStatus;
    NSString *state = self.statusFresh ? status[@"State"] : nil;
    if ([state isEqual:@"unsupported"]) return DOLocalizedString(@"LowPowerSchedule_Unsupported");
    if ([state isEqual:@"applyFailed"]) return DOLocalizedString(@"LowPowerSchedule_ApplyFailed");
    if ([state isEqual:@"runtimeFailed"]) return DOLocalizedString(@"LowPowerSchedule_RuntimeFailed");
    NSDictionary *next = self.statusFresh ? status[@"Next"] : nil;
    if (![next isKindOfClass:NSDictionary.class] || ![next[@"Date"] isKindOfClass:NSDate.class])
        next = rcLowPowerEvent(self.savedConfiguration, NSDate.date, rcLowPowerLocalCalendar(), YES);
    NSString *action = DOLocalizedString([next[@"PowerMode"] boolValue] ?
        @"LowPowerSchedule_OnAction" : @"LowPowerSchedule_OffAction");
    return [NSString stringWithFormat:DOLocalizedString(@"PowerSchedule_Next"), DOScheduleDateText(next[@"Date"]), action];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 2; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return section == 0 ? 4 : 1;
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    return DOLocalizedString(section == 0 ? @"LowPowerSchedule_Title" : @"LowPowerSchedule_Status");
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    return DOLocalizedString(section == 0 ? @"LowPowerSchedule_Footer" : @"LowPowerSchedule_RuntimeFooter");
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section
{
    UITableViewHeaderFooterView *footer = [[UITableViewHeaderFooterView alloc] initWithReuseIdentifier:nil];
    footer.backgroundView = [UIView new];
    footer.backgroundView.backgroundColor = UIColor.clearColor;
    UILabel *label = [UILabel new];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.text = [self tableView:tableView titleForFooterInSection:section];
    label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    label.adjustsFontForContentSizeCategory = YES;
    label.textColor = UIColor.secondaryLabelColor;
    label.numberOfLines = 0;
    [footer.contentView addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:footer.contentView.leadingAnchor constant:32],
        [label.trailingAnchor constraintEqualToAnchor:footer.contentView.trailingAnchor constant:-32],
        [label.topAnchor constraintEqualToAnchor:footer.contentView.topAnchor constant:16],
        [label.bottomAnchor constraintLessThanOrEqualToAnchor:footer.contentView.bottomAnchor constant:-20]
    ]];
    return footer;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section
{
    NSString *text = [self tableView:tableView titleForFooterInSection:section];
    // Reserve real padding outside the glass, including at accessibility font sizes.
    CGFloat width = MAX(80, CGRectGetWidth(tableView.bounds) - 104);
    CGRect rect = [text boundingRectWithSize:CGSizeMake(width, CGFLOAT_MAX)
        options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
        attributes:@{NSFontAttributeName: [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote]} context:nil];
    return ceil(rect.size.height) + 36;
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView { [self refreshScheduleGlassFrames]; }

- (void)configureStatusCell:(UITableViewCell *)cell
{
    cell.textLabel.text = self.statusText;
    cell.detailTextLabel.text = DOLocalizedString(@"PowerSchedule_TapRefresh");
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.accessibilityTraits |= UIAccessibilityTraitButton;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    if (self.statusWaiting) {
        UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
        [spinner startAnimating];
        cell.accessoryView = spinner;
    }
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:indexPath.section == 1 ? UITableViewCellStyleSubtitle : UITableViewCellStyleValue1 reuseIdentifier:nil];
    [self styleScheduleCell:cell];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    if (indexPath.section == 1) {
        [self configureStatusCell:cell];
    } else if (indexPath.row == 3) {
        if (self.timePickerExpanded) [self attachTimePickerToCell:cell];
    } else if (indexPath.row == 0) {
        cell.textLabel.text = DOLocalizedString(@"LowPowerSchedule_Enable");
        cell.accessoryView = self.enabledSwitch;
    } else {
        BOOL start = [self isStartRow:indexPath];
        cell.textLabel.text = DOLocalizedString(self.scheduleMode == 0 ?
            (start ? @"LowPowerSchedule_OnTime" : @"LowPowerSchedule_OffTime") :
            (start ? @"BatteryRecord_StartTime" : @"BatteryRecord_EndTime"));
        NSInteger minute = start ? self.lastStartMinute : self.lastEndMinute;
        cell.detailTextLabel.text =
            [NSString stringWithFormat:@"%02ld:%02ld", (long)(minute / 60), (long)(minute % 60)];
        cell.detailTextLabel.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleBody]
            scaledFontForFont:[UIFont monospacedDigitSystemFontOfSize:17 weight:UIFontWeightRegular]];
        cell.detailTextLabel.adjustsFontForContentSizeCategory = YES;
        cell.detailTextLabel.textColor = UIColor.systemBlueColor;
        BOOL isEditingTime = self.timePickerExpanded &&
            ((self.editingTime == 0 && start) || (self.editingTime == 1 && !start));
        cell.accessoryType = isEditingTime ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
        cell.tintColor = UIColor.systemBlueColor;
        cell.accessibilityTraits |= UIAccessibilityTraitButton;
        cell.accessibilityHint = DOLocalizedString(@"LowPowerSchedule_EditTime");
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        UIView *selected = [[UIView alloc] initWithFrame:CGRectZero];
        selected.backgroundColor = [UIColor colorWithWhite:1 alpha:0.05];
        cell.selectedBackgroundView = selected;
    }
    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return indexPath.section == 0 && indexPath.row == 3 ?
        (self.timePickerExpanded ? 232 : 0) : UITableViewAutomaticDimension;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell
    forRowAtIndexPath:(NSIndexPath *)indexPath
{
    [self styleScheduleCell:cell];
    if (indexPath.section == 0 && (indexPath.row == 1 || indexPath.row == 2)) {
        cell.detailTextLabel.textColor = UIColor.systemBlueColor;
        cell.detailTextLabel.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleBody]
            scaledFontForFont:[UIFont monospacedDigitSystemFontOfSize:17 weight:UIFontWeightRegular]];
    }
    [self refreshScheduleGlassFrames];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 1 && indexPath.row == 0) {
        [[[UISelectionFeedbackGenerator alloc] init] selectionChanged];
        [self requestStatus];
        return;
    }
    if (indexPath.section != 0 || indexPath.row == 0 || indexPath.row == 3) return;
    self.editingTime = [self isStartRow:indexPath] ? 0 : 1;
    self.timePicker.date = [self dateForMinute:self.editingTime == 0 ?
        self.lastStartMinute : self.lastEndMinute];
    self.timePicker.accessibilityLabel = DOLocalizedString(self.scheduleMode == 0 ?
        (self.editingTime == 0 ? @"LowPowerSchedule_OnTime" : @"LowPowerSchedule_OffTime") :
        (self.editingTime == 0 ? @"BatteryRecord_StartTime" : @"BatteryRecord_EndTime"));
    [self setTimePickerExpanded:YES animated:YES];
    [self updateTimeLabels];
    [self prepareTimeFeedback];
}

- (void)savePressed
{
    if (!self.hasChanges) {
        [self setTimePickerExpanded:NO animated:YES];
        return;
    }
    NSInteger start = self.lastStartMinute;
    NSInteger end = self.lastEndMinute;
    if (start == end) {
        [self showMessage:DOLocalizedString(@"LowPowerSchedule_SameTime")];
        return;
    }
    NSError *error = nil;
    if (![DOEnvironmentManager.sharedManager saveLowPowerScheduleEnabled:self.enabledSwitch.on
            startMinute:start endMinute:end error:&error]) {
        [self showMessage:[NSString stringWithFormat:DOLocalizedString(@"LowPowerSchedule_SaveFailed"),
            error.localizedDescription ?: @"Unknown"]];
        return;
    }
    [self didSaveConfiguration:[self loadScheduleConfiguration]];
}

- (void)showMessage:(NSString *)message
{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:self.title
        message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:DOLocalizedString(@"Button_OK")
        style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)backPressed
{
    if (self.backHandler) { self.backHandler(); return; }
    if (!self.hasChanges) {
        [self.navigationController popViewControllerAnimated:YES];
        return;
    }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:self.title
        message:DOLocalizedString(@"LowPowerSchedule_Discard") preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:DOLocalizedString(@"Button_Cancel")
        style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:DOLocalizedString(@"LowPowerSchedule_DiscardButton")
        style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
            [self.navigationController popViewControllerAnimated:YES];
        }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)edgeBack:(UIScreenEdgePanGestureRecognizer *)gesture
{
    if (gesture.state == UIGestureRecognizerStateEnded &&
        [gesture translationInView:self.view].x > 60 &&
        [gesture velocityInView:self.view].x > 80) [self backPressed];
}
@end
