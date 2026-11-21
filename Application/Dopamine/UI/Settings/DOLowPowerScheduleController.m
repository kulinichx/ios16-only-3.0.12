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

// Public UIKit views only: both the track and selection have a full capsule radius.
@interface DOScheduleModeControl : UIControl
@property(nonatomic, strong) UIView *selectionView;
@property(nonatomic, strong) NSArray<UIButton *> *buttons;
@property(nonatomic) NSInteger selectedIndex;
@property(nonatomic) CGSize laidOutSize;
@property(nonatomic, strong) UIViewPropertyAnimator *selectionAnimator;
- (void)selectIndex:(NSInteger)index animated:(BOOL)animated;
@end

@implementation DOScheduleModeControl
- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = [UIColor colorWithWhite:1 alpha:0.10];
    self.clipsToBounds = YES;
    self.layer.cornerCurve = kCACornerCurveContinuous;
    self.selectionView = [UIView new];
    self.selectionView.userInteractionEnabled = NO;
    self.selectionView.backgroundColor = [UIColor colorWithWhite:1 alpha:0.20];
    self.selectionView.layer.cornerCurve = kCACornerCurveContinuous;
    [self addSubview:self.selectionView];
    NSMutableArray *buttons = [NSMutableArray new];
    NSArray *titles = @[DOLocalizedString(@"LowPowerSchedule_Title"), DOLocalizedString(@"BatteryRecord_Title")];
    for (NSInteger i = 0; i < titles.count; i++) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        button.tag = i;
        [button setTitle:titles[i] forState:UIControlStateNormal];
        [button setTitleColor:UIColor.labelColor forState:UIControlStateNormal];
        button.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
        button.titleLabel.adjustsFontForContentSizeCategory = YES;
        button.titleLabel.adjustsFontSizeToFitWidth = YES;
        button.titleLabel.minimumScaleFactor = 0.75;
        [button addTarget:self action:@selector(pressed:) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:button];
        [buttons addObject:button];
    }
    self.buttons = buttons;
    [self selectIndex:0 animated:NO];
    return self;
}
- (CGRect)selectionFrame
{
    CGFloat width = MAX(0, (CGRectGetWidth(self.bounds) - 8) / 2);
    NSInteger slot = self.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft ? 1 - self.selectedIndex : self.selectedIndex;
    return CGRectMake(4 + slot * width, 4, width, MAX(0, CGRectGetHeight(self.bounds) - 8));
}
- (void)finishSelection
{
    UIViewPropertyAnimator *animator = self.selectionAnimator;
    self.selectionAnimator = nil;
    if (animator.state == UIViewAnimatingStateActive) {
        [animator stopAnimation:NO];
        [animator finishAnimationAtPosition:UIViewAnimatingPositionEnd];
    }
}
- (void)layoutSubviews
{
    [super layoutSubviews];
    self.layer.cornerRadius = CGRectGetHeight(self.bounds) / 2;
    self.selectionView.layer.cornerRadius = MAX(0, (CGRectGetHeight(self.bounds) - 8) / 2);
    CGFloat width = CGRectGetWidth(self.bounds) / 2;
    for (UIButton *button in self.buttons) {
        NSInteger slot = self.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft ? 1 - button.tag : button.tag;
        button.frame = CGRectMake(slot * width, 0, width, CGRectGetHeight(self.bounds));
    }
    if (!CGSizeEqualToSize(self.laidOutSize, self.bounds.size)) {
        [self finishSelection];
        self.laidOutSize = self.bounds.size;
        self.selectionView.frame = [self selectionFrame];
    }
}
- (void)selectIndex:(NSInteger)index animated:(BOOL)animated
{
    [self finishSelection];
    self.selectedIndex = index;
    for (UIButton *button in self.buttons)
        button.accessibilityTraits = UIAccessibilityTraitButton | (button.tag == index ? UIAccessibilityTraitSelected : 0);
    CGRect target = [self selectionFrame];
    if (!animated || UIAccessibilityIsReduceMotionEnabled()) { self.selectionView.frame = target; return; }
    __weak typeof(self) weakSelf = self;
    self.selectionAnimator = [[UIViewPropertyAnimator alloc] initWithDuration:0.5 dampingRatio:0.86
        animations:^{ weakSelf.selectionView.frame = target; }];
    [self.selectionAnimator startAnimation];
}
- (void)pressed:(UIButton *)sender
{
    if (sender.tag == self.selectedIndex) return;
    self.selectedIndex = sender.tag;
    [self sendActionsForControlEvents:UIControlEventValueChanged];
}
@end

// Self-sizing rows can settle after the controller's layout/display callbacks.
// Update decorations only after UITableView has positioned its own content.
@interface DOScheduleTableView : UITableView
@property(nonatomic, copy) void (^didLayoutContent)(void);
@property(nonatomic) BOOL updatingBackdrop;
@end

