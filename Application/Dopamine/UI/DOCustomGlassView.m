#import "DOCustomGlassView.h"
#import "DOCustomGlassMediaStore.h"
#import "DOGlobalAppearance.h"
#import "DOUIManager.h"
#import "DOSupporterLicense.h"
#import "Settings/DOSettingsController.h"
#import <PhotosUI/PhotosUI.h>
#import <Photos/Photos.h>
#import <AVFoundation/AVFoundation.h>

@interface DOCustomWallpaperBlurView : UIView

@property(nonatomic, strong) UIVisualEffectView *fallbackBlurView;
@property(nonatomic, assign) CGFloat blurIntensity;

- (void)setBlurIntensity:(CGFloat)blurIntensity;

@end

@implementation DOCustomWallpaperBlurView

@synthesize blurIntensity = _blurIntensity;

+ (Class)layerClass
{
    Class backdropClass = NSClassFromString(@"CABackdropLayer");
    return backdropClass ?: [CALayer class];
}

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        _blurIntensity = 0.0;
        self.backgroundColor = UIColor.clearColor;
        self.userInteractionEnabled = NO;
        self.clipsToBounds = YES;
        [self setBlurIntensity:0.0];
    }
    return self;
}

- (void)setBlurIntensity:(CGFloat)blurIntensity
{
    _blurIntensity = DOCustomGlassClamp01(blurIntensity);

    BOOL isBackdropLayer = [NSStringFromClass(self.layer.class) containsString:@"Backdrop"];
    if (isBackdropLayer) {
        CGFloat radius = 22.0 * pow(_blurIntensity, 1.10);
        NSMutableArray *filters = [NSMutableArray array];

        if (radius > 0.05) {
            id blur = DOCustomGlassCreateCAFilter(@"gaussianBlur");
            if (blur) {
                [blur setValue:@(radius) forKey:@"inputRadius"];
                [blur setValue:@YES forKey:@"inputNormalizeEdges"];
                [blur setValue:@YES forKey:@"inputHardEdges"];
                [filters addObject:blur];
            }
        }

        [self.layer setValue:filters forKey:@"filters"];
        [self.layer setValue:@1.0 forKey:@"scale"];
        [self.fallbackBlurView removeFromSuperview];
        self.fallbackBlurView = nil;
    }
    else {
        if (!self.fallbackBlurView) {
            UIBlurEffect *effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleRegular];
            self.fallbackBlurView = [[UIVisualEffectView alloc] initWithEffect:effect];
            self.fallbackBlurView.userInteractionEnabled = NO;
            [self addSubview:self.fallbackBlurView];
        }
        self.fallbackBlurView.alpha = _blurIntensity;
    }
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    self.fallbackBlurView.frame = self.bounds;
}

- (void)didMoveToWindow
{
    [super didMoveToWindow];

    // CABackdropLayer can keep a stale sampling state when a controller is
    // pushed, popped, and then recreated. Rebuild the gaussian filter after
    // the view is attached to a real window so repeated entries behave exactly
    // like the first presentation instead of waiting for a wallpaper change.
    if (self.window) {
        CGFloat blurIntensity = self.blurIntensity;
        __weak typeof(self) weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf setBlurIntensity:blurIntensity];
            [weakSelf.layer setNeedsDisplay];
            [weakSelf setNeedsLayout];
        });
    }
}

@end

@implementation DOCustomLiquidGlassView

+ (Class)layerClass
{
    Class backdropClass = NSClassFromString(@"CABackdropLayer");
    return backdropClass ?: [CALayer class];
}

- (instancetype)initWithCornerRadius:(CGFloat)cornerRadius baseTintAlpha:(CGFloat)baseTintAlpha
{
    self = [super initWithFrame:CGRectZero];
    if (self) {
        _preferredCornerRadius = MAX(0.0, cornerRadius);
        _baseTintAlpha = MAX(0.0, baseTintAlpha);
        _materialScale = 1.0;
        _materialBodyScale = 1.0;
        _materialOpticalScale = 1.0;
        _materialBackdropScale = 1.0;
        _materialSpecularScale = 1.0;
        _materialEdgeDarkScale = 1.0;
        _suppressBackdrop = NO;
        _lastRenderedShortDimension = 0.0;

        self.backgroundColor = UIColor.clearColor;
        self.clipsToBounds = YES;
        self.layer.masksToBounds = YES;
        self.layer.cornerRadius = _preferredCornerRadius;
        self.layer.cornerCurve = kCACornerCurveContinuous;

        _neutralTintView = [[UIView alloc] initWithFrame:CGRectZero];
        _neutralTintView.userInteractionEnabled = NO;
        [self addSubview:_neutralTintView];

        _contentView = [[UIView alloc] initWithFrame:CGRectZero];
        _contentView.translatesAutoresizingMaskIntoConstraints = NO;
        _contentView.backgroundColor = UIColor.clearColor;
        _contentView.layer.zPosition = 10.0;
        [self addSubview:_contentView];
        [NSLayoutConstraint activateConstraints:@[
            [_contentView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_contentView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_contentView.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_contentView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor]
        ]];

        // Glass V2.2: the optical language is perimeter-only. The material body
        // comes from backdrop + neutral tint; highlight owns only three thin,
        // directional rails inspired by Mango's specular/boost/dark structure.
        _specularGradientLayer = [CAGradientLayer layer];
        _specularGradientLayer.startPoint = CGPointMake(0.0, 0.0);
        _specularGradientLayer.endPoint = CGPointMake(1.0, 1.0);
        _specularGradientLayer.locations = @[@0.0, @0.34, @0.50, @0.66, @1.0];
        _specularGradientLayer.zPosition = 901.0;
        _specularMaskLayer = [CAShapeLayer layer];
        _specularMaskLayer.fillColor = UIColor.clearColor.CGColor;
        _specularMaskLayer.strokeColor = UIColor.whiteColor.CGColor;
        _specularMaskLayer.lineWidth = 1.30;
        _specularGradientLayer.mask = _specularMaskLayer;
        [self.layer addSublayer:_specularGradientLayer];

        _specularBoostGradientLayer = [CAGradientLayer layer];
        _specularBoostGradientLayer.startPoint = CGPointMake(0.0, 0.0);
        _specularBoostGradientLayer.endPoint = CGPointMake(1.0, 1.0);
        _specularBoostGradientLayer.locations = @[@0.0, @0.22, @0.50, @0.78, @1.0];
        _specularBoostGradientLayer.zPosition = 902.0;
        _specularBoostMaskLayer = [CAShapeLayer layer];
        _specularBoostMaskLayer.fillColor = UIColor.clearColor.CGColor;
        _specularBoostMaskLayer.strokeColor = UIColor.whiteColor.CGColor;
        _specularBoostMaskLayer.lineWidth = 0.70;
        _specularBoostGradientLayer.mask = _specularBoostMaskLayer;
        [self.layer addSublayer:_specularBoostGradientLayer];

        // Rotate the dark field by 90 degrees relative to the bright field so the
        // opposite edges carry a quiet contour instead of a uniform black stroke.
        _specularDarkGradientLayer = [CAGradientLayer layer];
        _specularDarkGradientLayer.startPoint = CGPointMake(1.0, 0.0);
        _specularDarkGradientLayer.endPoint = CGPointMake(0.0, 1.0);
        _specularDarkGradientLayer.locations = @[@0.0, @0.24, @0.50, @0.76, @1.0];
        _specularDarkGradientLayer.zPosition = 900.0;
        _specularDarkMaskLayer = [CAShapeLayer layer];
        _specularDarkMaskLayer.fillColor = UIColor.clearColor.CGColor;
        _specularDarkMaskLayer.strokeColor = UIColor.whiteColor.CGColor;
        _specularDarkMaskLayer.lineWidth = 0.32;
        _specularDarkGradientLayer.mask = _specularDarkMaskLayer;
        [self.layer addSublayer:_specularDarkGradientLayer];

        [self reloadMaterial];
    }
    return self;
}

- (BOOL)usesDarkAppearance
{
    UIUserInterfaceStyle style = self.traitCollection.userInterfaceStyle;
    if (style == UIUserInterfaceStyleUnspecified)
        style = UIScreen.mainScreen.traitCollection.userInterfaceStyle;
    return style == UIUserInterfaceStyleDark;
}

- (CGFloat)surfaceGeometryScale
{
    CGFloat shortDimension = MIN(CGRectGetWidth(self.bounds), CGRectGetHeight(self.bounds));
    if (shortDimension <= 1.0)
        return MIN(0.92, MAX(0.42, 0.58 * MAX(0.35, self.materialScale)));

    // GlassFolders' folder-sized optical rail is intentionally richer than a
    // small action pill. Scale the geometry from the surface's short edge so
    // compact controls never inherit a folder-sized shoulder/filament.
    CGFloat normalized = DOCustomGlassClamp01((shortDimension - 42.0) / 118.0);
    CGFloat sizeScale = 0.42 + (0.50 * normalized);
    CGFloat roleScale = sqrt(MAX(0.18, MIN(1.15, self.materialScale)));
    return MIN(0.96, MAX(0.24, sizeScale * roleScale));
}

