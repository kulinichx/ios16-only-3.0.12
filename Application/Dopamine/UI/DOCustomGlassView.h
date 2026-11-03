#pragma once
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <math.h>

@interface UINavigationController (DOCustomGlassSharedBackground)
- (void)customGlassRefreshSharedBackground;
- (void)customGlassReplaceSharedBackgroundWithImage:(UIImage *)image;
- (void)customGlassApplySharedBackgroundBlurIntensity:(CGFloat)blurIntensity;
- (BOOL)customGlassIsUsingVideoWallpaper;
- (void)customGlassSetWallpaperPlaybackRate:(CGFloat)playbackRate;
- (BOOL)customGlassHasSharedBackground;
- (UIImage *)customGlassCurrentDisplayedBackgroundImage;
- (UIView *)customGlassBackgroundSamplingView;
- (UIView *)customGlassWallpaperScrimSamplingView;
- (NSArray<NSNumber *> *)customGlassCurrentWallpaperScrimLocations;
- (NSArray<NSNumber *> *)customGlassCurrentWallpaperScrimAlphas;
- (BOOL)customGlassPrefersDarkForegroundForView:(UIView *)view;
@end

static UIColor *DOCustomGlassForegroundColorForMode(BOOL darkForeground, CGFloat alpha)
{
    return [UIColor colorWithWhite:(darkForeground ? 0.08 : 1.0) alpha:alpha];
}

static void DOCustomGlassApplyForegroundMode(UIView *view, BOOL darkForeground)
{
    if (!view)
        return;

    if ([view isKindOfClass:[UILabel class]]) {
        UILabel *label = (UILabel *)view;
        CGFloat alpha = label.font.pointSize >= 15.0 ? 0.96 : 0.78;
        label.textColor = DOCustomGlassForegroundColorForMode(darkForeground, alpha);
        label.shadowColor = [UIColor colorWithWhite:(darkForeground ? 1.0 : 0.0) alpha:0.08];
        label.shadowOffset = CGSizeMake(0.0, 0.30);
    }
    else if ([view isKindOfClass:[UIButton class]]) {
        UIButton *button = (UIButton *)view;
        UIColor *foreground = DOCustomGlassForegroundColorForMode(darkForeground, 0.96);
        button.tintColor = foreground;
        if (button.configuration) {
            UIButtonConfiguration *configuration = [button.configuration copy];
            configuration.baseForegroundColor = foreground;
            button.configuration = configuration;
        }
        [button setTitleColor:foreground forState:UIControlStateNormal];
    }
    else if ([view isKindOfClass:[UIImageView class]]) {
        UIImageView *imageView = (UIImageView *)view;
        if (imageView.image.renderingMode == UIImageRenderingModeAlwaysTemplate)
            imageView.tintColor = DOCustomGlassForegroundColorForMode(darkForeground, 0.94);
    }

    for (UIView *subview in view.subviews)
        DOCustomGlassApplyForegroundMode(subview, darkForeground);
}

static void DOCustomGlassApplyAdaptiveForeground(UINavigationController *navigationController, UIView *view)
{
    // Custom Glass uses stable Light Content. Wallpaper luminance still drives
    // material-body separation inside DOCustomLiquidGlassView, but it must never
    // flip labels/icons between black and white on bright photos.
    (void)navigationController;
    DOCustomGlassApplyForegroundMode(view, NO);
}