@implementation DOScheduleTableView
- (void)layoutSubviews
{
    [super layoutSubviews];
    if (self.updatingBackdrop || !self.didLayoutContent) return;
    self.updatingBackdrop = YES;
    self.didLayoutContent();
    self.updatingBackdrop = NO;
}
@end

@interface DOPowerScheduleController () <UIGestureRecognizerDelegate>
@property(nonatomic, strong) UIPanGestureRecognizer *pagePan;
@property(nonatomic, strong) NSArray<DOLowPowerScheduleController *> *pages;
@property(nonatomic, strong) DOLowPowerScheduleController *selectedPage;
@property(nonatomic, strong) DOScheduleModeControl *modeControl;
@property(nonatomic, strong) UIView *contentView;
@property(nonatomic, strong) UIViewPropertyAnimator *pageAnimator;
@property(nonatomic, strong) DOLowPowerScheduleController *transitionFromPage;
@property(nonatomic, strong) DOLowPowerScheduleController *transitionToPage;
@property(nonatomic) BOOL transitionHasAppearance;
@property(nonatomic) BOOL pageVisible;
@property(nonatomic) CGSize contentSize;
@end

@implementation DOPowerScheduleController
- (BOOL)shouldAutomaticallyForwardAppearanceMethods { return NO; }
- (UIButton *)chromeButton:(NSString *)image action:(SEL)action label:(NSString *)label
{
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.tintColor = UIColor.labelColor;
    [button setImage:[UIImage systemImageNamed:image withConfiguration:
        [UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIImageSymbolWeightMedium]] forState:UIControlStateNormal];
    button.accessibilityLabel = label;
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}
- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.clearColor;
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.title = DOLocalizedString(@"PowerSchedule_Title");
    UIButton *back = [self chromeButton:@"chevron.left" action:@selector(backPressed) label:DOLocalizedString(@"Button_Cancel")];
    UILabel *title = [UILabel new];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.text = self.title;
    title.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    title.textColor = UIColor.labelColor;
    title.numberOfLines = 2;
    title.adjustsFontForContentSizeCategory = YES;
    title.textAlignment = NSTextAlignmentCenter;
    self.modeControl = [DOScheduleModeControl new];
    self.modeControl.translatesAutoresizingMaskIntoConstraints = NO;
    [self.modeControl addTarget:self action:@selector(modeChanged:) forControlEvents:UIControlEventValueChanged];
    self.contentView = [UIView new];
    self.contentView.translatesAutoresizingMaskIntoConstraints = NO;
    self.contentView.clipsToBounds = YES;
    self.pagePan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(pagePanned:)];
    self.pagePan.maximumNumberOfTouches = 1;
    self.pagePan.delegate = self;
    [self.contentView addGestureRecognizer:self.pagePan];
    for (UIView *view in @[back, title, self.modeControl, self.contentView]) [self.view addSubview:view];
    [NSLayoutConstraint activateConstraints:@[
        [back.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:10],
        [back.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:6],
        [back.widthAnchor constraintEqualToConstant:44], [back.heightAnchor constraintEqualToConstant:44],
        [title.leadingAnchor constraintEqualToAnchor:back.trailingAnchor constant:8],
        [title.centerXAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.centerXAnchor],
        [title.topAnchor constraintEqualToAnchor:back.topAnchor], [title.heightAnchor constraintGreaterThanOrEqualToConstant:44],
        [self.modeControl.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:12],
        [self.modeControl.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:20],
        [self.modeControl.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-20],
        [self.modeControl.heightAnchor constraintEqualToConstant:44],
        [self.contentView.topAnchor constraintEqualToAnchor:self.modeControl.bottomAnchor constant:4],
        [self.contentView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.contentView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.contentView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
    self.pages = @[[DOLowPowerScheduleController new], [DOBatteryRecordController new]];
    __weak typeof(self) weakSelf = self;
    for (DOLowPowerScheduleController *page in self.pages) {
        page.backHandler = ^{ [weakSelf backPressed]; };
        [self addChildViewController:page];
        page.view.translatesAutoresizingMaskIntoConstraints = NO;
        page.view.hidden = YES;
        [self.contentView addSubview:page.view];
        for (UIGestureRecognizer *gesture in page.view.gestureRecognizers) {
            if ([gesture isKindOfClass:UIScreenEdgePanGestureRecognizer.class])
                [self.pagePan requireGestureRecognizerToFail:gesture];
        }
        [page.tableView.panGestureRecognizer requireGestureRecognizerToFail:self.pagePan];
        [NSLayoutConstraint activateConstraints:@[
            [page.view.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
            [page.view.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
            [page.view.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
            [page.view.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor]
        ]];
        [page didMoveToParentViewController:self];
    }
    [self selectPage:0];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(stopPageMotion:)
        name:UIApplicationWillResignActiveNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(stopPageMotion:)
        name:UIAccessibilityReduceMotionStatusDidChangeNotification object:nil];
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldReceiveTouch:(UITouch *)touch
{
    if (gesture != self.pagePan) return YES;
    if (!self.pageVisible || self.pageAnimator || self.presentedViewController || self.selectedPage.presentedViewController)
        return NO;
    for (UIView *view = touch.view; view && view != self.contentView; view = view.superview) {
        if ([view isKindOfClass:UIControl.class]) return NO;
    }
    return YES;
}

- (NSInteger)pageIndexForHorizontalMovement:(CGFloat)movement
{
    BOOL rightToLeft = self.contentView.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
    BOOL advances = rightToLeft ? movement > 0 : movement < 0;
    return self.modeControl.selectedIndex + (advances ? 1 : -1);
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gesture
{
    if (gesture != self.pagePan) return YES;
    CGPoint velocity = [self.pagePan velocityInView:self.contentView];
    if (fabs(velocity.x) <= fabs(velocity.y) * 1.4) return NO;
    NSInteger index = [self pageIndexForHorizontalMovement:velocity.x];
    return index >= 0 && index < (NSInteger)self.pages.count;
}

- (void)pagePanned:(UIPanGestureRecognizer *)gesture
{
    if (gesture.state != UIGestureRecognizerStateEnded || self.pageAnimator) return;
    CGPoint offset = [gesture translationInView:self.contentView];
    CGPoint velocity = [gesture velocityInView:self.contentView];
    if (fabs(offset.x) < 24 || fabs(offset.x) <= fabs(offset.y)) return;
    if (fabs(offset.x) < 56 && (fabs(velocity.x) < 420 || offset.x * velocity.x <= 0)) return;
    [self selectPage:[self pageIndexForHorizontalMovement:offset.x]];
}

- (void)stopPageMotion:(NSNotification *)notification { [self finishPageTransition]; }
- (void)modeChanged:(DOScheduleModeControl *)sender { [self selectPage:sender.selectedIndex]; }
- (void)finishPageTransition
{
    UIViewPropertyAnimator *animator = self.pageAnimator;
    self.pageAnimator = nil;
    if (animator.state == UIViewAnimatingStateActive) [animator stopAnimation:YES];
    DOLowPowerScheduleController *previous = self.transitionFromPage;
    DOLowPowerScheduleController *next = self.transitionToPage;
    self.transitionFromPage = nil;
    self.transitionToPage = nil;
    previous.view.hidden = YES;
    previous.view.alpha = 1;
    next.view.maskView = nil;
    next.view.transform = CGAffineTransformIdentity;
    if (self.transitionHasAppearance) {
        self.transitionHasAppearance = NO;
        [previous endAppearanceTransition];
        [next endAppearanceTransition];
    }
    self.contentView.userInteractionEnabled = YES;
    [self.modeControl finishSelection];
}
- (void)selectPage:(NSInteger)index
{
    if (index < 0 || index >= self.pages.count || self.selectedPage == self.pages[index]) return;
    [self finishPageTransition];
    DOLowPowerScheduleController *previous = self.selectedPage;
    DOLowPowerScheduleController *next = self.pages[index];
    BOOL animated = previous && self.pageVisible && !UIAccessibilityIsReduceMotionEnabled() && UIView.areAnimationsEnabled;
    self.selectedPage = next;
    [self.modeControl selectIndex:index animated:animated];
    self.transitionFromPage = previous;
    self.transitionToPage = next;
    self.transitionHasAppearance = self.pageVisible;
    if (self.transitionHasAppearance) {
        [previous beginAppearanceTransition:NO animated:animated];
        [next beginAppearanceTransition:YES animated:animated];
    }
    [self.view layoutIfNeeded];
    [next.view layoutIfNeeded];
    next.view.hidden = NO;
    if (!animated) { [self finishPageTransition]; return; }
    self.contentView.userInteractionEnabled = NO;
    // Reveal from the top without resizing rows or moving the persistent header.
    UIView *mask = [[UIView alloc] initWithFrame:CGRectMake(0, 0, CGRectGetWidth(next.view.bounds), 0)];
    mask.backgroundColor = UIColor.blackColor;
    next.view.maskView = mask;
    next.view.transform = CGAffineTransformMakeTranslation(0, -6);
    __weak typeof(self) weakSelf = self;
    UIViewPropertyAnimator *fade = [[UIViewPropertyAnimator alloc] initWithDuration:0.10 curve:UIViewAnimationCurveEaseOut
        animations:^{ previous.view.alpha = 0; }];
    self.pageAnimator = fade;
    [fade addCompletion:^(__unused UIViewAnimatingPosition position) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || self.transitionToPage != next) return;
        previous.view.hidden = YES;
        UIViewPropertyAnimator *reveal = [[UIViewPropertyAnimator alloc] initWithDuration:0.56 curve:UIViewAnimationCurveEaseOut animations:^{
            mask.frame = next.view.bounds;
            next.view.transform = CGAffineTransformIdentity;
        }];
        self.pageAnimator = reveal;
        [reveal addCompletion:^(__unused UIViewAnimatingPosition end) { [weakSelf finishPageTransition]; }];
        [reveal startAnimation];
    }];
    [fade startAnimation];
    [[[UISelectionFeedbackGenerator alloc] init] selectionChanged];
}
- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self.selectedPage beginAppearanceTransition:YES animated:animated];
    [self.view layoutIfNeeded];
}
- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    [self.selectedPage endAppearanceTransition];
    self.pageVisible = YES;
}
- (void)viewWillDisappear:(BOOL)animated
{
    [self finishPageTransition];
    [super viewWillDisappear:animated];
    self.pageVisible = NO;
    [self.selectedPage beginAppearanceTransition:NO animated:animated];
}
- (void)viewDidDisappear:(BOOL)animated
{
    [super viewDidDisappear:animated];
    [self.selectedPage endAppearanceTransition];
}
- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    if (!CGSizeEqualToSize(self.contentSize, self.contentView.bounds.size)) {
        if (self.pageAnimator) [self finishPageTransition];
        self.contentSize = self.contentView.bounds.size;
    }
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }

- (void)backPressed
{
    if (self.presentedViewController) return;
    [self.navigationController popViewControllerAnimated:YES];
}
@end

@interface DOLowPowerScheduleController ()
@property(nonatomic, strong) UILabel *feedbackLabel;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, DOCustomLiquidGlassView *> *sectionGlassViews;
@property(nonatomic, strong) UIImpactFeedbackGenerator *timeFeedback;
@property(nonatomic, copy) NSArray<NSLayoutConstraint *> *timePickerCellConstraints;
@property(nonatomic) int statusToken;
@property(nonatomic, copy) NSString *pendingRevision;
@property(nonatomic) BOOL deferCurrentWindow;
@end

@implementation DOLowPowerScheduleController

- (NSString *)scheduleTitle { return DOLocalizedString(@"LowPowerSchedule_Title"); }
- (NSInteger)scheduleMode { return 0; }
- (NSDictionary *)loadScheduleConfiguration { return [DOEnvironmentManager.sharedManager lowPowerScheduleConfiguration]; }
- (NSDictionary *)loadRuntimeStatus { return [DOEnvironmentManager.sharedManager lowPowerScheduleStatus]; }
- (const char *)scheduleStatusNotification { return RC_LOW_POWER_STATUS_CHANGED; }
- (BOOL)isScheduleVisible
{
    UIViewController *page = self;
    while (page.parentViewController && page.parentViewController != self.navigationController)
        page = page.parentViewController;
    return self.viewIfLoaded.window && !self.view.hidden &&
        (![page isKindOfClass:DOPowerScheduleController.class] || ((DOPowerScheduleController *)page).selectedPage == self) &&
        self.navigationController.topViewController == page;
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
    [self.enabledSwitch addTarget:self action:@selector(settingsChanged)
                forControlEvents:UIControlEventValueChanged];
    self.lastStartMinute = [self.savedConfiguration[@"StartMinute"] integerValue];
    self.lastEndMinute = [self.savedConfiguration[@"EndMinute"] integerValue];
    self.timePicker = [self timePickerForMinute:self.lastStartMinute];
    self.timePicker.accessibilityLabel = DOLocalizedString(self.scheduleMode == 0 ? @"LowPowerSchedule_OnTime" : @"BatteryRecord_StartTime");

    DOScheduleTableView *tableView = [[DOScheduleTableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView = tableView;
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.backgroundColor = UIColor.clearColor;
    UIView *background = [UIView new];
    background.backgroundColor = UIColor.clearColor;
    background.userInteractionEnabled = NO;
    self.tableView.backgroundView = background;
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

    self.feedbackLabel = [UILabel new];
    self.feedbackLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.feedbackLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    self.feedbackLabel.adjustsFontForContentSizeCategory = YES;
    self.feedbackLabel.textColor = UIColor.secondaryLabelColor;
    self.feedbackLabel.numberOfLines = 0;
    self.feedbackLabel.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:self.feedbackLabel];
    [NSLayoutConstraint activateConstraints:@[
        [self.feedbackLabel.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:6],
        [self.feedbackLabel.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:20],
        [self.feedbackLabel.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-20],
        [self.feedbackLabel.heightAnchor constraintGreaterThanOrEqualToConstant:18],
        [self.tableView.topAnchor constraintEqualToAnchor:self.feedbackLabel.bottomAnchor constant:4],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
    UIScreenEdgePanGestureRecognizer *edge = [[UIScreenEdgePanGestureRecognizer alloc]
        initWithTarget:self action:@selector(edgeBack:)];
    edge.edges = UIRectEdgeLeft;
    [self.view addGestureRecognizer:edge];
    [self.tableView.panGestureRecognizer requireGestureRecognizerToFail:edge];

    __weak typeof(self) weakSelf = self;
    tableView.didLayoutContent = ^{ [weakSelf refreshScheduleGlassFrames]; };
    int token = -1;
    if (notify_register_dispatch([self scheduleStatusNotification], &token, dispatch_get_main_queue(),
        ^(__unused int value) {
            if ([weakSelf isScheduleVisible]) [weakSelf refreshStatus];
        }) == NOTIFY_STATUS_OK)
        self.statusToken = token;
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(applicationDidBecomeActive:)
        name:UIApplicationDidBecomeActiveNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(applicationDidBecomeActive:)
        name:UIApplicationSignificantTimeChangeNotification object:nil];
    if (self.scheduleMode == 0) [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(powerStateChanged:)
        name:NSProcessInfoPowerStateDidChangeNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(applicationWillResignActive:)
        name:UIApplicationWillResignActiveNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(scheduleThemeDidChange:)
        name:DOScheduleThemeDidChangeNotification object:nil];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self refreshStatus];
    [self refreshScheduleGlassFrames];
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
    UIView *background = self.tableView.backgroundView;
    if (!background) return;
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
        if (!glass) {
            glass = [[DOCustomLiquidGlassView alloc] initWithCornerRadius:18 baseTintAlpha:0.038];
            glass.userInteractionEnabled = NO;
            glass.materialScale = 0.88;
            glass.preferredCornerRadius = 18;
            glass.layer.cornerRadius = 18;
            glass.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner |
                kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner;
            self.sectionGlassViews[@(section)] = glass;
            [background addSubview:glass];
        }
        CGRect glassFrame = [self.tableView convertRect:CGRectInset(frame, 1, 0.5) toView:background];
        if (glass.hidden) glass.hidden = NO;
        if (!CGRectEqualToRect(glass.frame, glassFrame)) glass.frame = glassFrame;
    }
}