- (void)reloadMaterial
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    BOOL supporterVerified = DORHSupporterIsVerified();

    CGFloat blurStrength = supporterVerified && [defaults objectForKey:DOCustomGlassBlurIntensityKey] ?
        [defaults floatForKey:DOCustomGlassBlurIntensityKey] : 0.85;
    CGFloat transparency = supporterVerified && [defaults objectForKey:DOCustomGlassTransparencyKey] ?
        [defaults floatForKey:DOCustomGlassTransparencyKey] : 0.70;
    CGFloat highlight = supporterVerified && [defaults objectForKey:DOCustomGlassTintAlphaKey] ?
        [defaults floatForKey:DOCustomGlassTintAlphaKey] : 0.05;

    blurStrength = DOCustomGlassClamp01(blurStrength);
    transparency = DOCustomGlassClamp01(transparency);
    CGFloat highlightResponse = DOCustomGlassClamp01(highlight / 0.16);
    // R6 keeps the four Theme Settings controls strictly orthogonal:
    // wallpaper blur belongs to DOCustomWallpaperBlurView, Glass blur owns
    // only the local backdrop kernel, transparency owns only the material
    // body/transmission, and highlight owns only the optical rails.
    //
    // The response curves are intentionally wider than R5. On a phone-sized
    // panel, 20% vs 70% transparency and 30% vs 85% highlight must produce a
    // visible change without making the rail physically thicker.
    CGFloat blurResponse = pow(blurStrength, 0.92);
    CGFloat transmissionResponse = pow(transparency, 1.18);
    CGFloat bodyAuthority = 1.0 - transmissionResponse;

    // Match the proven GlassFolders response contract: edge luminance grows
    // much more clearly in the upper half of the slider while geometry barely
    // changes. 0% is genuinely quiet; 100% is obviously illuminated.
    CGFloat opticalResponse =
        (0.12 * highlightResponse) + (0.88 * pow(highlightResponse, 1.80));
    BOOL darkAppearance = [self usesDarkAppearance];
    BOOL darkGlassAppearance = supporterVerified &&
        [[defaults stringForKey:DOCustomGlassAppearanceKey] isEqualToString:DOCustomGlassAppearanceDark];

    // Per-surface optical role controls. The global sliders still define the
    // user's material; these scales only shape how a specific control expresses
    // that material (broad platter vs. concentrated interactive lens).
    CGFloat materialBackdropScale = MAX(0.0, MIN(1.25, self.materialBackdropScale));
    CGFloat materialSpecularScale = MAX(0.0, MIN(1.35, self.materialSpecularScale));
    CGFloat materialEdgeDarkScale = MAX(0.0, MIN(1.35, self.materialEdgeDarkScale));

    BOOL isBackdropLayer = [NSStringFromClass(self.layer.class) containsString:@"Backdrop"];
    if (isBackdropLayer && !self.suppressBackdrop) {
        CGFloat blurRadius = darkGlassAppearance ?
            (1.10 + (18.2 * blurResponse)) :
            (0.35 + (17.0 * blurResponse));
        // Dark Glass increases diffusion modestly, but preserves wallpaper
        // color transmission instead of turning the material into a black blur.
        // A structural platter gets a quieter, broader diffusion pass while
        // an interactive lens can keep a more concentrated local backdrop.
        // Scale the whole backdrop transform toward neutral rather than stacking
        // a second full-strength material on top of nested controls.
        blurRadius *= materialBackdropScale;
        CGFloat saturation = darkGlassAppearance ?
            (0.98 + (0.08 * blurResponse)) :
            (1.01 + (0.11 * blurResponse));
        saturation = 1.0 + ((saturation - 1.0) * materialBackdropScale);
        CGFloat brightness = darkGlassAppearance ?
            (-0.018 - (0.018 * bodyAuthority)) :
            (darkAppearance ?
                (0.006 + (0.012 * blurResponse)) :
                (0.002 + (0.006 * blurResponse)));
        brightness *= materialBackdropScale;

        id saturate = DOCustomGlassCreateCAFilter(@"colorSaturate");
        id brighten = DOCustomGlassCreateCAFilter(@"colorBrightness");
        id blur = DOCustomGlassCreateCAFilter(@"gaussianBlur");
        NSMutableArray *filters = [NSMutableArray array];

        if (saturate) {
            [saturate setValue:@(saturation) forKey:@"inputAmount"];
            [filters addObject:saturate];
        }
        if (brighten) {
            [brighten setValue:@(brightness) forKey:@"inputAmount"];
            [filters addObject:brighten];
        }
        if (blur && blurRadius > 0.05) {
            [blur setValue:@(blurRadius) forKey:@"inputRadius"];
            [blur setValue:@YES forKey:@"inputNormalizeEdges"];
            [blur setValue:@YES forKey:@"inputHardEdges"];
            [filters addObject:blur];
        }

        [self.layer setValue:filters forKey:@"filters"];
        [self.layer setValue:@1.0 forKey:@"scale"];
        [self.fallbackBlurView removeFromSuperview];
        self.fallbackBlurView = nil;
    }
    else if (isBackdropLayer) {
        // Group shells keep their own visible boundary/body but deliberately
        // skip a second backdrop blur underneath the three restart pills.
        [self.layer setValue:@[] forKey:@"filters"];
        [self.fallbackBlurView removeFromSuperview];
        self.fallbackBlurView = nil;
    }
    else {
        if (!self.fallbackBlurView) {
            UIBlurEffect *effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterial];
            self.fallbackBlurView = [[UIVisualEffectView alloc] initWithEffect:effect];
            self.fallbackBlurView.userInteractionEnabled = NO;
            [self insertSubview:self.fallbackBlurView atIndex:0];
        }
        self.fallbackBlurView.hidden = self.suppressBackdrop;
        self.fallbackBlurView.alpha = self.suppressBackdrop ? 0.0 :
            MIN(0.68, (0.18 + (0.50 * blurResponse)) * materialBackdropScale);
    }

    // Transparency owns a real material-body range now. R5's 0.8%...6.5%
    // neutral lift was too narrow, so Glass disappeared into both blurred and
    // low-contrast wallpapers. Keep a small body even at 100% transmission,
    // and let low transparency build a clearly separate optical layer.
    // Preserve a minimum material body even at maximum transparency. The user
    // should always be able to distinguish a Glass surface from the wallpaper;
    // transparency changes transmission, not whether the hierarchy exists.
    CGFloat tintAlpha =
        0.030 +
        (0.132 * bodyAuthority) +
        (0.12 * self.baseTintAlpha);
    if (darkAppearance)
        tintAlpha += 0.010 * bodyAuthority;

    // Keep the material body globally stable for a selected Glass appearance.
    // The CABackdropLayer already reacts naturally to local wallpaper content;
    // flipping the neutral body between black and white per surface made two
    // identical Main Glass views look like different materials on the same page.
    // Light Glass therefore keeps one faint white transmission body everywhere,
    // while Dark Glass keeps one dark neutral body everywhere.
    if (darkGlassAppearance) {
        CGFloat darkBodyAlpha =
            0.088 +
            (0.118 * bodyAuthority) +
            (0.10 * self.baseTintAlpha);
        self.neutralTintView.backgroundColor = UIColor.blackColor;
        self.neutralTintView.alpha = MIN(0.245, MAX(0.072, darkBodyAlpha));
    }
    else {
        self.neutralTintView.backgroundColor = UIColor.whiteColor;
        self.neutralTintView.alpha = MIN(0.190, tintAlpha);
    }
    self.neutralTintView.alpha *= MAX(0.0, MIN(1.0, self.materialBodyScale));

    CGFloat materialOpticalScale = MAX(0.0, MIN(1.25, self.materialOpticalScale));
    CGFloat brightOpticalScale = materialOpticalScale * materialSpecularScale;
    CGFloat darkEdgeScale = materialOpticalScale * materialEdgeDarkScale;

    // V2.2 contract: Glass Highlight maps only to perimeter specular intensity.
    // Geometry no longer attenuates compact CTA surfaces; Role scales preserve
    // Main/Outer > Inset hierarchy without changing physical rail thickness.
    CGFloat specularAlpha = MIN(0.30,
        0.30 * opticalResponse * brightOpticalScale);
    CGFloat specularBoostAlpha = MIN(0.60,
        0.60 * opticalResponse * brightOpticalScale);
    CGFloat specularDarkAlpha = MIN(0.12,
        0.12 * opticalResponse * darkEdgeScale);

    self.specularGradientLayer.colors = @[
        (id)[UIColor colorWithWhite:1.0 alpha:specularAlpha].CGColor,
        (id)[UIColor colorWithWhite:1.0 alpha:specularAlpha * 0.62].CGColor,
        (id)[UIColor colorWithWhite:1.0 alpha:0.0].CGColor,
        (id)[UIColor colorWithWhite:1.0 alpha:specularAlpha * 0.30].CGColor,
        (id)[UIColor colorWithWhite:1.0 alpha:specularAlpha * 0.82].CGColor
    ];

    self.specularBoostGradientLayer.colors = @[
        (id)[UIColor colorWithWhite:1.0 alpha:specularBoostAlpha].CGColor,
        (id)[UIColor colorWithWhite:1.0 alpha:specularBoostAlpha * 0.22].CGColor,
        (id)[UIColor colorWithWhite:1.0 alpha:0.0].CGColor,
        (id)[UIColor colorWithWhite:1.0 alpha:specularBoostAlpha * 0.14].CGColor,
        (id)[UIColor colorWithWhite:1.0 alpha:specularBoostAlpha * 0.78].CGColor
    ];

    // Back-facing edges stay almost transparent. The two small dark lobes
    // reinforce material separation, while every corner fades fully to zero.
    self.specularDarkGradientLayer.colors = @[
        (id)[UIColor colorWithWhite:0.0 alpha:0.0].CGColor,
        (id)[UIColor colorWithWhite:0.0 alpha:specularDarkAlpha * 0.12].CGColor,
        (id)[UIColor colorWithWhite:0.0 alpha:0.0].CGColor,
        (id)[UIColor colorWithWhite:0.0 alpha:specularDarkAlpha * 0.08].CGColor,
        (id)[UIColor colorWithWhite:0.0 alpha:0.0].CGColor
    ];

    // Apple-style hierarchy: a broader low-energy reflection region plus a
    // narrower bright filament. The dark rail stays subordinate and never
    // closes the perimeter into a black outline.
    self.specularMaskLayer.lineWidth = 1.30;
    self.specularBoostMaskLayer.lineWidth = 0.70;
    self.specularDarkMaskLayer.lineWidth = 0.32;

    // Keep one neutral structural hairline so Glass still has a material boundary
    // at Highlight = 0. It depends on body/appearance only, never on Highlight.
    CGFloat structuralBorderAlpha = darkGlassAppearance ?
        (0.024 + (0.014 * bodyAuthority)) :
        (0.015 + (0.011 * bodyAuthority));
    self.layer.borderWidth = 0.25;
    self.layer.borderColor = [UIColor colorWithWhite:1.0
                                             alpha:MIN(0.035, structuralBorderAlpha)].CGColor;

}

