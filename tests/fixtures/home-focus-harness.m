// Compile and exercise the production avatar views, gesture handlers, reveal,
// and layout callbacks. Only the surrounding home screen/services are synthetic.
#define DOLocalizedString(key) (key)
/* PRODUCTION_HOME_VIEWS */

@interface HomeTestPan : UIPanGestureRecognizer
@property(nonatomic) UIGestureRecognizerState testState;
@property(nonatomic) CGPoint testTranslation;
@property(nonatomic) CGPoint testVelocity;
@end
@implementation HomeTestPan
- (UIGestureRecognizerState)state { return self.testState; }
- (CGPoint)translationInView:(UIView *)view { return self.testTranslation; }
- (CGPoint)velocityInView:(UIView *)view { return self.testVelocity; }
@end

@interface HomeTestLongPress : UILongPressGestureRecognizer
@property(nonatomic) UIGestureRecognizerState testState;
@property(nonatomic) CGPoint testLocation;
@end
@implementation HomeTestLongPress
- (UIGestureRecognizerState)state { return self.testState; }
- (CGPoint)locationInView:(UIView *)view { return self.testLocation; }
@end

@interface HomeFocusHarness : UIViewController <UIGestureRecognizerDelegate>
/* PRODUCTION_HOME_ENTRANCE_PROPERTIES */
@property(nonatomic, strong) UIView *customGlassProfileView;
@property(nonatomic, strong) UIView *customGlassJailbreakPlaceholder;
@property(nonatomic, strong) UIView *customGlassActionGrid;
@property(nonatomic, strong) UIView *customGlassAvatarContainerView;
@property(nonatomic, strong) UIView *jailbreakBtn;
@property(nonatomic, strong) UIView *updateButton;
@property(nonatomic, strong) NSLayoutConstraint *customGlassJailbreakCenterYConstraint;
@property(nonatomic, strong) UILabel *customGlassUsernameLabel;
@property(nonatomic, strong) UILabel *customGlassSystemLabel;
@property(nonatomic, strong) UILabel *customGlassMottoLabel;
@property(nonatomic, strong) NSArray<UIView *> *customGlassHeaderSubtitleLabels;
@property(nonatomic, strong) UIImageView *customGlassAvatarPhotoView;
@property(nonatomic, strong) UIImageView *customGlassAvatarFallbackIconView;
@property(nonatomic, strong) DOHomeThermalHaloView *homeThermalHalo;
@property(nonatomic, strong) DOHomeThermalStatusView *homeThermalAvatarOverlay;
@property(nonatomic, strong) UIPanGestureRecognizer *customGlassAvatarPan;
@property(nonatomic, strong) UILongPressGestureRecognizer *customGlassAvatarLongPress;
@property(nonatomic, strong) UIViewPropertyAnimator *customGlassAvatarAnimator;
@property(nonatomic) CGFloat customGlassAvatarNormalSize;
@property(nonatomic) CGFloat customGlassAvatarOffset;
@property(nonatomic) CGFloat customGlassAvatarPanStart;
@property(nonatomic) BOOL customGlassAvatarHidden;
@property(nonatomic) BOOL customGlassAvatarWasDragged;
@property(nonatomic) CGPoint customGlassAvatarPressOrigin;
@property(nonatomic) BOOL homeAvatarShowsTemperature;
@property(nonatomic) BOOL customGlassAvatarHiddenRight;
@property(nonatomic, strong) UIPanGestureRecognizer *customGlassAvatarLeftEdge;
@property(nonatomic, strong) UIPanGestureRecognizer *customGlassAvatarRightEdge;
@property(nonatomic, strong) UIView *customGlassAvatarMaterialView;
@property(nonatomic, strong) NSTimer *homeThermalRevealTimer;
@property(nonatomic) BOOL informationVisible;
@property(nonatomic) BOOL observingHomeThermalState;
@property(nonatomic) BOOL homeThermalRevealActive;
@property(nonatomic) NSUInteger homeThermalRevealGeneration;
@property(nonatomic) NSProcessInfoThermalState homeThermalState;
@property(nonatomic, strong) UIViewController *testPresentedController;
- (void)applyHomeAvatarDisplayMode;
- (void)updateHomeThermalInteriorBreath;
- (void)revealHomeThermalStateInAvatar:(BOOL)animated;
- (void)revealHomeThermalStateInAvatar:(BOOL)animated force:(BOOL)force;
- (void)finishHomeEntrance;
@end