- (void)refreshScheduleAppearance
{
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

- (BOOL)writeConfiguration:(NSDictionary *)configuration error:(NSError **)error
{
    return [DOEnvironmentManager.sharedManager saveLowPowerScheduleConfiguration:configuration error:error];
}

- (void)settingsChanged
{
    if (self.scheduleMode != 0 || !self.enabledSwitch.on || [self.savedConfiguration[@"Enabled"] boolValue]) {
        [self applySettings];
        return;
    }
    NSDictionary *draft = @{ @"Version": @1, @"Enabled": @YES,
        @"Revision": self.savedConfiguration[@"Revision"], @"StartMinute": @(self.lastStartMinute),
        @"EndMinute": @(self.lastEndMinute) };
    NSDate *now = NSDate.date;
    NSCalendar *calendar = rcLowPowerLocalCalendar();
    NSDictionary *previous = rcLowPowerEvent(draft, now, calendar, NO);
    if (![previous[@"PowerMode"] boolValue]) {
        [self applySettings];
        return;
    }
    NSDate *end = rcLowPowerEvent(draft, now, calendar, YES)[@"Date"];
    self.enabledSwitch.on = NO;
    if (self.presentedViewController) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:DOLocalizedString(@"LowPowerSchedule_StartNowTitle")
        message:[NSString stringWithFormat:DOLocalizedString(@"LowPowerSchedule_StartNowMessage"), DOScheduleDateText(end)]
        preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:DOLocalizedString(@"LowPowerSchedule_StartNow") style:UIAlertActionStyleDefault
        handler:^(__unused UIAlertAction *action) { [weakSelf enablePlanDeferringCurrentWindow:NO]; }]];
    [alert addAction:[UIAlertAction actionWithTitle:DOLocalizedString(@"LowPowerSchedule_WaitForNext") style:UIAlertActionStyleDefault
        handler:^(__unused UIAlertAction *action) { [weakSelf enablePlanDeferringCurrentWindow:YES]; }]];
    [alert addAction:[UIAlertAction actionWithTitle:DOLocalizedString(@"LowPowerSchedule_AdjustTime") style:UIAlertActionStyleCancel
        handler:^(__unused UIAlertAction *action) {
            if (!weakSelf.timePickerExpanded || weakSelf.editingTime != 0) {
                [weakSelf tableView:weakSelf.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:1 inSection:0]];
            }
        }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)enablePlanDeferringCurrentWindow:(BOOL)defer
{
    self.deferCurrentWindow = defer;
    self.enabledSwitch.on = YES;
    [self applySettings];
    self.deferCurrentWindow = NO;
}