- (void)layoutSubviews
{
    [super layoutSubviews];

    self.layer.cornerRadius = self.preferredCornerRadius;
    self.neutralTintView.frame = self.bounds;
    self.fallbackBlurView.frame = self.bounds;

    CGFloat shortDimension = MIN(CGRectGetWidth(self.bounds), CGRectGetHeight(self.bounds));
    if (shortDimension > 1.0 && fabs(shortDimension - self.lastRenderedShortDimension) > 0.5) {
        self.lastRenderedShortDimension = shortDimension;
        [self reloadMaterial];
    }

    CGFloat rimInset = self.suppressBackdrop ? 0.28 : 0.34;
    CGRect rimRect = CGRectInset(self.bounds, rimInset, rimInset);
    CGFloat rimRadius = MAX(0.0, self.preferredCornerRadius - rimInset);
    UIBezierPath *rimPath = [UIBezierPath bezierPathWithRoundedRect:rimRect
                                                      cornerRadius:rimRadius];

    self.specularGradientLayer.frame = self.bounds;
    self.specularMaskLayer.frame = self.bounds;
    self.specularMaskLayer.path = rimPath.CGPath;

    self.specularBoostGradientLayer.frame = self.bounds;
    self.specularBoostMaskLayer.frame = self.bounds;
    self.specularBoostMaskLayer.path = rimPath.CGPath;

    self.specularDarkGradientLayer.frame = self.bounds;
    self.specularDarkMaskLayer.frame = self.bounds;
    self.specularDarkMaskLayer.path = rimPath.CGPath;
}

- (void)didMoveToWindow
{
    [super didMoveToWindow];
    // Controllers explicitly reload their mounted Glass surfaces on appearance
    // and theme changes. Avoid a second asynchronous filter rebuild for every
    // panel during cold launch; that burst was unnecessary on compact iPhones.
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection
{
    [super traitCollectionDidChange:previousTraitCollection];
    if (previousTraitCollection.userInterfaceStyle != self.traitCollection.userInterfaceStyle)
        [self reloadMaterial];
}

@end

// Main Glass is one material across home, Theme Settings, the restart shell,
// and the compact jailbreak status bar. Geometry may differ, but body, backdrop,
// and optical response must not drift into separate material families.
@interface DOCustomGlassSegmentedControl : UISegmentedControl
@property(nonatomic, strong) CALayer *glassSelectionLayer;
@end

@implementation DOCustomGlassSegmentedControl

- (instancetype)initWithItems:(NSArray *)items
{
    self = [super initWithItems:items];
    if (self) {
        _glassSelectionLayer = [CALayer layer];
        _glassSelectionLayer.backgroundColor =
            [UIColor colorWithWhite:1.0 alpha:0.11].CGColor;
        _glassSelectionLayer.cornerRadius = 19.0;
        _glassSelectionLayer.cornerCurve = kCACornerCurveContinuous;
        [self.layer insertSublayer:_glassSelectionLayer atIndex:0];
    }
    return self;
}

- (void)setSelectedSegmentIndex:(NSInteger)selectedSegmentIndex
{
    [super setSelectedSegmentIndex:selectedSegmentIndex];
    [self setNeedsLayout];
}

- (void)layoutSubviews
{
    [super layoutSubviews];

    NSInteger segmentCount = MAX(1, self.numberOfSegments);
    NSInteger selectedIndex = self.selectedSegmentIndex;
    BOOL hasSelection = selectedIndex != UISegmentedControlNoSegment &&
        selectedIndex >= 0 && selectedIndex < segmentCount;
    if (!hasSelection)
        selectedIndex = 0;

    CGFloat totalWidth = CGRectGetWidth(self.bounds);
    CGFloat segmentWidth = totalWidth / (CGFloat)segmentCount;
    CGRect selectionFrame = self.bounds;
    selectionFrame.origin.x = segmentWidth * selectedIndex;
    selectionFrame.size.width = (selectedIndex == segmentCount - 1)
        ? MAX(0.0, totalWidth - selectionFrame.origin.x)
        : segmentWidth;

    CACornerMask maskedCorners = 0;
    if (segmentCount == 1) {
        maskedCorners = kCALayerMinXMinYCorner | kCALayerMinXMaxYCorner |
            kCALayerMaxXMinYCorner | kCALayerMaxXMaxYCorner;
    }
    else if (selectedIndex == 0) {
        maskedCorners = kCALayerMinXMinYCorner | kCALayerMinXMaxYCorner;
    }
    else if (selectedIndex == segmentCount - 1) {
        maskedCorners = kCALayerMaxXMinYCorner | kCALayerMaxXMaxYCorner;
    }

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.glassSelectionLayer.hidden = !hasSelection;
    self.glassSelectionLayer.frame = selectionFrame;
    self.glassSelectionLayer.cornerRadius = 19.0;
    self.glassSelectionLayer.cornerCurve = kCACornerCurveContinuous;
    self.glassSelectionLayer.maskedCorners = maskedCorners;
    [CATransaction commit];
}

@end

static UIButton *DOCustomGlassBackButton(UIViewController *controller)
{
    UIButtonConfiguration *configuration = [UIButtonConfiguration plainButtonConfiguration];
    configuration.image = [UIImage systemImageNamed:@"chevron.left"];
    configuration.baseForegroundColor = UIColor.whiteColor;
    configuration.contentInsets = NSDirectionalEdgeInsetsMake(8.0, 10.0, 8.0, 10.0);

    __weak UIViewController *weakController = controller;
    UIButton *button = [UIButton buttonWithConfiguration:configuration
                                           primaryAction:[UIAction actionWithHandler:^(__kindof UIAction * _Nonnull action) {
        [weakController.navigationController popViewControllerAnimated:YES];
    }]];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.accessibilityLabel = @"返回";
    return button;
}

@interface DOCustomGlassThemeSettingsViewController () <PHPickerViewControllerDelegate>

@property UIImageView *customGlassBackgroundImageView;
@property(nonatomic, assign) BOOL supporterAuthorizationKnown;
@property(nonatomic, assign) BOOL supporterAuthorizationVerified;
@property DOCustomWallpaperBlurView *backgroundBlurView;
@property DOCustomLiquidGlassView *previewGlassView;

@property UISegmentedControl *glassAppearanceControl;
@property UISlider *backgroundBlurSlider;
@property UISlider *glassBlurSlider;
@property UISlider *glassTransparencySlider;
@property UISlider *glassTintSlider;
@property UIView *wallpaperPlaybackRateRow;
@property UISegmentedControl *wallpaperPlaybackRateControl;

@property UILabel *backgroundBlurValueLabel;
@property UILabel *glassBlurValueLabel;
@property UILabel *glassTransparencyValueLabel;
@property UILabel *glassTintValueLabel;

- (void)prepareForPresentation;
- (void)refreshThemePageFromPersistedState;

@end

@implementation DOCustomGlassThemeSettingsViewController

- (void)supporterLicenseDidChange:(NSNotification *)notification
{
    (void)notification;
    self.supporterAuthorizationKnown = NO;
}

- (BOOL)requireCustomGlassSupporterAuthorization
{
    if (!self.supporterAuthorizationKnown) {
        self.supporterAuthorizationVerified = DORHSupporterIsVerified();
        self.supporterAuthorizationKnown = YES;
    }

    if (self.supporterAuthorizationVerified)
        return YES;

    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:DOLocalizedString(@"Supporter_Required_Title")
                         message:DOLocalizedString(@"Supporter_Required_Message")
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:DOLocalizedString(@"Supporter_OK")
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:DOLocalizedString(@"Supporter_Manage")
                                              style:UIAlertActionStyleDefault
                                            handler:^(__kindof UIAlertAction * _Nonnull action) {
        [self.navigationController pushViewController:[[DOSettingsController alloc] init] animated:YES];
    }]];
    if (!self.presentedViewController)
        [self presentViewController:alert animated:YES completion:nil];
    return NO;
}

- (DOCustomLiquidGlassView *)themeGlassViewWithCornerRadius:(CGFloat)cornerRadius tintAlpha:(CGFloat)tintAlpha
{
    DOCustomLiquidGlassView *glassView =
        [[DOCustomLiquidGlassView alloc] initWithCornerRadius:cornerRadius baseTintAlpha:tintAlpha];
    glassView.translatesAutoresizingMaskIntoConstraints = NO;
    return glassView;
}

- (void)refreshLiquidGlassInView:(UIView *)view
{
    if ([view isKindOfClass:[DOCustomLiquidGlassView class]])
        [(DOCustomLiquidGlassView *)view reloadMaterial];

    for (UIView *subview in view.subviews)
        [self refreshLiquidGlassInView:subview];
}

