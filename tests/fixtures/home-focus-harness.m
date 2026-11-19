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
@property(nonatomic, strong) UIViewPropertyAnimator *customGlassFocusAnimator;
@property(nonatomic) CGFloat customGlassAvatarNormalSize;
@property(nonatomic) CGFloat customGlassFocusProgress;
@property(nonatomic) CGFloat customGlassFocusPanStart;
@property(nonatomic) BOOL customGlassProfileFocusEnabled;
@property(nonatomic) BOOL customGlassAvatarWasDragged;
@property(nonatomic) CGPoint customGlassAvatarPressOrigin;
@property(nonatomic) BOOL homeAvatarShowsTemperature;
@property(nonatomic) BOOL informationVisible;
@property(nonatomic) NSUInteger homeThermalRevealGeneration;
@property(nonatomic) NSProcessInfoThermalState homeThermalState;
@property(nonatomic, strong) UIViewController *testPresentedController;
- (void)applyHomeAvatarDisplayMode;
- (void)revealHomeThermalStateInAvatar:(BOOL)animated;
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
@end

static NSUInteger CheckHomeFocus(UIViewController *host)
{
    BOOL revealWasConsumed = DOHomeThermalLaunchRevealConsumed;
    DOHomeThermalLaunchRevealConsumed = YES;
    BOOL animationsWereEnabled = UIView.areAnimationsEnabled;
    [UIView setAnimationsEnabled:NO];
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    id savedFocus = [defaults objectForKey:DOCustomGlassProfileFocusEnabledKey];
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
        for (NSValue *size in sizes) {
            home.view.frame = (CGRect){CGPointZero, size.CGSizeValue};
            [home.view setNeedsLayout];
            [home.view layoutIfNeeded];
            [home setCustomGlassProfileFocusEnabled:NO animated:NO persist:NO];
            CGRect original = home.customGlassAvatarContainerView.frame;
            CGRect profile = home.customGlassProfileView.frame;
            CGFloat travel = [home customGlassFocusTravel];
            CHECK(travel > 50);
            CHECK(!home.customGlassAvatarContainerView.hasAmbiguousLayout);
            pan.testVelocity = CGPointMake(400, 20);
            CHECK(![home gestureRecognizerShouldBegin:pan]);
            pan.testVelocity = CGPointMake(20, 400);
            CHECK([home gestureRecognizerShouldBegin:pan]);
            pan.testTranslation = CGPointZero;
            pan.testState = UIGestureRecognizerStateBegan;
            [home customGlassAvatarPanned:pan];
            pan.testTranslation = CGPointMake(500, travel / 2.0);
            pan.testState = UIGestureRecognizerStateChanged;
            [home customGlassAvatarPanned:pan];
            CHECK(fabs(home.customGlassAvatarContainerView.center.x - CGRectGetMidX(original)) < 0.5);
            CHECK(fabs(home.customGlassAvatarContainerView.center.y - CGRectGetMidY(original) - travel / 2.0) < 0.5);
            CHECK(fabs(home.customGlassActionGrid.alpha - 0.5) < 0.01);
            CHECK(home.customGlassActionGrid.transform.ty > 0);
            CHECK(!home.customGlassActionGrid.userInteractionEnabled);
            CHECK(CGRectEqualToRect(profile, home.customGlassProfileView.frame));
            pan.testState = UIGestureRecognizerStateEnded;
            [home customGlassAvatarPanned:pan];
            [home finishCustomGlassFocusAnimation];
            CHECK(home.customGlassProfileFocusEnabled);
            CHECK(home.customGlassActionGrid.alpha == 0 && home.jailbreakBtn.alpha == 0 && home.updateButton.alpha == 0);
            CHECK(home.customGlassActionGrid.accessibilityElementsHidden);
            CHECK(CGSizeEqualToSize(home.customGlassAvatarContainerView.bounds.size, original.size));
            CHECK(CGRectGetMaxY(home.customGlassAvatarContainerView.frame) <= CGRectGetMaxY(home.view.safeAreaLayoutGuide.layoutFrame));
            CHECK(CGRectGetMaxY(home.customGlassAvatarContainerView.frame) + DOHomeThermalHaloExtent(84.0) <= CGRectGetMaxY(home.view.safeAreaLayoutGuide.layoutFrame));
            CHECK(home.customGlassAvatarContainerView.userInteractionEnabled);
            for (NSNumber *end in @[@(UIGestureRecognizerStateCancelled), @(UIGestureRecognizerStateEnded)]) {
                pan.testState = UIGestureRecognizerStateBegan;
                pan.testTranslation = CGPointZero;
                [home customGlassAvatarPanned:pan];
                pan.testTranslation = CGPointMake(-500, -travel);
                pan.testState = UIGestureRecognizerStateChanged;
                [home customGlassAvatarPanned:pan];
                pan.testState = end.integerValue;
                [home customGlassAvatarPanned:pan];
                [home finishCustomGlassFocusAnimation];
                CHECK(home.customGlassProfileFocusEnabled == (end.integerValue == UIGestureRecognizerStateCancelled));
            }
            CHECK(CGRectEqualToRect(original, home.customGlassAvatarContainerView.frame));
            CHECK(home.customGlassActionGrid.alpha == 1 && home.customGlassActionGrid.userInteractionEnabled);
            CHECK(!home.customGlassActionGrid.accessibilityElementsHidden);
            CHECK(home.updateButton.alpha == 1);
            // A tiny drag must settle back even after a high initial velocity.
            pan.testTranslation = CGPointZero;
            pan.testState = UIGestureRecognizerStateBegan;
            [home customGlassAvatarPanned:pan];
            pan.testTranslation = CGPointMake(0, 2);
            pan.testState = UIGestureRecognizerStateEnded;
            [home customGlassAvatarPanned:pan];
            [home finishCustomGlassFocusAnimation];
            CHECK(!home.customGlassProfileFocusEnabled);
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
                    CHECK(((UIAlertController *)home.testPresentedController).actions.count == 3);
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
            }
            for (NSInteger state = 0; state < 4; state++) {
                [home displayHomeThermalState:(NSProcessInfoThermalState)state animate:YES];
                CHECK(home.homeThermalAvatarOverlay.statusLabel.text.length > 0);
                if (!UIAccessibilityIsReduceMotionEnabled()) CHECK([home.homeThermalHalo.glowLayer animationForKey:DOHomeThermalBreathKey] != nil);
            }
            [home.homeThermalHalo stopBreath];
            CHECK([home.homeThermalHalo.glowLayer animationForKey:DOHomeThermalBreathKey] == nil);
            cases++;
        }
        [home willMoveToParentViewController:nil];
        [home.view removeFromSuperview];
        [home removeFromParentViewController];
    } @finally {
        DOHomeThermalLaunchRevealConsumed = revealWasConsumed;
        [UIView setAnimationsEnabled:animationsWereEnabled];
        if (savedFocus) [defaults setObject:savedFocus forKey:DOCustomGlassProfileFocusEnabledKey];
        else [defaults removeObjectForKey:DOCustomGlassProfileFocusEnabledKey];
    }
    return cases;
}