- (void)restoreControls
{
    self.enabledSwitch.on = [self.savedConfiguration[@"Enabled"] boolValue];
    self.lastStartMinute = [self.savedConfiguration[@"StartMinute"] integerValue];
    self.lastEndMinute = [self.savedConfiguration[@"EndMinute"] integerValue];
    self.timePicker.date = [self dateForMinute:self.editingTime == 0 ? self.lastStartMinute : self.lastEndMinute];
    [self updateTimeLabels];
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
    [self applySettings];
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
    if (self.timePickerExpanded == expanded) return;
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

// Read the persisted result on entry and on real scheduler events. No query loop.
- (void)applicationDidBecomeActive:(NSNotification *)notification
{
    if ([self isScheduleVisible]) [self refreshStatus];
}
- (void)applicationWillResignActive:(NSNotification *)notification { self.timeFeedback = nil; }
- (BOOL)statusFresh
{
    return [self.runtimeStatus[@"Updated"] isKindOfClass:NSDate.class] &&
        [self.runtimeStatus[@"Revision"] isEqual:self.savedConfiguration[@"Revision"]];
}

- (BOOL)runtimeHasError
{
    return [@[@"unsupported", @"applyFailed", @"runtimeFailed", @"timerFailed"] containsObject:self.runtimeStatus[@"State"] ?: @""];
}

- (void)refreshStatus
{
    NSArray *previousHistory = self.runtimeStatus[@"History"] ?: @[];
    self.runtimeStatus = [self loadRuntimeStatus];
    [self didRefreshStatus];
    // Preserve cells, footers, wheel and scroll position when only status changes.
    NSIndexPath *statusPath = [NSIndexPath indexPathForRow:0 inSection:1];
    UITableViewCell *statusCell = [self.tableView cellForRowAtIndexPath:statusPath];
    BOOL textChanged = statusCell && ![statusCell.textLabel.text isEqual:self.statusText];
    BOOL rowsChanged = self.tableView.numberOfSections > 1 &&
        [self.tableView numberOfRowsInSection:1] != [self tableView:self.tableView numberOfRowsInSection:1];
    BOOL historyChanged = ![previousHistory isEqual:self.runtimeStatus[@"History"] ?: @[]];
    [UIView performWithoutAnimation:^{
        if (rowsChanged) [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:1] withRowAnimation:UITableViewRowAnimationNone];
        else if (textChanged) {
            [self configureStatusCell:statusCell];
            [self.tableView beginUpdates];
            [self.tableView endUpdates];
        }
        if (historyChanged && self.tableView.numberOfSections > 2)
            [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:2] withRowAnimation:UITableViewRowAnimationNone];
        [self.tableView layoutIfNeeded];
        [self refreshScheduleGlassFrames];
    }];
}