- (UILabel *)themeSectionLabelWithText:(NSString *)text
{
    UILabel *label = [[UILabel alloc] init];
    label.text = text;
    label.textColor = [UIColor colorWithWhite:1.0 alpha:0.72];
    label.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightSemibold];
    return label;
}

- (DOCustomLiquidGlassView *)themeRowWithTitle:(NSString *)title
                                 subtitle:(NSString *)subtitle
                                imageName:(NSString *)imageName
                                   action:(UIAction *)action
{
    BOOL isPad = [[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad;
    DOCustomLiquidGlassView *row = [self themeGlassViewWithCornerRadius:22.0 tintAlpha:0.05];
    // Exact Main Glass profile: Theme Settings rows must render the same
    // material as the home cards rather than a nearby approximation.
    DOCustomGlassApplyMainMaterialProfile(row);
    [row reloadMaterial];

    UIImageSymbolConfiguration *symbolConfiguration =
        [UIImageSymbolConfiguration configurationWithPointSize:(isPad ? 21.0 : 19.0)
                                                        weight:UIImageSymbolWeightMedium
                                                         scale:UIImageSymbolScaleMedium];
    UIImageView *iconView = [[UIImageView alloc] initWithImage:
        [UIImage systemImageNamed:imageName withConfiguration:symbolConfiguration]];
    iconView.translatesAutoresizingMaskIntoConstraints = NO;
    iconView.tintColor = UIColor.whiteColor;
    iconView.contentMode = UIViewContentModeScaleAspectFit;

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = title;
    titleLabel.textColor = UIColor.whiteColor;
    titleLabel.font = [UIFont systemFontOfSize:(isPad ? 17.0 : 16.0) weight:UIFontWeightSemibold];

    UILabel *subtitleLabel = [[UILabel alloc] init];
    subtitleLabel.text = subtitle;
    subtitleLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.58];
    subtitleLabel.font = [UIFont systemFontOfSize:(isPad ? 13.0 : 12.0) weight:UIFontWeightRegular];
    subtitleLabel.numberOfLines = 1;
    subtitleLabel.adjustsFontSizeToFitWidth = YES;
    subtitleLabel.minimumScaleFactor = 0.88;

    UIStackView *textStack = [[UIStackView alloc] initWithArrangedSubviews:@[titleLabel, subtitleLabel]];
    textStack.axis = UILayoutConstraintAxisVertical;
    textStack.alignment = UIStackViewAlignmentFill;
    textStack.spacing = 3.0;
    textStack.translatesAutoresizingMaskIntoConstraints = NO;

    UIImageSymbolConfiguration *chevronConfiguration =
        [UIImageSymbolConfiguration configurationWithPointSize:13.0
                                                        weight:UIImageSymbolWeightSemibold
                                                         scale:UIImageSymbolScaleSmall];
    UIImageView *chevronView = [[UIImageView alloc] initWithImage:
        [UIImage systemImageNamed:@"chevron.right" withConfiguration:chevronConfiguration]];
    chevronView.translatesAutoresizingMaskIntoConstraints = NO;
    chevronView.tintColor = [UIColor colorWithWhite:1.0 alpha:0.42];
    chevronView.contentMode = UIViewContentModeScaleAspectFit;

    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.accessibilityLabel = title;
    [button addAction:action forControlEvents:UIControlEventTouchUpInside];

    [row.contentView addSubview:iconView];
    [row.contentView addSubview:textStack];
    [row.contentView addSubview:chevronView];
    [row.contentView addSubview:button];

    [NSLayoutConstraint activateConstraints:@[
        [row.heightAnchor constraintEqualToConstant:(isPad ? 76.0 : 70.0)],

        [iconView.leadingAnchor constraintEqualToAnchor:row.contentView.leadingAnchor constant:18.0],
        [iconView.centerYAnchor constraintEqualToAnchor:row.contentView.centerYAnchor],
        [iconView.widthAnchor constraintEqualToConstant:(isPad ? 28.0 : 26.0)],
        [iconView.heightAnchor constraintEqualToConstant:(isPad ? 28.0 : 26.0)],

        [textStack.leadingAnchor constraintEqualToAnchor:iconView.trailingAnchor constant:14.0],
        [textStack.centerYAnchor constraintEqualToAnchor:row.contentView.centerYAnchor],
        [textStack.trailingAnchor constraintLessThanOrEqualToAnchor:chevronView.leadingAnchor constant:-12.0],

        [chevronView.trailingAnchor constraintEqualToAnchor:row.contentView.trailingAnchor constant:-18.0],
        [chevronView.centerYAnchor constraintEqualToAnchor:row.contentView.centerYAnchor],
        [chevronView.widthAnchor constraintEqualToConstant:12.0],
        [chevronView.heightAnchor constraintEqualToConstant:18.0],

        [button.leadingAnchor constraintEqualToAnchor:row.contentView.leadingAnchor],
        [button.trailingAnchor constraintEqualToAnchor:row.contentView.trailingAnchor],
        [button.topAnchor constraintEqualToAnchor:row.contentView.topAnchor],
        [button.bottomAnchor constraintEqualToAnchor:row.contentView.bottomAnchor]
    ]];

    return row;
}

- (UILabel *)appearanceValueLabel
{
    UILabel *label = [[UILabel alloc] init];
    label.textColor = [UIColor colorWithWhite:1.0 alpha:0.68];
    label.font = [UIFont monospacedDigitSystemFontOfSize:13.0 weight:UIFontWeightMedium];
    label.textAlignment = NSTextAlignmentRight;
    [label.widthAnchor constraintEqualToConstant:48.0].active = YES;
    return label;
}

- (UISlider *)appearanceSlider
{
    UISlider *slider = [[UISlider alloc] init];
    slider.minimumTrackTintColor = [UIColor colorWithWhite:1.0 alpha:0.88];
    slider.maximumTrackTintColor = [UIColor colorWithWhite:1.0 alpha:0.24];
    [slider addTarget:self action:@selector(appearanceSliderChanged:) forControlEvents:UIControlEventValueChanged];
    return slider;
}

- (UIView *)appearanceControlRowWithTitle:(NSString *)title
                                subtitle:(NSString *)subtitle
                                  slider:(UISlider *)slider
                              valueLabel:(UILabel *)valueLabel
{
    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = title;
    titleLabel.textColor = UIColor.whiteColor;
    titleLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold];

    UILabel *subtitleLabel = [[UILabel alloc] init];
    subtitleLabel.text = subtitle;
    subtitleLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.52];
    subtitleLabel.font = [UIFont systemFontOfSize:11.5 weight:UIFontWeightRegular];

    UIStackView *titleStack = [[UIStackView alloc] initWithArrangedSubviews:@[titleLabel, subtitleLabel]];
    titleStack.axis = UILayoutConstraintAxisVertical;
    titleStack.spacing = 2.0;

    UIStackView *headerRow = [[UIStackView alloc] initWithArrangedSubviews:@[titleStack, valueLabel]];
    headerRow.axis = UILayoutConstraintAxisHorizontal;
    headerRow.alignment = UIStackViewAlignmentCenter;
    headerRow.spacing = 10.0;

    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[headerRow, slider]];
    row.axis = UILayoutConstraintAxisVertical;
    row.spacing = 7.0;
    return row;
}

- (UIView *)appearanceSegmentedRowWithTitle:(NSString *)title
                                   subtitle:(NSString *)subtitle
                                    control:(UISegmentedControl *)control
{
    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = title;
    titleLabel.textColor = UIColor.whiteColor;
    titleLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold];

    UILabel *subtitleLabel = [[UILabel alloc] init];
    subtitleLabel.text = subtitle;
    subtitleLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.52];
    subtitleLabel.font = [UIFont systemFontOfSize:11.5 weight:UIFontWeightRegular];

    UIStackView *titleStack = [[UIStackView alloc] initWithArrangedSubviews:@[titleLabel, subtitleLabel]];
    titleStack.axis = UILayoutConstraintAxisVertical;
    titleStack.spacing = 2.0;

    DOCustomLiquidGlassView *inset = [self themeGlassViewWithCornerRadius:21.0 tintAlpha:0.0];
    inset.materialScale = 0.70;
    inset.materialBodyScale = 0.24;
    inset.materialOpticalScale = 0.36;
    inset.materialBackdropScale = 0.0;
    inset.materialSpecularScale = 0.30;
    inset.materialEdgeDarkScale = 0.34;
    inset.suppressBackdrop = YES;
    [inset reloadMaterial];

    control.translatesAutoresizingMaskIntoConstraints = NO;
    [inset.contentView addSubview:control];
    [NSLayoutConstraint activateConstraints:@[
        [control.leadingAnchor constraintEqualToAnchor:inset.contentView.leadingAnchor constant:2.0],
        [control.trailingAnchor constraintEqualToAnchor:inset.contentView.trailingAnchor constant:-2.0],
        [control.topAnchor constraintEqualToAnchor:inset.contentView.topAnchor constant:2.0],
        [control.bottomAnchor constraintEqualToAnchor:inset.contentView.bottomAnchor constant:-2.0],
        [inset.heightAnchor constraintEqualToConstant:42.0]
    ]];

    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[titleStack, inset]];
    row.axis = UILayoutConstraintAxisVertical;
    row.spacing = 7.0;
    return row;
}

static NSInteger DOCustomGlassPlaybackRateSegmentIndex(CGFloat rate)
{
    static const CGFloat rates[] = {0.50, 0.65, 0.80, 1.00};
    NSInteger bestIndex = 0;
    CGFloat bestDistance = CGFLOAT_MAX;
    for (NSInteger index = 0; index < 4; index++) {
        CGFloat distance = fabs(rate - rates[index]);
        if (distance < bestDistance) {
            bestDistance = distance;
            bestIndex = index;
        }
    }
    return bestIndex;
}