@implementation HomeFocusHarness
- (BOOL)requireCustomGlassSupporterAuthorization { return YES; }
- (void)presentCustomGlassAvatarPicker {}
- (void)presentViewController:(UIViewController *)controller animated:(BOOL)animated completion:(void (^)(void))completion
{
    self.testPresentedController = controller;
    if (completion) completion();
}
/* PRODUCTION_HOME_FOCUS */
/* PRODUCTION_HOME_THERMAL */
/* PRODUCTION_HOME_ENTRANCE */
@end

// The avatar moves through transform, which leaves its layout center unchanged.
// Convert its bounds to the home coordinate system to measure the displayed
// geometry; reading center (or frame with a nonidentity transform) is incorrect.
static CGRect HomeAvatarRect(HomeFocusHarness *home)
{
    UIView *avatar = home.customGlassAvatarContainerView;
    return [avatar convertRect:avatar.bounds toView:home.view];
}

static void CheckHomeAvatarRect(HomeFocusHarness *home, CGRect expected, NSString *stage)
{
    CGRect actual = HomeAvatarRect(home);
    if (fabs(actual.origin.x - expected.origin.x) >= 0.5 ||
        fabs(actual.origin.y - expected.origin.y) >= 0.5 ||
        fabs(actual.size.width - expected.size.width) >= 0.5 ||
        fabs(actual.size.height - expected.size.height) >= 0.5) {
        NSString *reason = [NSString stringWithFormat:@"%@: avatar %@, expected %@, viewport %@, progress %.3f, transform %@",
            stage, NSStringFromCGRect(actual), NSStringFromCGRect(expected),
            NSStringFromCGSize(home.view.bounds.size), home.customGlassAvatarOffset,
            NSStringFromCGAffineTransform(home.customGlassAvatarContainerView.transform)];
        @throw [NSException exceptionWithName:@"LayoutFailure" reason:reason userInfo:nil];
    }
}