- (void)didRefreshStatus {}

- (void)powerStateChanged:(NSNotification *)notification
{
    dispatch_async(dispatch_get_main_queue(), ^{ if (self.isScheduleVisible) [self refreshStatus]; });
}

- (void)finishScheduleWait:(NSString *)request
{
    if (![self.pendingRevision isEqual:request]) return;
    self.pendingRevision = nil;
    // Read once even if the status notification was missed.
    [self refreshStatus];
}

- (void)beginScheduleWait:(NSString *)request
{
    self.pendingRevision = request;
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [weakSelf finishScheduleWait:request];
    });
}

- (void)showScheduleFeedback:(NSString *)message error:(BOOL)error
{
    self.feedbackLabel.text = message;
    self.feedbackLabel.textColor = error ? UIColor.systemOrangeColor : UIColor.secondaryLabelColor;
}


- (BOOL)stopIsPending
{
    NSString *state = self.statusFresh ? self.runtimeStatus[@"State"] : nil;
    if ([state isEqual:@"disabled"] || (self.statusFresh && self.runtimeHasError)) return NO;
    return self.pendingRevision != nil || ([state isEqual:@"verifying"] &&
        [self.runtimeStatus[@"Updated"] timeIntervalSinceNow] > -5);
}

- (BOOL)canRetryStop
{
    return self.scheduleMode == 0 && ![self.savedConfiguration[@"Enabled"] boolValue] && !self.stopIsPending &&
        NSProcessInfo.processInfo.lowPowerModeEnabled;
}

- (NSString *)disabledStatusWithSystemLowPower:(BOOL)on
{
    if (self.stopIsPending) return DOLocalizedString(@"LowPowerSchedule_Stopping");
    if (!on) return DOLocalizedString(@"LowPowerSchedule_Disabled");
    if (self.statusFresh && self.runtimeHasError &&
        [self.runtimeStatus[@"DisableRequest"] isEqual:self.savedConfiguration[@"DisableRequest"]])
        return DOLocalizedString(@"LowPowerSchedule_DisableFailed");
    return DOLocalizedString(@"LowPowerSchedule_SystemOn");
}