static CGFloat DOCustomGlassPlaybackRateForSegmentIndex(NSInteger index)
{
    static const CGFloat rates[] = {0.50, 0.65, 0.80, 1.00};
    NSInteger clampedIndex = MIN(3, MAX(0, index));
    return rates[clampedIndex];
}

static UIImage *DOCustomGlassCreateVideoPosterImage(NSURL *videoURL)
{
    if (!videoURL.isFileURL)
        return nil;

    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:videoURL options:nil];
    AVAssetImageGenerator *generator = [[AVAssetImageGenerator alloc] initWithAsset:asset];
    generator.appliesPreferredTrackTransform = YES;
    generator.maximumSize = CGSizeMake(2048.0, 2048.0);

    NSError *error = nil;
    CMTime requestedTime = CMTimeMakeWithSeconds(0.10, 600);
    CGImageRef frame = [generator copyCGImageAtTime:requestedTime actualTime:NULL error:&error];
    if (!frame) {
        error = nil;
        frame = [generator copyCGImageAtTime:kCMTimeZero actualTime:NULL error:&error];
    }
    if (!frame) {
        NSLog(@"[CustomGlass][VideoWallpaper] poster generation failed: %@", error);
        return nil;
    }

    UIImage *poster = [UIImage imageWithCGImage:frame];
    CGImageRelease(frame);
    return poster;
}

static NSInteger DOCustomGlassLivePhotoVideoResourcePriority(PHAssetResourceType type)
{
    switch (type) {
        case PHAssetResourceTypeFullSizePairedVideo:
            return 3;
        case PHAssetResourceTypePairedVideo:
            return 2;
        case PHAssetResourceTypeAdjustmentBasePairedVideo:
            return 1;
        default:
            return 0;
    }
}

static NSInteger DOCustomGlassLivePhotoImageResourcePriority(PHAssetResourceType type)
{
    switch (type) {
        case PHAssetResourceTypeFullSizePhoto:
            return 3;
        case PHAssetResourceTypePhoto:
            return 2;
        case PHAssetResourceTypeAdjustmentBasePhoto:
            return 1;
        default:
            return 0;
    }
}

static NSError *DOCustomGlassLivePhotoImportError(NSInteger code, NSString *message)
{
    return [NSError errorWithDomain:@"DOCustomGlassLivePhotoImport"
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message ?: @"Live Photo import failed."}];
}

// PHPicker can vend a PHLivePhoto without granting broad Photo Library access.
// PHAssetResource then exposes that selected object's paired resources directly,
// so Live Photo stays inside the same privacy model as the existing picker.
static void DOCustomGlassExportLivePhoto(PHLivePhoto *livePhoto,
                                         void (^completion)(NSURL *videoURL,
                                                            UIImage *posterImage,
                                                            NSError *error))
{
    if (!livePhoto || !completion)
        return;

    NSArray<PHAssetResource *> *resources = [PHAssetResource assetResourcesForLivePhoto:livePhoto];
    PHAssetResource *videoResource = nil;
    PHAssetResource *imageResource = nil;
    NSInteger videoPriority = 0;
    NSInteger imagePriority = 0;

    for (PHAssetResource *resource in resources) {
        NSInteger candidateVideoPriority = DOCustomGlassLivePhotoVideoResourcePriority(resource.type);
        if (candidateVideoPriority > videoPriority) {
            videoPriority = candidateVideoPriority;
            videoResource = resource;
        }

        NSInteger candidateImagePriority = DOCustomGlassLivePhotoImageResourcePriority(resource.type);
        if (candidateImagePriority > imagePriority) {
            imagePriority = candidateImagePriority;
            imageResource = resource;
        }
    }

    if (!videoResource) {
        completion(nil, nil,
                   DOCustomGlassLivePhotoImportError(1, @"Live Photo has no paired video resource."));
        return;
    }

    NSURL *temporaryRoot = [NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES];
    NSURL *temporaryDirectory = [temporaryRoot
        URLByAppendingPathComponent:[NSString stringWithFormat:@"CustomGlass-LivePhoto-%@",
                                                               NSUUID.UUID.UUIDString]
                         isDirectory:YES];
    NSError *directoryError = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtURL:temporaryDirectory
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:&directoryError]) {
        completion(nil, nil, directoryError ?: DOCustomGlassLivePhotoImportError(2, @"Unable to create Live Photo staging directory."));
        return;
    }

    NSURL *videoURL = [temporaryDirectory URLByAppendingPathComponent:@"paired.mov" isDirectory:NO];
    NSString *imageExtension = imageResource.originalFilename.pathExtension.lowercaseString;
    if (imageExtension.length == 0)
        imageExtension = @"jpg";
    NSURL *imageURL = [temporaryDirectory
        URLByAppendingPathComponent:[NSString stringWithFormat:@"poster.%@", imageExtension]
                         isDirectory:NO];

    PHAssetResourceRequestOptions *options = [[PHAssetResourceRequestOptions alloc] init];
    options.networkAccessAllowed = YES;

    PHAssetResourceManager *manager = [PHAssetResourceManager defaultManager];
    dispatch_group_t group = dispatch_group_create();
    __block NSError *videoError = nil;
    __block NSError *imageError = nil;

    dispatch_group_enter(group);
    [manager writeDataForAssetResource:videoResource
                                toFile:videoURL
                               options:options
                     completionHandler:^(NSError *error) {
        videoError = error;
        dispatch_group_leave(group);
    }];

    if (imageResource) {
        dispatch_group_enter(group);
        [manager writeDataForAssetResource:imageResource
                                    toFile:imageURL
                                   options:options
                         completionHandler:^(NSError *error) {
            imageError = error;
            dispatch_group_leave(group);
        }];
    }

    dispatch_group_notify(group,
                          dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSFileManager *fileManager = [NSFileManager defaultManager];
        BOOL hasVideo = !videoError && [fileManager fileExistsAtPath:videoURL.path];
        if (!hasVideo) {
            NSError *error = videoError ?:
                DOCustomGlassLivePhotoImportError(3, @"Unable to export Live Photo paired video.");
            completion(nil, nil, error);
            [fileManager removeItemAtURL:temporaryDirectory error:nil];
            return;
        }

        UIImage *poster = nil;
        if (imageResource && !imageError && [fileManager fileExistsAtPath:imageURL.path])
            poster = [UIImage imageWithContentsOfFile:imageURL.path];
        if (!poster)
            poster = DOCustomGlassCreateVideoPosterImage(videoURL);

        if (!poster) {
            completion(nil, nil,
                       DOCustomGlassLivePhotoImportError(4, @"Unable to create Live Photo poster image."));
            [fileManager removeItemAtURL:temporaryDirectory error:nil];
            return;
        }

        // The callback must synchronously consume videoURL. MediaStore does so
        // by copying it into the persistent CustomGlass directory.
        completion(videoURL, poster, nil);
        [fileManager removeItemAtURL:temporaryDirectory error:nil];
    });
}

- (void)presentCustomGlassBackgroundPicker
{
    if (![self requireCustomGlassSupporterAuthorization])
        return;

    PHPickerConfiguration *configuration = [[PHPickerConfiguration alloc] init];
    configuration.filter = [PHPickerFilter anyFilterMatchingSubfilters:@[
        [PHPickerFilter imagesFilter],
        [PHPickerFilter livePhotosFilter],
        [PHPickerFilter videosFilter]
    ]];
    configuration.preferredAssetRepresentationMode = PHPickerConfigurationAssetRepresentationModeCurrent;
    configuration.selectionLimit = 1;

    PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:configuration];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results
{
    [picker dismissViewControllerAnimated:YES completion:nil];

    PHPickerResult *result = results.firstObject;
    if (!result || !DORHSupporterIsVerified())
        return;

    NSItemProvider *provider = result.itemProvider;
    __weak typeof(self) weakSelf = self;

    void (^finishWallpaperImport)(BOOL) = ^(BOOL saved) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!saved)
                return;

            [[UIApplication sharedApplication] ignoreSnapshotOnNextApplicationLaunch];

            // Always re-resolve MediaStore so image and video imports share the
            // exact same cold-launch and live-preview path.
            [weakSelf.navigationController customGlassRefreshSharedBackground];
            [[NSNotificationCenter defaultCenter]
                postNotificationName:DOCustomGlassThemeDidChangeNotification object:nil];
            [weakSelf syncAppearanceControlsFromDefaults];
            [weakSelf applyAppearancePreviewAndPersist:NO];
        });
    };

    void (^importStaticImage)(void) = ^{
        if (![provider canLoadObjectOfClass:UIImage.class])
            return;

        [provider loadObjectOfClass:UIImage.class
                  completionHandler:^(id<NSItemProviderReading> object, NSError *error) {
            if (error || ![object isKindOfClass:UIImage.class]) {
                NSLog(@"[CustomGlass][Wallpaper] image provider failed: %@", error);
                return;
            }

            if (!DORHSupporterIsVerified()) {
                finishWallpaperImport(NO);
                return;
            }

            BOOL saved = DOCustomGlassMediaStoreSaveWallpaper((UIImage *)object, NULL);
            finishWallpaperImport(saved);
        }];
    };

    // Detect Live Photo before public.movie. A Live Photo is imported as its
    // paired motion resource plus key photo, then handed to the exact same
    // persistent AVPlayer pipeline as an ordinary video wallpaper.
    if ([provider canLoadObjectOfClass:PHLivePhoto.class]) {
        [provider loadObjectOfClass:PHLivePhoto.class
                  completionHandler:^(id<NSItemProviderReading> object, NSError *error) {
            if (error || ![object isKindOfClass:PHLivePhoto.class]) {
                NSLog(@"[CustomGlass][LivePhoto] provider failed: %@", error);
                importStaticImage();
                return;
            }

            DOCustomGlassExportLivePhoto((PHLivePhoto *)object,
                                         ^(NSURL *videoURL, UIImage *poster, NSError *exportError) {
                if (exportError || !videoURL || !poster) {
                    NSLog(@"[CustomGlass][LivePhoto] export failed: %@", exportError);
                    importStaticImage();
                    return;
                }

                if (!DORHSupporterIsVerified()) {
                    finishWallpaperImport(NO);
                    return;
                }

                BOOL saved = DOCustomGlassMediaStoreSaveWallpaperVideo(videoURL, poster, NULL);
                if (!saved)
                    NSLog(@"[CustomGlass][LivePhoto] MediaStore commit failed");
                finishWallpaperImport(saved);
            });
        }];
        return;
    }

    if ([provider hasItemConformingToTypeIdentifier:@"public.movie"]) {
        [provider loadFileRepresentationForTypeIdentifier:@"public.movie"
                                         completionHandler:^(NSURL *fileURL, NSError *error) {
            if (error || !fileURL) {
                NSLog(@"[CustomGlass][VideoWallpaper] provider failed: %@", error);
                return;
            }

            // PHPicker's representation URL is temporary. Generate the poster
            // and copy the movie into MediaStore before this callback returns.
            if (!DORHSupporterIsVerified()) {
                finishWallpaperImport(NO);
                return;
            }

            UIImage *poster = DOCustomGlassCreateVideoPosterImage(fileURL);
            BOOL saved = poster ?
                DOCustomGlassMediaStoreSaveWallpaperVideo(fileURL, poster, NULL) : NO;
            finishWallpaperImport(saved);
        }];
        return;
    }

    importStaticImage();
}