static NSUInteger CheckHomeFocus(UIViewController *host)
{
    BOOL revealWasConsumed = DOHomeThermalLaunchRevealConsumed;
    BOOL entranceWasConsumed = DOHomeEntranceConsumed;
    NSString *visibilityKey = @"DOCustomGlassTheme.AvatarVisibility";
    id savedVisibility = [NSUserDefaults.standardUserDefaults objectForKey:visibilityKey];
    DOHomeThermalLaunchRevealConsumed = YES;
    BOOL animationsWereEnabled = UIView.areAnimationsEnabled;
    [UIView setAnimationsEnabled:NO];
    NSUInteger cases = 0;
    NSArray<NSValue *> *sizes = @[
        [NSValue valueWithCGSize:CGSizeMake(320, 568)], [NSValue valueWithCGSize:CGSizeMake(393, 852)],
        [NSValue valueWithCGSize:CGSizeMake(852, 393)], [NSValue valueWithCGSize:CGSizeMake(744, 1133)],
        [NSValue valueWithCGSize:CGSizeMake(1133, 744)], [NSValue valueWithCGSize:CGSizeMake(834, 1194)]
    ];
    @try {
        HomeFocusHarness *home = [HomeFocusHarness new];
        [host addChildViewController:home];
        [host.view addSubview:home.view];
        [home didMoveToParentViewController:host];
        home.customGlassAvatarNormalSize = 84.0;
        home.customGlassProfileView = [UIView new];
        home.customGlassJailbreakPlaceholder = [UIView new];
        home.customGlassAvatarContainerView = [UIView new];
        home.customGlassActionGrid = [UIView new];
        home.jailbreakBtn = [UIView new];
        home.updateButton = [UIView new];
        home.homeEntranceHeader = [[UIView alloc] initWithFrame:CGRectMake(40, 8, 240, 40)];
        home.homeEntranceLeftColumn = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 120, 100)];
        home.homeEntranceRightColumn = [[UIView alloc] initWithFrame:CGRectMake(140, 0, 120, 100)];
        [home.view addSubview:home.homeEntranceHeader];
        [home.customGlassActionGrid addSubview:home.homeEntranceLeftColumn];
        [home.customGlassActionGrid addSubview:home.homeEntranceRightColumn];
        home.customGlassUsernameLabel = [UILabel new];
        home.customGlassSystemLabel = [UILabel new];
        home.customGlassMottoLabel = [UILabel new];
        home.customGlassHeaderSubtitleLabels = @[[UILabel new]];
        home.customGlassAvatarPhotoView = [UIImageView new];
        home.customGlassAvatarFallbackIconView = [UIImageView new];
        home.homeThermalHalo = [[DOHomeThermalHaloView alloc] initWithFrame:CGRectMake(0, 0, 84, 84)];
        home.homeThermalAvatarOverlay = [[DOHomeThermalStatusView alloc] initWithFrame:CGRectMake(0, 0, 84, 84)];
        HomeTestLongPress *press = [HomeTestLongPress new];
        home.customGlassAvatarLongPress = press;
        HomeTestPan *pan = [HomeTestPan new];
        home.customGlassAvatarPan = pan;
        HomeTestPan *left = [HomeTestPan new], *right = [HomeTestPan new];
        home.customGlassAvatarLeftEdge = left; home.customGlassAvatarRightEdge = right;
        home.customGlassAvatarMaterialView = [UIView new];
        for (UIView *view in @[home.customGlassProfileView, home.customGlassJailbreakPlaceholder,
            home.customGlassActionGrid, home.jailbreakBtn, home.updateButton, home.customGlassAvatarContainerView]) {
            view.translatesAutoresizingMaskIntoConstraints = NO;
            [home.view addSubview:view];
        }
        for (UIView *view in @[home.customGlassUsernameLabel, home.customGlassSystemLabel, home.customGlassMottoLabel])
            [home.customGlassProfileView addSubview:view];
        for (UIView *view in @[home.customGlassAvatarPhotoView, home.customGlassAvatarFallbackIconView,
            home.homeThermalHalo, home.homeThermalAvatarOverlay])
            [home.customGlassAvatarContainerView addSubview:view];
        home.customGlassJailbreakCenterYConstraint = [home.jailbreakBtn.centerYAnchor constraintEqualToAnchor:home.customGlassJailbreakPlaceholder.centerYAnchor constant:-12.0];
        [NSLayoutConstraint activateConstraints:@[
            [home.customGlassProfileView.topAnchor constraintEqualToAnchor:home.view.topAnchor constant:55],
            [home.customGlassProfileView.centerXAnchor constraintEqualToAnchor:home.view.centerXAnchor],
            [home.customGlassProfileView.widthAnchor constraintEqualToConstant:200],
            [home.customGlassProfileView.heightAnchor constraintEqualToConstant:150],
            [home.customGlassAvatarContainerView.topAnchor constraintEqualToAnchor:home.customGlassProfileView.topAnchor],
            [home.customGlassAvatarContainerView.centerXAnchor constraintEqualToAnchor:home.customGlassProfileView.centerXAnchor],
            [home.customGlassAvatarContainerView.widthAnchor constraintEqualToConstant:84],
            [home.customGlassAvatarContainerView.heightAnchor constraintEqualToConstant:84],
            [home.customGlassJailbreakPlaceholder.centerXAnchor constraintEqualToAnchor:home.view.centerXAnchor],
            [home.customGlassJailbreakPlaceholder.bottomAnchor constraintEqualToAnchor:home.view.safeAreaLayoutGuide.bottomAnchor constant:-24],
            [home.customGlassJailbreakPlaceholder.widthAnchor constraintEqualToConstant:260],
            [home.customGlassJailbreakPlaceholder.heightAnchor constraintEqualToConstant:44],
            home.customGlassJailbreakCenterYConstraint,
            [home.jailbreakBtn.widthAnchor constraintEqualToConstant:260],
            [home.jailbreakBtn.heightAnchor constraintEqualToConstant:44],
            [home.jailbreakBtn.centerXAnchor constraintEqualToAnchor:home.view.centerXAnchor],
            [home.customGlassActionGrid.centerXAnchor constraintEqualToAnchor:home.view.centerXAnchor],
            [home.customGlassActionGrid.widthAnchor constraintEqualToConstant:260],
            [home.customGlassActionGrid.heightAnchor constraintEqualToConstant:100],
            [home.customGlassActionGrid.topAnchor constraintEqualToAnchor:home.customGlassProfileView.bottomAnchor constant:10],
            [home.updateButton.centerXAnchor constraintEqualToAnchor:home.view.centerXAnchor],
            [home.updateButton.widthAnchor constraintEqualToConstant:100],
            [home.updateButton.heightAnchor constraintEqualToConstant:30],
            [home.updateButton.bottomAnchor constraintEqualToAnchor:home.customGlassJailbreakPlaceholder.topAnchor constant:-12]
        ]];
        home.informationVisible = YES;
        home.observingHomeThermalState = YES;
        // Production press feedback must restore after release, cancellation and disabling.
        UIView *pressSurface = [[UIView alloc] initWithFrame:CGRectMake(20, 20, 160, 60)];
        DOHomePressButton *pressButton = [DOHomePressButton buttonWithType:UIButtonTypeCustom];
        pressButton.frame = pressSurface.bounds;
        pressButton.pressSurface = pressSurface;
        [pressSurface addSubview:pressButton];
        [home.view addSubview:pressSurface];
        __block NSUInteger actionCount = 0;
        [pressButton addAction:[UIAction actionWithHandler:^(__kindof UIAction *action) { actionCount++; }]
            forControlEvents:UIControlEventTouchUpInside];
        pressButton.highlighted = YES;
        CHECK(fabs(pressSurface.transform.a - (UIAccessibilityIsReduceMotionEnabled() ? 1.0 : 0.97)) < 0.001);
        pressButton.highlighted = NO;
        CHECK(CGAffineTransformIsIdentity(pressSurface.transform));
        CHECK(actionCount == 0);
        [pressButton sendActionsForControlEvents:UIControlEventTouchUpInside];
        CHECK(actionCount == 1);
        pressButton.highlighted = YES;
        pressButton.enabled = NO;
        CHECK(CGAffineTransformIsIdentity(pressSurface.transform));
        [pressSurface removeFromSuperview];
        for (NSValue *size in sizes) {
            home.view.frame = (CGRect){CGPointZero, size.CGSizeValue};
            [home.view setNeedsLayout];
            [home.view layoutIfNeeded];
            [home setCustomGlassAvatarHidden:NO right:YES animated:NO];
            CGRect original = HomeAvatarRect(home);
            CGRect profile = home.customGlassProfileView.frame;
            CHECK(!home.customGlassAvatarContainerView.hasAmbiguousLayout);
            // Exercise the actual launch methods: pre-frame hiding, edge directions,
            // readiness gating, interruption, normal completion and no replay.
            DOHomeEntranceConsumed = NO;
            home.homeEntranceReady = NO;
            [home prepareHomeEntrance];
            CHECK(DOHomeEntranceConsumed);
            if (!UIAccessibilityIsReduceMotionEnabled() && !NSProcessInfo.processInfo.lowPowerModeEnabled) {
                CHECK(home.homeEntrancePrepared);
                for (UIView *view in home.homeEntranceViews) CHECK(view.alpha == 0);
                CheckHomeAvatarRect(home, original, @"entrance avatar stays in place");
                CHECK(CGAffineTransformIsIdentity(home.customGlassProfileView.transform));
                CHECK(CGRectGetMaxY([home.homeEntranceHeader convertRect:home.homeEntranceHeader.bounds toView:home.view]) < 0);
                CHECK(CGRectGetMaxX([home.homeEntranceLeftColumn convertRect:home.homeEntranceLeftColumn.bounds toView:home.view]) < 0);
                CHECK(CGRectGetMinX([home.homeEntranceRightColumn convertRect:home.homeEntranceRightColumn.bounds toView:home.view]) > size.CGSizeValue.width);
                CHECK(CGRectGetMinY([home.jailbreakBtn convertRect:home.jailbreakBtn.bounds toView:home.view]) > size.CGSizeValue.height);
                [home startHomeEntranceIfReady];
                CHECK(home.homeEntranceAnimator == nil);
                [UIView setAnimationsEnabled:YES];
                home.homeEntranceReady = YES;
                [home startHomeEntranceIfReady];
                UIViewPropertyAnimator *entrance = home.homeEntranceAnimator;
                CHECK(entrance != nil);
                [home startHomeEntranceIfReady];
                CHECK(home.homeEntranceAnimator == entrance);
                NSArray<UIView *> *entranceViews = home.homeEntranceViews;
                if (cases == 0) {
                    // Let one entrance really finish; other sizes interrupt halfway.
                    [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1.85]];
                } else {
                    [entrance pauseAnimation];
                    entrance.fractionComplete = 0.45;
                    [home finishHomeEntrance];
                }
                CHECK(!home.homeEntrancePrepared && home.homeEntranceAnimator == nil);
                for (UIView *view in entranceViews) {
                    CHECK(view.alpha == 1);
                    CHECK(CGAffineTransformIsIdentity(view.transform));
                }
                [UIView setAnimationsEnabled:NO];
                [home prepareHomeEntrance];
                CHECK(!home.homeEntrancePrepared);
                // A scene can disappear after preparation, before animation starts.
                DOHomeEntranceConsumed = NO;
                [home prepareHomeEntrance];
                [home finishHomeEntrance];
                CHECK(home.homeEntranceAnimator == nil && home.customGlassAvatarContainerView.alpha == 1);
                CheckHomeAvatarRect(home, original, @"interrupted entrance restored");
            } else {
                CHECK(!home.homeEntrancePrepared && home.customGlassAvatarContainerView.alpha == 1);
            }
            pan.testVelocity = CGPointMake(20, 400);
            CHECK(![home gestureRecognizerShouldBegin:pan]);
            for (NSNumber *direction in @[@-1, @1]) {
                CGFloat dx = direction.doubleValue * 70;
                pan.testVelocity = CGPointMake(dx * 5, 0);
                CHECK([home gestureRecognizerShouldBegin:pan]);
                pan.testTranslation = CGPointZero; pan.testState = UIGestureRecognizerStateBegan;
                [home customGlassAvatarPanned:pan];
                pan.testTranslation = CGPointMake(dx, 0); pan.testState = UIGestureRecognizerStateChanged;
                [home customGlassAvatarPanned:pan];
                CheckHomeAvatarRect(home, CGRectOffset(original, dx, 0), @"horizontal drag");
                pan.testState = UIGestureRecognizerStateEnded; [home customGlassAvatarPanned:pan];
                [home finishCustomGlassAvatarAnimation];
                CHECK(home.customGlassAvatarHidden);
                CHECK(home.customGlassAvatarLeftEdge.enabled && home.customGlassAvatarRightEdge.enabled);
                CHECK([NSUserDefaults.standardUserDefaults integerForKey:visibilityKey] == 2);
                CHECK(dx < 0 ? CGRectGetMaxX(HomeAvatarRect(home)) < 0 : CGRectGetMinX(HomeAvatarRect(home)) > size.CGSizeValue.width);
                CHECK(home.customGlassActionGrid.alpha == 1 && home.jailbreakBtn.alpha == 1 && home.updateButton.alpha == 1);
                CHECK(home.customGlassActionGrid.userInteractionEnabled);
                CHECK(CGRectEqualToRect(profile, home.customGlassProfileView.frame));
                CHECK([home.homeThermalHalo.glowLayer animationForKey:DOHomeThermalBreathKey] == nil);
                // Restore from the opposite side, including cancellation first.
                HomeTestPan *edge = dx < 0 ? right : left;
                for (NSNumber *end in @[@(UIGestureRecognizerStateCancelled), @(UIGestureRecognizerStateEnded)]) {
                    edge.testVelocity = CGPointMake(dx * 5, 0);
                    CHECK([home gestureRecognizerShouldBegin:edge]);
                    edge.testTranslation = CGPointZero; edge.testState = UIGestureRecognizerStateBegan;
                    [home customGlassAvatarPanned:edge];
                    edge.testTranslation = CGPointMake(dx, 0); edge.testState = UIGestureRecognizerStateChanged;
                    [home customGlassAvatarPanned:edge];
                    edge.testState = end.integerValue; [home customGlassAvatarPanned:edge];
                    [home finishCustomGlassAvatarAnimation];
                    CHECK(home.customGlassAvatarHidden == (end.integerValue == UIGestureRecognizerStateCancelled));
                    CHECK([NSUserDefaults.standardUserDefaults integerForKey:visibilityKey] ==
                        (end.integerValue == UIGestureRecognizerStateCancelled ? 2 : 1));
                }
                CheckHomeAvatarRect(home, original, @"edge restored");
            }
            pan.testTranslation = CGPointZero; pan.testState = UIGestureRecognizerStateBegan;
            [home customGlassAvatarPanned:pan];
            pan.testTranslation = CGPointMake(2, 0); pan.testVelocity = CGPointMake(800, 0);
            pan.testState = UIGestureRecognizerStateEnded; [home customGlassAvatarPanned:pan];
            [home finishCustomGlassAvatarAnimation]; CHECK(!home.customGlassAvatarHidden);
            CheckHomeAvatarRect(home, original, @"tiny flick restored");
            // Holding still opens the selector; moving while held must never open it.
            pan.testState = UIGestureRecognizerStatePossible;
            for (NSNumber *move in @[@YES, @NO]) {
                home.testPresentedController = nil;
                press.testLocation = CGPointMake(160, 100);
                press.testState = UIGestureRecognizerStateBegan;
                [home customGlassAvatarLongPressed:press];
                if (move.boolValue) press.testLocation = CGPointMake(190, 100);
                press.testState = UIGestureRecognizerStateEnded;
                [home customGlassAvatarLongPressed:press];
                CHECK((home.testPresentedController != nil) == !move.boolValue);
                if (!move.boolValue) {
                    CHECK(((UIAlertController *)home.testPresentedController).actions.count == 6);
                    if (home.testPresentedController.popoverPresentationController)
                        CHECK(home.testPresentedController.popoverPresentationController.sourceView == home.customGlassAvatarContainerView);
                }
            }
            home.testPresentedController = nil;
            for (NSNumber *mode in @[@YES, @NO]) {
                home.homeAvatarShowsTemperature = mode.boolValue;
                [home applyHomeAvatarDisplayMode];
                CHECK(home.homeThermalAvatarOverlay.alpha == (mode.boolValue ? 1 : 0));
                CHECK(home.customGlassAvatarPhotoView.alpha == (mode.boolValue ? 0 : 1));
                CHECK(home.homeThermalAvatarOverlay.textStack.alpha == 0);
                CHECK(([home.homeThermalAvatarOverlay.breathingLayer animationForKey:DOHomeThermalBreathKey] != nil) ==
                    (mode.boolValue && (!UIAccessibilityIsReduceMotionEnabled() && !NSProcessInfo.processInfo.lowPowerModeEnabled)));
            }
            home.homeAvatarShowsTemperature = YES;
            [home applyHomeAvatarDisplayMode];
            for (NSInteger state = 0; state < 4; state++) {
                [home displayHomeThermalState:(NSProcessInfoThermalState)state animate:YES];
                CHECK(home.homeThermalAvatarOverlay.statusLabel.text.length > 0);
                if ((!UIAccessibilityIsReduceMotionEnabled() && !NSProcessInfo.processInfo.lowPowerModeEnabled)) CHECK([home.homeThermalHalo.glowLayer animationForKey:DOHomeThermalBreathKey] != nil);
                CHECK(([home.homeThermalAvatarOverlay.breathingLayer animationForKey:DOHomeThermalBreathKey] != nil) ==
                    (!UIAccessibilityIsReduceMotionEnabled() && !NSProcessInfo.processInfo.lowPowerModeEnabled));
                CHECK(home.homeThermalAvatarOverlay.textStack.layer.animationKeys.count == 0);
                CHECK(home.homeThermalAvatarOverlay.statusLabel.layer.animationKeys.count == 0);
            }
            // Leaving the page or stopping thermal observation must stop the
            // interior effect, even when the persistent temperature mode is on.
            home.informationVisible = NO;
            [home updateHomeThermalInteriorBreath];
            CHECK([home.homeThermalAvatarOverlay.breathingLayer animationForKey:DOHomeThermalBreathKey] == nil);
            home.informationVisible = YES;
            [home updateHomeThermalInteriorBreath];
            home.observingHomeThermalState = NO;
            [home applyHomeAvatarDisplayMode];
            CHECK([home.homeThermalAvatarOverlay.breathingLayer animationForKey:DOHomeThermalBreathKey] == nil);
            home.observingHomeThermalState = YES;
            home.homeAvatarShowsTemperature = NO;
            home.homeThermalRevealActive = YES;
            [home updateHomeThermalInteriorBreath];
            CHECK(([home.homeThermalAvatarOverlay.breathingLayer animationForKey:DOHomeThermalBreathKey] != nil) ==
                (!UIAccessibilityIsReduceMotionEnabled() && !NSProcessInfo.processInfo.lowPowerModeEnabled));
            [home applyHomeAvatarDisplayMode];
            CHECK(!home.homeThermalRevealActive);
            CHECK([home.homeThermalAvatarOverlay.breathingLayer animationForKey:DOHomeThermalBreathKey] == nil);
            [home.homeThermalHalo stopBreath];
            CHECK([home.homeThermalHalo.glowLayer animationForKey:DOHomeThermalBreathKey] == nil);
            // Force a real reveal, then fire the one-shot timer to test its final state.
            home.homeAvatarShowsTemperature = YES;
            [home revealHomeThermalStateInAvatar:NO force:YES];
            CHECK(home.homeThermalRevealTimer != nil);
            CHECK(home.homeThermalAvatarOverlay.textStack.alpha == 1);
            [home.homeThermalRevealTimer fire];
            [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
            CHECK(home.homeThermalAvatarOverlay.textStack.alpha == 0);
            CHECK(home.homeThermalAvatarOverlay.alpha == 1);
            CHECK(!home.homeThermalRevealActive);
            [home revealHomeThermalStateInAvatar:NO force:YES];
            [home applyHomeAvatarDisplayMode];
            CHECK(home.homeThermalRevealTimer == nil);
            // Automatic fading preserves automatic mode; explicit choices survive reload.
            [home selectHomeAvatarVisibilityMode:0];
            [home finishCustomGlassAvatarAnimation];
            CHECK(home.homeAvatarHideTimer != nil);
            [home.homeAvatarHideTimer fire];
            [home finishCustomGlassAvatarAnimation];
            CHECK(home.customGlassAvatarHidden && home.homeAvatarHideTimer == nil);
            CHECK([NSUserDefaults.standardUserDefaults integerForKey:visibilityKey] == 0);
            CHECK([home.homeThermalHalo.glowLayer animationForKey:DOHomeThermalBreathKey] == nil);
            [home restoreHomeAvatarVisibilityPreference];
            CHECK(!home.customGlassAvatarHidden);
            [home selectHomeAvatarVisibilityMode:2];
            [home finishCustomGlassAvatarAnimation];
            [home restoreHomeAvatarVisibilityPreference];
            DOHomeEntranceConsumed = NO;
            [home prepareHomeEntrance];
            [home finishHomeEntrance];
            CHECK(home.customGlassAvatarHidden);
            CHECK(CGRectGetMinX(HomeAvatarRect(home)) > size.CGSizeValue.width);
            [home selectHomeAvatarVisibilityMode:1];
            [home finishCustomGlassAvatarAnimation];
            [home restoreHomeAvatarVisibilityPreference];
            CHECK(!home.customGlassAvatarHidden && home.homeAvatarHideTimer == nil);
            [home selectHomeAvatarVisibilityMode:0];
            [home finishCustomGlassAvatarAnimation];
            NSTimer *cancelledTimer = home.homeAvatarHideTimer;
            [home cancelHomeAvatarAutoHide];
            CHECK(!cancelledTimer.valid && home.homeAvatarHideTimer == nil);
            cases++;
        }
        [home willMoveToParentViewController:nil];
        [home.view removeFromSuperview];
        [home removeFromParentViewController];
    } @finally {
        DOHomeThermalLaunchRevealConsumed = revealWasConsumed;
        DOHomeEntranceConsumed = entranceWasConsumed;
        if (savedVisibility) [NSUserDefaults.standardUserDefaults setObject:savedVisibility forKey:visibilityKey];
        else [NSUserDefaults.standardUserDefaults removeObjectForKey:visibilityKey];
        [UIView setAnimationsEnabled:animationsWereEnabled];
    }
    return cases;
}