- (NSString *)statusText
{
    BOOL systemOn = NSProcessInfo.processInfo.lowPowerModeEnabled;
    if (![self.savedConfiguration[@"Enabled"] boolValue])
        return [self disabledStatusWithSystemLowPower:systemOn];
    NSDictionary *status = self.runtimeStatus;
    NSString *state = self.statusFresh ? status[@"State"] : nil;
    if ([state isEqual:@"unsupported"]) return DOLocalizedString(@"LowPowerSchedule_Unsupported");
    if ([state isEqual:@"applyFailed"]) return DOLocalizedString(@"LowPowerSchedule_ApplyFailed");
    if ([@[@"runtimeFailed", @"timerFailed", @"calendarFailed", @"invalidConfiguration"] containsObject:state ?: @""])
        return DOLocalizedString(@"LowPowerSchedule_RuntimeFailed");
    NSDictionary *next = status[@"Next"];
    if ([state isEqual:@"verifying"]) return DOLocalizedString(@"LowPowerSchedule_Confirming");
    if (![state isEqual:@"scheduled"] || ![next isKindOfClass:NSDictionary.class] ||
        ![next[@"Date"] isKindOfClass:NSDate.class] || [next[@"Date"] timeIntervalSinceNow] <= 0)
        return DOLocalizedString(self.pendingRevision ? @"LowPowerSchedule_Confirming" : @"LowPowerSchedule_Unconfirmed");
    if (![next[@"PowerMode"] boolValue] && systemOn)
        return [NSString stringWithFormat:DOLocalizedString(@"LowPowerSchedule_OnUntil"), DOScheduleDateText(next[@"Date"])];
    if (![next[@"PowerMode"] boolValue])
        next = rcLowPowerNextStart(self.savedConfiguration, NSDate.date, rcLowPowerLocalCalendar());
    if (!next) return DOLocalizedString(@"LowPowerSchedule_RuntimeFailed");
    NSString *key = systemOn ? @"LowPowerSchedule_SystemOnNextStart" : @"LowPowerSchedule_WaitingForStart";
    return [NSString stringWithFormat:DOLocalizedString(key), DOScheduleDateText(next[@"Date"])];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 2; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return section == 0 ? 4 : (self.canRetryStop ? 2 : 1);
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    return DOLocalizedString(section == 0 ? @"LowPowerSchedule_Title" : @"LowPowerSchedule_Status");
}
- (NSString *)footerTextForSection:(NSInteger)section
{
    return DOLocalizedString(section == 0 ? @"LowPowerSchedule_Footer" : @"LowPowerSchedule_RuntimeFooter");
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section
{
    UIView *footer = [UIView new];
    footer.backgroundColor = UIColor.clearColor;
    UILabel *label = [UILabel new];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.text = [self footerTextForSection:section];
    label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    label.adjustsFontForContentSizeCategory = YES;
    label.textColor = UIColor.secondaryLabelColor;
    label.numberOfLines = 0;
    [footer addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:footer.leadingAnchor constant:32],
        [label.trailingAnchor constraintEqualToAnchor:footer.trailingAnchor constant:-32],
        [label.topAnchor constraintEqualToAnchor:footer.topAnchor constant:16],
        [label.bottomAnchor constraintLessThanOrEqualToAnchor:footer.bottomAnchor constant:-20]
    ]];
    return footer;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section
{
    NSString *text = [self footerTextForSection:section];
    // Reserve real padding outside the glass, including at accessibility font sizes.
    CGFloat width = MAX(80, CGRectGetWidth(tableView.bounds) - 64);
    CGRect rect = [text boundingRectWithSize:CGSizeMake(width, CGFLOAT_MAX)
        options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
        attributes:@{NSFontAttributeName: [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote]} context:nil];
    return ceil(rect.size.height) + 36;
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView { [self refreshScheduleGlassFrames]; }

- (void)configureStatusCell:(UITableViewCell *)cell
{
    cell.textLabel.text = self.statusText;
    cell.detailTextLabel.text = nil;
    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.accessibilityTraits = UIAccessibilityTraitStaticText;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:indexPath.section == 1 ? UITableViewCellStyleSubtitle : UITableViewCellStyleValue1 reuseIdentifier:nil];
    [self styleScheduleCell:cell];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    if (indexPath.section == 1) {
        if (indexPath.row == 1) {
            cell.textLabel.text = DOLocalizedString(@"LowPowerSchedule_RetryStop");
            cell.textLabel.textColor = UIColor.systemBlueColor;
            cell.accessibilityTraits = UIAccessibilityTraitButton;
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        } else {
            [self configureStatusCell:cell];
        }
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
    [tableView setNeedsLayout];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 1 && indexPath.row == 1 && self.canRetryStop) {
        [self retryStoppingLowPower];
        return;
    }
    if (indexPath.section != 0 || indexPath.row == 0 || indexPath.row == 3) return;
    NSInteger field = [self isStartRow:indexPath] ? 0 : 1;
    if (self.timePickerExpanded && self.editingTime == field) {
        [self setTimePickerExpanded:NO animated:YES];
        return;
    }
    self.editingTime = field;
    self.timePicker.date = [self dateForMinute:self.editingTime == 0 ?
        self.lastStartMinute : self.lastEndMinute];
    self.timePicker.accessibilityLabel = DOLocalizedString(self.scheduleMode == 0 ?
        (self.editingTime == 0 ? @"LowPowerSchedule_OnTime" : @"LowPowerSchedule_OffTime") :
        (self.editingTime == 0 ? @"BatteryRecord_StartTime" : @"BatteryRecord_EndTime"));
    [self setTimePickerExpanded:YES animated:YES];
    [self updateTimeLabels];
    [self prepareTimeFeedback];
}