- (void)showThemePlaceholderForTitle:(NSString *)title
{
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:title
                         message:@"基础页面已经接入；具体编辑功能会在下一阶段逐项加入。"
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:DOLocalizedString(@"Button_Close")
                                              style:UIAlertActionStyleDefault
                                            handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)prepareForPresentation
{
    // The navigation controller already owns the persistent first-frame
    // wallpaper. Prime only this controller's local Glass hierarchy before the
    // transition; do not re-decode or re-blur the shared image here.
    [self loadViewIfNeeded];
    [self syncAppearanceControlsFromDefaults];
    [self refreshLiquidGlassInView:self.view];
    [self.view setNeedsLayout];
    [self.view layoutIfNeeded];
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(supporterLicenseDidChange:)
                                                 name:DORHSupporterLicenseDidChangeNotification
                                               object:nil];

    self.title = @"主题设置";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.view.backgroundColor = UIColor.clearColor;

    // The navigation controller owns the only Custom Glass wallpaper layer.
    // This page stays transparent above that persistent source.

    [[NSUserDefaults standardUserDefaults] registerDefaults:@{
        DOCustomGlassAppearanceKey : DOCustomGlassAppearanceLight,
        DOCustomGlassBackgroundBlurKey : @0.10,
        DOCustomGlassBlurIntensityKey : @0.85,
        DOCustomGlassTransparencyKey : @0.70,
        DOCustomGlassTintAlphaKey : @0.05,
        DOCustomGlassUsernameKey : @"",
        DOCustomGlassMottoKey : @"",
        DOCustomGlassWallpaperPlaybackRateKey : @(DOCustomGlassWallpaperPlaybackRateDefault)
    }];

    BOOL isPad = [[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad;

    UIScrollView *scrollView = [[UIScrollView alloc] init];
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    scrollView.alwaysBounceVertical = YES;
    scrollView.showsVerticalScrollIndicator = NO;
    scrollView.backgroundColor = UIColor.clearColor;
    scrollView.opaque = NO;
    [self.view addSubview:scrollView];

    UIStackView *contentStack = [[UIStackView alloc] init];
    contentStack.axis = UILayoutConstraintAxisVertical;
    contentStack.alignment = UIStackViewAlignmentFill;
    contentStack.spacing = 9.0;
    contentStack.translatesAutoresizingMaskIntoConstraints = NO;
    [scrollView addSubview:contentStack];

    UIButton *backButton = DOCustomGlassBackButton(self);
    [self.view addSubview:backButton];

    UILabel *pageTitleLabel = [[UILabel alloc] init];
    pageTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    pageTitleLabel.text = @"主题设置";
    pageTitleLabel.textColor = UIColor.whiteColor;
    pageTitleLabel.font = [UIFont systemFontOfSize:(isPad ? 18.0 : 17.0) weight:UIFontWeightSemibold];
    pageTitleLabel.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:pageTitleLabel];

    [NSLayoutConstraint activateConstraints:@[
        [backButton.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:12.0],
        [backButton.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:4.0],
        [backButton.widthAnchor constraintEqualToConstant:44.0],
        [backButton.heightAnchor constraintEqualToConstant:40.0],

        [pageTitleLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [pageTitleLabel.centerYAnchor constraintEqualToAnchor:backButton.centerYAnchor],

        [scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [scrollView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:48.0],
        [scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [contentStack.topAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.topAnchor constant:(isPad ? 12.0 : 8.0)],
        [contentStack.bottomAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.bottomAnchor constant:-28.0],
        [contentStack.centerXAnchor constraintEqualToAnchor:scrollView.frameLayoutGuide.centerXAnchor],
        [contentStack.widthAnchor constraintLessThanOrEqualToConstant:620.0]
    ]];

    NSLayoutConstraint *responsiveWidth =
        [contentStack.widthAnchor constraintEqualToAnchor:scrollView.frameLayoutGuide.widthAnchor constant:(isPad ? -56.0 : -40.0)];
    responsiveWidth.priority = UILayoutPriorityDefaultHigh;
    responsiveWidth.active = YES;

    __weak typeof(self) weakSelf = self;

    UILabel *wallpaperLabel = [self themeSectionLabelWithText:@"背景"];
    [contentStack addArrangedSubview:wallpaperLabel];

    [contentStack addArrangedSubview:[self themeRowWithTitle:@"背景"
                                                    subtitle:@"选择首页背景图片或视频"
                                                   imageName:@"photo"
                                                      action:[UIAction actionWithHandler:^(__kindof UIAction * _Nonnull action) {
        [weakSelf presentCustomGlassBackgroundPicker];
    }]]];

    UIView *appearanceSpacer = [[UIView alloc] init];
    [contentStack addArrangedSubview:appearanceSpacer];
    [appearanceSpacer.heightAnchor constraintEqualToConstant:7.0].active = YES;

    UILabel *appearanceLabel = [self themeSectionLabelWithText:@"外观效果"];
    [contentStack addArrangedSubview:appearanceLabel];

    // The control panel is the actual Main Glass renderer used by the home
    // cards. Slider changes therefore preview the same body, backdrop and
    // directional optics instead of a deliberately quieter panel variant.
    self.previewGlassView = [self themeGlassViewWithCornerRadius:26.0 tintAlpha:0.05];
    DOCustomGlassApplyMainMaterialProfile(self.previewGlassView);
    [self.previewGlassView reloadMaterial];
    [contentStack addArrangedSubview:self.previewGlassView];
    // This panel previously collapsed to zero height because the Glass content
    // surface was frame-driven. Keep a safety floor even though contentView is
    // now Auto Layout driven, so all four sliders remain visible on every iOS 16
    // device and Dynamic Type configuration.
    [self.previewGlassView.heightAnchor constraintGreaterThanOrEqualToConstant:(isPad ? 488.0 : 472.0)].active = YES;

    UIStackView *controlsStack = [[UIStackView alloc] init];
    controlsStack.translatesAutoresizingMaskIntoConstraints = NO;
    controlsStack.axis = UILayoutConstraintAxisVertical;
    controlsStack.spacing = isPad ? 16.0 : 14.0;
    [self.previewGlassView.contentView addSubview:controlsStack];

    [NSLayoutConstraint activateConstraints:@[
        [controlsStack.leadingAnchor constraintEqualToAnchor:self.previewGlassView.contentView.leadingAnchor constant:20.0],
        [controlsStack.trailingAnchor constraintEqualToAnchor:self.previewGlassView.contentView.trailingAnchor constant:-20.0],
        [controlsStack.topAnchor constraintEqualToAnchor:self.previewGlassView.contentView.topAnchor constant:18.0],
        [controlsStack.bottomAnchor constraintEqualToAnchor:self.previewGlassView.contentView.bottomAnchor constant:-16.0]
    ]];

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

    UILabel *liquidGlassLabel = [[UILabel alloc] init];
    liquidGlassLabel.text = @"Liquid Glass";
    liquidGlassLabel.textColor = UIColor.whiteColor;
    liquidGlassLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold];
    [controlsStack addArrangedSubview:liquidGlassLabel];

    self.glassAppearanceControl = [[DOCustomGlassSegmentedControl alloc] initWithItems:@[@"Light Glass", @"Dark Glass"]];
    self.glassAppearanceControl.translatesAutoresizingMaskIntoConstraints = NO;
    // The segmented control is content inside an Inset Glass surface. Keep the
    // native control itself optically quiet so it does not read as a second,
    // unrelated grey platter pasted over the parent Glass panel.
    self.glassAppearanceControl.selectedSegmentTintColor = UIColor.clearColor;
    self.glassAppearanceControl.backgroundColor = UIColor.clearColor;

    UIImage *normalSegmentImage = DOCustomGlassSolidImage(UIColor.clearColor);
    UIImage *selectedSegmentImage = DOCustomGlassSolidImage(UIColor.clearColor);
    UIImage *clearSegmentImage = DOCustomGlassSolidImage(UIColor.clearColor);
    [self.glassAppearanceControl setBackgroundImage:normalSegmentImage
                                          forState:UIControlStateNormal
                                        barMetrics:UIBarMetricsDefault];
    [self.glassAppearanceControl setBackgroundImage:selectedSegmentImage
                                          forState:UIControlStateSelected
                                        barMetrics:UIBarMetricsDefault];
    [self.glassAppearanceControl setDividerImage:clearSegmentImage
                             forLeftSegmentState:UIControlStateNormal
                               rightSegmentState:UIControlStateNormal
                                      barMetrics:UIBarMetricsDefault];
    [self.glassAppearanceControl setDividerImage:clearSegmentImage
                             forLeftSegmentState:UIControlStateSelected
                               rightSegmentState:UIControlStateNormal
                                      barMetrics:UIBarMetricsDefault];
    [self.glassAppearanceControl setDividerImage:clearSegmentImage
                             forLeftSegmentState:UIControlStateNormal
                               rightSegmentState:UIControlStateSelected
                                      barMetrics:UIBarMetricsDefault];

    self.glassAppearanceControl.layer.cornerRadius = 19.0;
    self.glassAppearanceControl.layer.cornerCurve = kCACornerCurveContinuous;
    self.glassAppearanceControl.layer.masksToBounds = YES;
    self.glassAppearanceControl.accessibilityLabel = @"Liquid Glass";
    [self.glassAppearanceControl setTitleTextAttributes:@{
        NSForegroundColorAttributeName : [UIColor colorWithWhite:1.0 alpha:0.68],
        NSFontAttributeName : [UIFont systemFontOfSize:14.0 weight:UIFontWeightMedium]
    } forState:UIControlStateNormal];
    [self.glassAppearanceControl setTitleTextAttributes:@{
        NSForegroundColorAttributeName : UIColor.whiteColor,
        NSFontAttributeName : [UIFont systemFontOfSize:14.0 weight:UIFontWeightSemibold]
    } forState:UIControlStateSelected];

    NSString *appearance = [defaults stringForKey:DOCustomGlassAppearanceKey];
    self.glassAppearanceControl.selectedSegmentIndex =
        [appearance isEqualToString:DOCustomGlassAppearanceDark] ? 1 : 0;
    [self.glassAppearanceControl addTarget:self
                                    action:@selector(glassAppearanceChanged:)
                          forControlEvents:UIControlEventValueChanged];

    // Inset Glass role: a shallow local control surface inside the parent panel.
    // It deliberately has no backdrop pass; the parent previewGlassView owns
    // diffusion/transmission. Only a light body + quiet contour establish depth.
    DOCustomLiquidGlassView *appearanceInset =
        [self themeGlassViewWithCornerRadius:21.0 tintAlpha:0.0];
    appearanceInset.materialScale = 0.70;
    appearanceInset.materialBodyScale = 0.24;
    appearanceInset.materialOpticalScale = 0.36;
    appearanceInset.materialBackdropScale = 0.0;
    appearanceInset.materialSpecularScale = 0.30;
    appearanceInset.materialEdgeDarkScale = 0.34;
    appearanceInset.suppressBackdrop = YES;
    [appearanceInset reloadMaterial];
    [appearanceInset.contentView addSubview:self.glassAppearanceControl];
    [NSLayoutConstraint activateConstraints:@[
        [self.glassAppearanceControl.leadingAnchor constraintEqualToAnchor:appearanceInset.contentView.leadingAnchor constant:2.0],
        [self.glassAppearanceControl.trailingAnchor constraintEqualToAnchor:appearanceInset.contentView.trailingAnchor constant:-2.0],
        [self.glassAppearanceControl.topAnchor constraintEqualToAnchor:appearanceInset.contentView.topAnchor constant:2.0],
        [self.glassAppearanceControl.bottomAnchor constraintEqualToAnchor:appearanceInset.contentView.bottomAnchor constant:-2.0]
    ]];
    [controlsStack addArrangedSubview:appearanceInset];
    [appearanceInset.heightAnchor constraintEqualToConstant:44.0].active = YES;

    self.backgroundBlurSlider = [self appearanceSlider];
    self.backgroundBlurSlider.minimumValue = 0.0;
    self.backgroundBlurSlider.maximumValue = 1.0;
    self.backgroundBlurSlider.value = [defaults floatForKey:DOCustomGlassBackgroundBlurKey];
    self.backgroundBlurValueLabel = [self appearanceValueLabel];
    [controlsStack addArrangedSubview:[self appearanceControlRowWithTitle:@"壁纸模糊"
                                                                 subtitle:@"仅静态壁纸生效"
                                                                   slider:self.backgroundBlurSlider
                                                               valueLabel:self.backgroundBlurValueLabel]];

    self.wallpaperPlaybackRateControl = [[DOCustomGlassSegmentedControl alloc]
        initWithItems:@[@"0.50×", @"0.65×", @"0.80×", @"1.00×"]];
    self.wallpaperPlaybackRateControl.selectedSegmentTintColor = UIColor.clearColor;
    self.wallpaperPlaybackRateControl.backgroundColor = UIColor.clearColor;
    self.wallpaperPlaybackRateControl.apportionsSegmentWidthsByContent = NO;
    self.wallpaperPlaybackRateControl.accessibilityLabel = @"动态壁纸速度";

    UIImage *speedNormalImage = DOCustomGlassSolidImage(UIColor.clearColor);
    UIImage *speedSelectedImage = DOCustomGlassSolidImage(UIColor.clearColor);
    UIImage *speedDividerImage = DOCustomGlassSolidImage(UIColor.clearColor);
    [self.wallpaperPlaybackRateControl setBackgroundImage:speedNormalImage
                                                 forState:UIControlStateNormal
                                               barMetrics:UIBarMetricsDefault];
    [self.wallpaperPlaybackRateControl setBackgroundImage:speedSelectedImage
                                                 forState:UIControlStateSelected
                                               barMetrics:UIBarMetricsDefault];
    [self.wallpaperPlaybackRateControl setDividerImage:speedDividerImage
                                   forLeftSegmentState:UIControlStateNormal
                                     rightSegmentState:UIControlStateNormal
                                            barMetrics:UIBarMetricsDefault];
    [self.wallpaperPlaybackRateControl setDividerImage:speedDividerImage
                                   forLeftSegmentState:UIControlStateSelected
                                     rightSegmentState:UIControlStateNormal
                                            barMetrics:UIBarMetricsDefault];
    [self.wallpaperPlaybackRateControl setDividerImage:speedDividerImage
                                   forLeftSegmentState:UIControlStateNormal
                                     rightSegmentState:UIControlStateSelected
                                            barMetrics:UIBarMetricsDefault];
    [self.wallpaperPlaybackRateControl setTitleTextAttributes:@{
        NSForegroundColorAttributeName : [UIColor colorWithWhite:1.0 alpha:0.68],
        NSFontAttributeName : [UIFont systemFontOfSize:12.0 weight:UIFontWeightMedium]
    } forState:UIControlStateNormal];
    [self.wallpaperPlaybackRateControl setTitleTextAttributes:@{
        NSForegroundColorAttributeName : UIColor.whiteColor,
        NSFontAttributeName : [UIFont systemFontOfSize:12.0 weight:UIFontWeightSemibold]
    } forState:UIControlStateSelected];
    [self.wallpaperPlaybackRateControl addTarget:self
                                          action:@selector(wallpaperPlaybackRateChanged:)
                                forControlEvents:UIControlEventValueChanged];

    CGFloat persistedPlaybackRate = [defaults objectForKey:DOCustomGlassWallpaperPlaybackRateKey] ?
        [defaults floatForKey:DOCustomGlassWallpaperPlaybackRateKey] :
        DOCustomGlassWallpaperPlaybackRateDefault;
    self.wallpaperPlaybackRateControl.selectedSegmentIndex =
        DOCustomGlassPlaybackRateSegmentIndex(persistedPlaybackRate);
    self.wallpaperPlaybackRateRow =
        [self appearanceSegmentedRowWithTitle:@"动态壁纸速度"
                                     subtitle:@"视频 / Live Photo 的播放速度"
                                      control:self.wallpaperPlaybackRateControl];
    self.wallpaperPlaybackRateRow.hidden = ![self.navigationController customGlassIsUsingVideoWallpaper];
    [controlsStack addArrangedSubview:self.wallpaperPlaybackRateRow];

    self.glassBlurSlider = [self appearanceSlider];
    self.glassBlurSlider.minimumValue = 0.0;
    self.glassBlurSlider.maximumValue = 1.0;
    self.glassBlurSlider.value = [defaults floatForKey:DOCustomGlassBlurIntensityKey];
    self.glassBlurValueLabel = [self appearanceValueLabel];
    [controlsStack addArrangedSubview:[self appearanceControlRowWithTitle:@"Glass 模糊"
                                                                 subtitle:@"玻璃自身的模糊强度"
                                                                   slider:self.glassBlurSlider
                                                               valueLabel:self.glassBlurValueLabel]];

    self.glassTransparencySlider = [self appearanceSlider];
    self.glassTransparencySlider.minimumValue = 0.0;
    self.glassTransparencySlider.maximumValue = 1.0;
    self.glassTransparencySlider.value = [defaults floatForKey:DOCustomGlassTransparencyKey];
    self.glassTransparencyValueLabel = [self appearanceValueLabel];
    [controlsStack addArrangedSubview:[self appearanceControlRowWithTitle:@"Glass 透明度"
                                                                 subtitle:@"越高越通透"
                                                                   slider:self.glassTransparencySlider
                                                               valueLabel:self.glassTransparencyValueLabel]];

    self.glassTintSlider = [self appearanceSlider];
    self.glassTintSlider.minimumValue = 0.0;
    self.glassTintSlider.maximumValue = 0.16;
    self.glassTintSlider.value = [defaults floatForKey:DOCustomGlassTintAlphaKey];
    self.glassTintValueLabel = [self appearanceValueLabel];
    [controlsStack addArrangedSubview:[self appearanceControlRowWithTitle:@"Glass 高光"
                                                                 subtitle:@"玻璃表面的白色高光强度"
                                                                   slider:self.glassTintSlider
                                                               valueLabel:self.glassTintValueLabel]];

    UIButtonConfiguration *resetConfiguration = [UIButtonConfiguration plainButtonConfiguration];
    resetConfiguration.title = @"恢复推荐值";
    resetConfiguration.image = [UIImage systemImageNamed:@"arrow.counterclockwise"];
    resetConfiguration.imagePadding = 7.0;
    resetConfiguration.baseForegroundColor = [UIColor colorWithWhite:1.0 alpha:0.86];

    UIButton *resetButton = [UIButton buttonWithConfiguration:resetConfiguration
                                                primaryAction:[UIAction actionWithHandler:^(__kindof UIAction * _Nonnull action) {
        [weakSelf restoreRecommendedAppearanceValues];
    }]];
    [controlsStack addArrangedSubview:resetButton];
    [resetButton.heightAnchor constraintEqualToConstant:38.0].active = YES;

    UIScreenEdgePanGestureRecognizer *edgeBackGesture =
        [[UIScreenEdgePanGestureRecognizer alloc] initWithTarget:self action:@selector(handleEdgeBackGesture:)];
    edgeBackGesture.edges = UIRectEdgeLeft;
    [self.view addGestureRecognizer:edgeBackGesture];

    [self applyAppearancePreviewAndPersist:NO];
}

- (void)syncAppearanceControlsFromDefaults
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

    if (self.glassAppearanceControl) {
        NSString *appearance = [defaults stringForKey:DOCustomGlassAppearanceKey];
        self.glassAppearanceControl.selectedSegmentIndex =
            [appearance isEqualToString:DOCustomGlassAppearanceDark] ? 1 : 0;
    }
    if (self.backgroundBlurSlider) {
        self.backgroundBlurSlider.value = [defaults floatForKey:DOCustomGlassBackgroundBlurKey];
        BOOL usingVideoWallpaper = [self.navigationController customGlassIsUsingVideoWallpaper];
        self.backgroundBlurSlider.enabled = !usingVideoWallpaper;
        self.backgroundBlurSlider.alpha = usingVideoWallpaper ? 0.40 : 1.0;
    }
    if (self.glassBlurSlider)
        self.glassBlurSlider.value = [defaults floatForKey:DOCustomGlassBlurIntensityKey];
    if (self.glassTransparencySlider)
        self.glassTransparencySlider.value = [defaults floatForKey:DOCustomGlassTransparencyKey];
    if (self.glassTintSlider)
        self.glassTintSlider.value = [defaults floatForKey:DOCustomGlassTintAlphaKey];
    if (self.wallpaperPlaybackRateControl) {
        CGFloat playbackRate = [defaults objectForKey:DOCustomGlassWallpaperPlaybackRateKey] ?
            [defaults floatForKey:DOCustomGlassWallpaperPlaybackRateKey] :
            DOCustomGlassWallpaperPlaybackRateDefault;
        self.wallpaperPlaybackRateControl.selectedSegmentIndex =
            DOCustomGlassPlaybackRateSegmentIndex(playbackRate);
    }
    if (self.wallpaperPlaybackRateRow)
        self.wallpaperPlaybackRateRow.hidden = ![self.navigationController customGlassIsUsingVideoWallpaper];
}

- (void)refreshThemePageFromPersistedState
{
    [self syncAppearanceControlsFromDefaults];
    [self applyAppearancePreviewAndPersist:NO];

    // Force a full layout/display pass after the background image and all
    // CABackdropLayer filters are rebuilt. This is intentionally shared by
    // first presentation, repeated navigation entries and post-picker refresh.
    [self refreshLiquidGlassInView:self.view];
    [self.view setNeedsLayout];
    [self.view layoutIfNeeded];
    DOCustomGlassApplyAdaptiveForeground(self.navigationController, self.view);
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    self.supporterAuthorizationVerified = DORHSupporterIsVerified();
    self.supporterAuthorizationKnown = YES;
    [self refreshThemePageFromPersistedState];

    // One deferred local-material pass is enough after the transition attaches
    // these Glass layers. Do not run wallpaper decode/blur a second time.
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        [weakSelf refreshLiquidGlassInView:weakSelf.view];
        [weakSelf.view setNeedsLayout];
        [weakSelf.view layoutIfNeeded];
    });
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
}