static NSString * const DOCustomGlassBackgroundBlurKey = @"DOCustomGlassTheme.BackgroundBlur";
static NSString * const DOCustomGlassBlurIntensityKey = @"DOCustomGlassTheme.GlassBlurIntensity";
static NSString * const DOCustomGlassTransparencyKey = @"DOCustomGlassTheme.GlassTransparency";
static NSString * const DOCustomGlassTintAlphaKey = @"DOCustomGlassTheme.GlassTintAlpha";
static NSString * const DOCustomGlassAppearanceKey = @"DOCustomGlassTheme.Appearance";
static NSString * const DOCustomGlassAppearanceLight = @"light";
static NSString * const DOCustomGlassAppearanceDark = @"dark";
static NSString * const DOCustomGlassUsernameKey = @"DOCustomGlassTheme.Username";
static NSString * const DOCustomGlassMottoKey = @"DOCustomGlassTheme.Motto";
static NSString * const DOCustomGlassProfileFocusEnabledKey = @"DOCustomGlassTheme.ProfileFocusEnabled";
static NSString * const DOCustomGlassProfileFocusDockRightKey = @"DOCustomGlassTheme.ProfileFocusDockRight";
static NSString * const DOCustomGlassWallpaperPlaybackRateKey = @"DOCustomGlassTheme.WallpaperPlaybackRate";
static CGFloat const DOCustomGlassWallpaperPlaybackRateDefault = 0.65;
static NSString * const DOCustomGlassThemeDidChangeNotification = @"DOCustomGlassTheme.DidChange";
static NSUInteger const DOCustomGlassUsernameCharacterLimit = 20;
static NSUInteger const DOCustomGlassMottoCharacterLimit = 32;

static inline CGFloat DOCustomGlassClamp01(CGFloat value)
{
    return MIN(1.0, MAX(0.0, value));
}

static UIImage *DOCustomGlassSolidImage(UIColor *color)
{
    CGRect rect = CGRectMake(0.0, 0.0, 1.0, 1.0);
    UIGraphicsBeginImageContextWithOptions(rect.size, NO, 0.0);
    [color setFill];
    UIRectFill(rect);
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

static id DOCustomGlassCreateCAFilter(NSString *type)
{
    Class filterClass = NSClassFromString(@"CAFilter");
    SEL selector = NSSelectorFromString(@"filterWithType:");
    if (!filterClass || ![filterClass respondsToSelector:selector])
        return nil;

    IMP implementation = [filterClass methodForSelector:selector];
    typedef id (*DOCustomGlassFilterFactoryIMP)(id, SEL, id);
    DOCustomGlassFilterFactoryIMP factory = (DOCustomGlassFilterFactoryIMP)implementation;
    return factory(filterClass, selector, type);
}

@interface DOCustomLiquidGlassView : UIView

@property(nonatomic, strong) UIView *contentView;
@property(nonatomic, strong) UIView *neutralTintView;
@property(nonatomic, strong) UIVisualEffectView *fallbackBlurView;
@property(nonatomic, strong) CAGradientLayer *specularGradientLayer;
@property(nonatomic, strong) CAShapeLayer *specularMaskLayer;
@property(nonatomic, strong) CAGradientLayer *specularBoostGradientLayer;
@property(nonatomic, strong) CAShapeLayer *specularBoostMaskLayer;
@property(nonatomic, strong) CAGradientLayer *specularDarkGradientLayer;
@property(nonatomic, strong) CAShapeLayer *specularDarkMaskLayer;
@property(nonatomic, assign) CGFloat preferredCornerRadius;
@property(nonatomic, assign) CGFloat baseTintAlpha;
@property(nonatomic, assign) CGFloat materialScale;
@property(nonatomic, assign) CGFloat materialBodyScale;
@property(nonatomic, assign) CGFloat materialOpticalScale;
@property(nonatomic, assign) CGFloat materialBackdropScale;
@property(nonatomic, assign) CGFloat materialSpecularScale;
@property(nonatomic, assign) CGFloat materialEdgeDarkScale;
@property(nonatomic, assign) BOOL suppressBackdrop;
@property(nonatomic, assign) CGFloat lastRenderedShortDimension;

- (instancetype)initWithCornerRadius:(CGFloat)cornerRadius baseTintAlpha:(CGFloat)baseTintAlpha;
- (void)reloadMaterial;

@end

static void DOCustomGlassApplyMainMaterialProfile(DOCustomLiquidGlassView *glassView)
{
    if (!glassView)
        return;

    glassView.materialScale = 0.90;
    glassView.materialBodyScale = 0.92;
    glassView.materialOpticalScale = 0.84;
    glassView.materialBackdropScale = 0.92;
    glassView.materialSpecularScale = 0.82;
    glassView.materialEdgeDarkScale = 0.88;
    glassView.suppressBackdrop = NO;
}

@interface DOCustomGlassThemeSettingsViewController : UIViewController
- (void)prepareForPresentation;
- (void)refreshThemePageFromPersistedState;
@end