- (NSString *)prepareConfiguration:(NSMutableDictionary *)configuration
{
    if (![configuration[@"Enabled"] boolValue]) {
        [configuration removeObjectForKey:@"SkipThrough"];
        return nil;
    }
    if ([self.savedConfiguration[@"Enabled"] boolValue]) return nil;

    NSDate *now = NSDate.date;
    NSCalendar *calendar = rcLowPowerLocalCalendar();
    NSDictionary *previous = rcLowPowerEvent(configuration, now, calendar, NO);
    if (![previous[@"PowerMode"] boolValue]) {
        // Enabling outside the window must not replay an earlier OFF.
        configuration[@"SkipThrough"] = previous[@"Date"];
    } else if (self.deferCurrentWindow) {
        configuration[@"SkipThrough"] = rcLowPowerEvent(configuration, now, calendar, YES)[@"Date"];
    } else {
        [configuration removeObjectForKey:@"SkipThrough"];
    }
    return nil;
}

- (void)retryStoppingLowPower
{
    NSMutableDictionary *configuration = [self.savedConfiguration mutableCopy];
    NSString *request = NSUUID.UUID.UUIDString;
    configuration[@"Revision"] = request;
    configuration[@"DisableRequest"] = request;
    NSError *error = nil;
    if (![self writeConfiguration:configuration error:&error]) {
        [self showScheduleFeedback:[NSString stringWithFormat:DOLocalizedString(@"LowPowerSchedule_SaveFailed"),
            error.localizedDescription ?: DOLocalizedString(@"Unknown")] error:YES];
        return;
    }
    self.savedConfiguration = configuration;
    [self beginScheduleWait:request];
    [self showScheduleFeedback:nil error:NO];
    [self refreshStatus];
}

- (BOOL)applySettings
{
    if (!self.hasChanges) return YES;
    NSInteger start = self.lastStartMinute, end = self.lastEndMinute;
    NSMutableDictionary *configuration = [self.savedConfiguration mutableCopy];
    configuration[@"Enabled"] = @(self.enabledSwitch.on);
    configuration[@"StartMinute"] = @(start);
    configuration[@"EndMinute"] = @(end);
    configuration[@"Revision"] = NSUUID.UUID.UUIDString;
    BOOL stopping = !self.enabledSwitch.on && [self.savedConfiguration[@"Enabled"] boolValue];
    if (stopping) {
        configuration[@"DisableRequest"] = configuration[@"Revision"];
        if (self.scheduleMode == 0) [configuration removeObjectForKey:@"SkipThrough"];
    }
    else if (self.enabledSwitch.on) [configuration removeObjectForKey:@"DisableRequest"];
    NSString *message = start == end ? DOLocalizedString(@"LowPowerSchedule_SameTime") : nil;
    if (!message && !stopping) message = [self prepareConfiguration:configuration];
    NSError *error = nil;
    if (!message && ![self writeConfiguration:configuration error:&error])
        message = [NSString stringWithFormat:DOLocalizedString(@"LowPowerSchedule_SaveFailed"),
            error.localizedDescription ?: DOLocalizedString(@"Unknown")];
    if (message) {
        [self restoreControls];
        [self showScheduleFeedback:message error:YES];
        return NO;
    }
    self.savedConfiguration = configuration;
    if (stopping || (self.scheduleMode == 0 && self.enabledSwitch.on)) {
        [self beginScheduleWait:configuration[@"Revision"]];
    } else if (self.enabledSwitch.on) {
        self.pendingRevision = nil;
    }
    [self showScheduleFeedback:nil error:NO];
    [self refreshStatus];
    return YES;
}

- (void)showMessage:(NSString *)message
{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:self.title
        message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:DOLocalizedString(@"Supporter_OK")
        style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)backPressed
{
    if (self.backHandler) { self.backHandler(); return; }
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)edgeBack:(UIScreenEdgePanGestureRecognizer *)gesture
{
    if (gesture.state == UIGestureRecognizerStateEnded &&
        [gesture translationInView:self.view].x > 60 &&
        [gesture velocityInView:self.view].x > 80) [self backPressed];
}
@end