- (void)glassAppearanceChanged:(UISegmentedControl *)control
{
    if (![self requireCustomGlassSupporterAuthorization]) {
        [self syncAppearanceControlsFromDefaults];
        return;
    }

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *appearance = control.selectedSegmentIndex == 1 ?
        DOCustomGlassAppearanceDark : DOCustomGlassAppearanceLight;

    [defaults setObject:appearance forKey:DOCustomGlassAppearanceKey];
    [defaults synchronize];

    [[NSNotificationCenter defaultCenter]
        postNotificationName:DOCustomGlassThemeDidChangeNotification object:nil];

    [self refreshLiquidGlassInView:self.view];
    DOCustomGlassApplyAdaptiveForeground(self.navigationController, self.view);
}

- (void)appearanceSliderChanged:(UISlider *)slider
{
    if (![self requireCustomGlassSupporterAuthorization]) {
        [self syncAppearanceControlsFromDefaults];
        return;
    }

    [self applyAppearancePreviewAndPersist:YES];
}

- (void)wallpaperPlaybackRateChanged:(UISegmentedControl *)control
{
    if (![self requireCustomGlassSupporterAuthorization]) {
        [self syncAppearanceControlsFromDefaults];
        return;
    }

    CGFloat playbackRate = DOCustomGlassPlaybackRateForSegmentIndex(control.selectedSegmentIndex);
    [self.navigationController customGlassSetWallpaperPlaybackRate:playbackRate];
}

- (void)applyAppearancePreviewAndPersist:(BOOL)persist
{
    if (persist && ![self requireCustomGlassSupporterAuthorization]) {
        [self syncAppearanceControlsFromDefaults];
        return;
    }

    CGFloat backgroundBlur = self.backgroundBlurSlider.value;
    CGFloat glassBlur = self.glassBlurSlider.value;
    CGFloat transparency = self.glassTransparencySlider.value;
    CGFloat tintAlpha = self.glassTintSlider.value;

    [self.navigationController customGlassApplySharedBackgroundBlurIntensity:backgroundBlur];

    if (persist) {
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        [defaults setFloat:backgroundBlur forKey:DOCustomGlassBackgroundBlurKey];
        [defaults setFloat:glassBlur forKey:DOCustomGlassBlurIntensityKey];
        [defaults setFloat:transparency forKey:DOCustomGlassTransparencyKey];
        [defaults setFloat:tintAlpha forKey:DOCustomGlassTintAlphaKey];
        [defaults synchronize];

        // DOMainViewController stays alive underneath this pushed settings page.
        // Notify it immediately so its already-created Glass surfaces consume
        // the same values now, rather than depending only on navigation timing.
        [[NSNotificationCenter defaultCenter]
            postNotificationName:DOCustomGlassThemeDidChangeNotification object:nil];
    }

    // Refresh every glass surface on this page, including the Background row
    // and the live controls panel, from the exact same persisted parameters the
    // home screen will read when it becomes visible again.
    [self refreshLiquidGlassInView:self.view];
    DOCustomGlassApplyAdaptiveForeground(self.navigationController, self.view);

    self.backgroundBlurValueLabel.text = [NSString stringWithFormat:@"%.0f%%", backgroundBlur * 100.0];
    self.glassBlurValueLabel.text = [NSString stringWithFormat:@"%.0f%%", glassBlur * 100.0];
    self.glassTransparencyValueLabel.text = [NSString stringWithFormat:@"%.0f%%", transparency * 100.0];
    self.glassTintValueLabel.text = [NSString stringWithFormat:@"%.0f%%", (tintAlpha / 0.16) * 100.0];
}

- (void)restoreRecommendedAppearanceValues
{
    if (![self requireCustomGlassSupporterAuthorization])
        return;

    self.glassAppearanceControl.selectedSegmentIndex = 0;
    self.backgroundBlurSlider.value = 0.10;
    self.glassBlurSlider.value = 0.85;
    self.glassTransparencySlider.value = 0.70;
    self.glassTintSlider.value = 0.05;
    if (self.wallpaperPlaybackRateControl)
        self.wallpaperPlaybackRateControl.selectedSegmentIndex = 1;

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:DOCustomGlassAppearanceLight forKey:DOCustomGlassAppearanceKey];
    [self.navigationController customGlassSetWallpaperPlaybackRate:DOCustomGlassWallpaperPlaybackRateDefault];

    [self applyAppearancePreviewAndPersist:YES];
}

- (void)handleEdgeBackGesture:(UIScreenEdgePanGestureRecognizer *)gesture
{
    if (gesture.state != UIGestureRecognizerStateEnded)
        return;

    CGPoint translation = [gesture translationInView:self.view];
    CGPoint velocity = [gesture velocityInView:self.view];
    if (translation.x > 70.0 && velocity.x > 100.0)
        [self.navigationController popViewControllerAnimated:YES];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:DORHSupporterLicenseDidChangeNotification
                                                  object:nil];
}

@end
