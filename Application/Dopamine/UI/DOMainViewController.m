//
//  DOMainViewController.m
//  Dopamine
//
//  Created by tomt000 on 08/01/2024.
//

#import "DOMainViewController.h"
#import "DOUIManager.h"
#import "DOEnvironmentManager.h"
#import "DOJailbreaker.h"
#import "DOGlobalAppearance.h"
#import "DOActionMenuButton.h"
#import "DOUpdateViewController.h"
#import "DOLogCrashViewController.h"
#import "DOCustomGlassView.h"
#import "DOCustomGlassMediaStore.h"
#import "DONavigationController.h"
#import "DOSupporterLicense.h"
#import "Settings/DOSettingsController.h"
#import <PhotosUI/PhotosUI.h>
#import <math.h>
#import <pthread.h>
#import <sys/sysctl.h>
#import <mach/mach_time.h>
#import <libjailbreak/libjailbreak.h>

@interface DOMainViewController () <PHPickerViewControllerDelegate>

@property DOJailbreakButton *jailbreakBtn;
@property UIStackView *mainStack;
@property UILabel *systemUptimeLabel;
@property NSTimer *uptimeTimer;
@property(nonatomic) BOOL informationVisible;
@property NSArray<NSLayoutConstraint *> *jailbreakButtonConstraints;
@property DOActionMenuButton *updateButton;
@property NSLayoutConstraint *customGlassJailbreakCenterYConstraint;
@property UIImageView *customGlassAvatarPhotoView;
@property(nonatomic, strong) UIView *customGlassAvatarContainerView;
@property(nonatomic, strong) DOCustomLiquidGlassView *customGlassAvatarMaterialView;
@property(nonatomic, strong) UIImageView *customGlassAvatarFallbackIconView;
@property(nonatomic, strong) NSArray<UIView *> *customGlassHeaderSubtitleLabels;
@property(nonatomic, strong) NSLayoutConstraint *customGlassAvatarWidthConstraint;
@property(nonatomic, strong) NSLayoutConstraint *customGlassAvatarHeightConstraint;
@property(nonatomic, strong) NSLayoutConstraint *customGlassAvatarIconWidthConstraint;
@property(nonatomic, strong) NSLayoutConstraint *customGlassAvatarIconHeightConstraint;
@property(nonatomic, strong) NSLayoutConstraint *customGlassAvatarCenterXConstraint;
@property(nonatomic, strong) NSLayoutConstraint *customGlassAvatarLeadingDockConstraint;
@property(nonatomic, strong) NSLayoutConstraint *customGlassAvatarTrailingDockConstraint;
@property(nonatomic, assign) CGFloat customGlassAvatarNormalSize;
@property(nonatomic, assign) CGFloat customGlassAvatarFocusSize;
@property(nonatomic, assign) BOOL customGlassProfileFocusEnabled;
@property(nonatomic, assign) BOOL customGlassProfileFocusDockRight;
@property UILabel *customGlassUsernameLabel;
@property UIAlertController *customGlassUsernameEditor;
@property UILabel *customGlassMottoLabel;
@property UIAlertController *customGlassMottoEditor;
@property DOCustomLiquidGlassView *customGlassThemeCard;
@property UILabel *customGlassSystemLabel;
@property(nonatomic, strong) UIView *customGlassJailbreakDisabledOverlay;

@property(nonatomic) BOOL hideStatusBar;
@property(nonatomic) BOOL hideHomeIndicator;

@end

@implementation DOMainViewController

- (BOOL)requireCustomGlassSupporterAuthorization
{
    if (DORHSupporterIsVerified())
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
    [self presentViewController:alert animated:YES completion:nil];
    return NO;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupCustomGlassHome];
    if (UIApplication.sharedApplication.alternateIconName != nil) {
        [UIApplication.sharedApplication setAlternateIconName:nil completionHandler:^(NSError *error) {
            if (error) NSLog(@"[CustomGlass] Restoring primary icon failed: %@", error);
        }];
    }
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(resumeSystemInformationUpdates) name:UIApplicationDidBecomeActiveNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(stopUptimeTimer) name:UIApplicationWillResignActiveNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self
                                             selector:@selector(supporterLicenseDidChange:)
                                                 name:DORHSupporterLicenseDidChangeNotification
                                               object:nil];
}


- (void)applyCustomGlassHomeAppearance
{
    // The navigation controller owns wallpaper source + blur. Home only updates
    // its local Glass materials from the persisted Glass controls.
    // Every home Glass surface is already mounted in self.view. Walking that
    // hierarchy makes Settings / About / Theme Settings / restart pills / the
    // restart shell / jailbreak emphasis all consume the same persisted values.
    [self refreshCustomGlassMaterialInView:self.view];
    [self.view setNeedsLayout];
    [self.view layoutIfNeeded];

    DOCustomGlassApplyAdaptiveForeground(self.navigationController, self.view);
}

- (void)customGlassThemeDidChange:(NSNotification *)notification
{
    if (![NSThread isMainThread]) {
        __weak typeof(self) weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf customGlassThemeDidChange:notification];
        });
        return;
    }

    [self applyCustomGlassHomeAppearance];
}

- (void)refreshCustomGlassButtonState
{
    BOOL active = [[DOEnvironmentManager sharedManager] isJailbroken] || [[DOEnvironmentManager sharedManager] isJailbrokenWithOtherJailbreak];
    BOOL supporterVerified = DORHSupporterIsVerified();
    BOOL canStartJailbreak = supporterVerified &&
        !active &&
        [[DOEnvironmentManager sharedManager] isSupported];
    self.jailbreakBtn.enabled = canStartJailbreak;
    self.jailbreakBtn.alpha = 1.0;
    self.jailbreakBtn.button.alpha = canStartJailbreak ? 1.0 : 0.70;
    UIButtonConfiguration *buttonConfiguration = self.jailbreakBtn.button.configuration;
    buttonConfiguration.baseForegroundColor = supporterVerified ?
        UIColor.whiteColor :
        [UIColor colorWithWhite:0.68 alpha:1.0];
    self.jailbreakBtn.button.configuration = buttonConfiguration;
    self.customGlassJailbreakDisabledOverlay.hidden = supporterVerified;
    self.customGlassSystemLabel.text = [NSString stringWithFormat:@"iOS %@", UIDevice.currentDevice.systemVersion];
}

- (void)supporterLicenseDidChange:(NSNotification *)notification
{
    (void)notification;
    if (![NSThread isMainThread]) {
        __weak typeof(self) weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf supporterLicenseDidChange:notification];
        });
        return;
    }

    [self refreshCustomGlassButtonState];
    [self applyCustomGlassHomeAppearance];
}

- (void)presentCustomGlassAvatarPicker
{
    PHPickerConfiguration *configuration = [[PHPickerConfiguration alloc] init];
    configuration.filter = [PHPickerFilter imagesFilter];
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
    if (![provider canLoadObjectOfClass:UIImage.class])
        return;

    __weak typeof(self) weakSelf = self;
    [provider loadObjectOfClass:UIImage.class
              completionHandler:^(id<NSItemProviderReading> object, NSError *error) {
        if (error || ![object isKindOfClass:UIImage.class])
            return;

        UIImage *image = (UIImage *)object;
        if (!DORHSupporterIsVerified()) {
            weakSelf.customGlassUsernameEditor = nil;
            return;
        }

        UIImage *persistedAvatar = nil;
        BOOL saved = DOCustomGlassMediaStoreSaveAvatar(image, &persistedAvatar);

        dispatch_async(dispatch_get_main_queue(), ^{
            if (!saved)
                return;

            // Show the exact object decoded back from the committed media file.
            weakSelf.customGlassAvatarPhotoView.image = persistedAvatar;
            weakSelf.customGlassAvatarPhotoView.hidden = NO;
            // The docked lens makes the photo translucent; never let the
            // placeholder glyph show through a real avatar.
            weakSelf.customGlassAvatarFallbackIconView.hidden = YES;
        });
    }];
}

- (void)presentCustomGlassUsernameEditor
{
    if (![self requireCustomGlassSupporterAuthorization])
        return;

    NSString *currentUsername = [NSUserDefaults.standardUserDefaults stringForKey:DOCustomGlassUsernameKey] ?: @"";

    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:@"用户名"
                                            message:[NSString stringWithFormat:@"%lu / %lu",
                                                     (unsigned long)currentUsername.length,
                                                     (unsigned long)DOCustomGlassUsernameCharacterLimit]
                                     preferredStyle:UIAlertControllerStyleAlert];

    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.text = currentUsername;
        textField.placeholder = @"输入用户名";
        textField.clearButtonMode = UITextFieldViewModeWhileEditing;
        [textField addTarget:self
                      action:@selector(customGlassUsernameTextChanged:)
            forControlEvents:UIControlEventEditingChanged];
    }];

    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"取消"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"保存"
                                              style:UIAlertActionStyleDefault
                                            handler:^(__kindof UIAlertAction * _Nonnull action) {
        NSString *username = alert.textFields.firstObject.text ?: @"";
        if (username.length > DOCustomGlassUsernameCharacterLimit)
            username = [username substringToIndex:DOCustomGlassUsernameCharacterLimit];

        if (!DORHSupporterIsVerified()) {
            weakSelf.customGlassUsernameEditor = nil;
            return;
        }

        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        [defaults setObject:username forKey:DOCustomGlassUsernameKey];
        weakSelf.customGlassUsernameLabel.text = username.length > 0 ? username : @"RootHide User";
        weakSelf.customGlassUsernameEditor = nil;
    }]];

    self.customGlassUsernameEditor = alert;
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)customGlassUsernameTextChanged:(UITextField *)textField
{
    NSString *text = textField.text ?: @"";
    if (text.length > DOCustomGlassUsernameCharacterLimit) {
        text = [text substringToIndex:DOCustomGlassUsernameCharacterLimit];
        textField.text = text;
    }

    self.customGlassUsernameEditor.message =
        [NSString stringWithFormat:@"%lu / %lu",
         (unsigned long)text.length,
         (unsigned long)DOCustomGlassUsernameCharacterLimit];
}

- (void)presentCustomGlassMottoEditor
{
    if (![self requireCustomGlassSupporterAuthorization])
        return;

    NSString *currentMotto = [NSUserDefaults.standardUserDefaults stringForKey:DOCustomGlassMottoKey] ?: @"";

    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:@"个性签名"
                                            message:[NSString stringWithFormat:@"%lu / %lu",
                                                     (unsigned long)currentMotto.length,
                                                     (unsigned long)DOCustomGlassMottoCharacterLimit]
                                     preferredStyle:UIAlertControllerStyleAlert];

    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.text = currentMotto;
        textField.placeholder = @"输入个性签名";
        textField.clearButtonMode = UITextFieldViewModeWhileEditing;
        [textField addTarget:self
                      action:@selector(customGlassMottoTextChanged:)
            forControlEvents:UIControlEventEditingChanged];
    }];

    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"取消"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"保存"
                                              style:UIAlertActionStyleDefault
                                            handler:^(__kindof UIAlertAction * _Nonnull action) {
        NSString *motto = alert.textFields.firstObject.text ?: @"";
        if (motto.length > DOCustomGlassMottoCharacterLimit)
            motto = [motto substringToIndex:DOCustomGlassMottoCharacterLimit];

        if (!DORHSupporterIsVerified()) {
            weakSelf.customGlassMottoEditor = nil;
            return;
        }

        [[NSUserDefaults standardUserDefaults] setObject:motto forKey:DOCustomGlassMottoKey];
        weakSelf.customGlassMottoLabel.text = motto.length > 0 ? motto : @"motto";
        weakSelf.customGlassMottoEditor = nil;
    }]];

    self.customGlassMottoEditor = alert;
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)customGlassMottoTextChanged:(UITextField *)textField
{
    NSString *text = textField.text ?: @"";
    if (text.length > DOCustomGlassMottoCharacterLimit) {
        text = [text substringToIndex:DOCustomGlassMottoCharacterLimit];
        textField.text = text;
    }

    self.customGlassMottoEditor.message =
        [NSString stringWithFormat:@"%lu / %lu",
         (unsigned long)text.length,
         (unsigned long)DOCustomGlassMottoCharacterLimit];
}

- (DOCustomLiquidGlassView *)customGlassViewWithCornerRadius:(CGFloat)cornerRadius tintAlpha:(CGFloat)tintAlpha
{
    DOCustomLiquidGlassView *glassView =
        [[DOCustomLiquidGlassView alloc] initWithCornerRadius:cornerRadius baseTintAlpha:tintAlpha];
    glassView.translatesAutoresizingMaskIntoConstraints = NO;
    return glassView;
}

- (void)refreshCustomGlassMaterialInView:(UIView *)view
{
    if ([view isKindOfClass:[DOCustomLiquidGlassView class]])
        [(DOCustomLiquidGlassView *)view reloadMaterial];

    for (UIView *subview in view.subviews)
        [self refreshCustomGlassMaterialInView:subview];
}

- (UIButton *)customGlassButtonWithTitle:(NSString *)title imageName:(NSString *)imageName action:(UIAction *)action
{
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.translatesAutoresizingMaskIntoConstraints = NO;

    UIButtonConfiguration *configuration = [UIButtonConfiguration plainButtonConfiguration];
    configuration.title = title;

    BOOL isPad = [[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad;
    CGFloat symbolPointSize = isPad ? 21.0 : 19.0;
    UIImageSymbolConfiguration *symbolConfiguration =
        [UIImageSymbolConfiguration configurationWithPointSize:symbolPointSize
                                                        weight:UIImageSymbolWeightMedium
                                                         scale:UIImageSymbolScaleMedium];
    configuration.image = [UIImage systemImageNamed:imageName withConfiguration:symbolConfiguration];
    configuration.imagePadding = 8;
    configuration.baseForegroundColor = UIColor.whiteColor;
    configuration.titleTextAttributesTransformer = ^NSDictionary<NSAttributedStringKey,id> *(NSDictionary<NSAttributedStringKey,id> *incoming) {
        NSMutableDictionary *attributes = [incoming mutableCopy];
        attributes[NSFontAttributeName] = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
        return attributes;
    };
    button.configuration = configuration;
    [button addAction:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (DOCustomLiquidGlassView *)customGlassCardWithTitle:(NSString *)title imageName:(NSString *)imageName action:(UIAction *)action
{
    DOCustomLiquidGlassView *card = [self customGlassViewWithCornerRadius:24 tintAlpha:0.05];
    // Settings / About / Theme Settings consume the same Main Glass profile
    // used by the Theme Settings preview and the compact jailbreak bar.
    DOCustomGlassApplyMainMaterialProfile(card);
    [card reloadMaterial];
    UIButton *button = [self customGlassButtonWithTitle:title imageName:imageName action:action];
    [card.contentView addSubview:button];

    [NSLayoutConstraint activateConstraints:@[
        [button.leadingAnchor constraintEqualToAnchor:card.contentView.leadingAnchor],
        [button.trailingAnchor constraintEqualToAnchor:card.contentView.trailingAnchor],
        [button.topAnchor constraintEqualToAnchor:card.contentView.topAnchor],
        [button.bottomAnchor constraintEqualToAnchor:card.contentView.bottomAnchor]
    ]];
    return card;
}

- (DOCustomLiquidGlassView *)customGlassRestartButtonWithTitle:(NSString *)title imageName:(NSString *)imageName action:(UIAction *)action enabled:(BOOL)enabled cornerRadius:(CGFloat)cornerRadius
{
    DOCustomLiquidGlassView *innerGlass = [self customGlassViewWithCornerRadius:cornerRadius tintAlpha:0.0];
    // Inset Glass role. The restart platter owns the only real backdrop pass;
    // each action is just a shallow local surface on that shared glass plane.
    // Keep a small body/contour for touch hierarchy, but intentionally avoid the
    // second full-strength rim that previously made these read as three separate lenses.
    innerGlass.materialScale = 0.70;
    innerGlass.materialBodyScale = 0.24;
    innerGlass.materialOpticalScale = 0.36;
    innerGlass.materialBackdropScale = 0.0;
    innerGlass.materialSpecularScale = 0.48;
    innerGlass.materialEdgeDarkScale = 0.58;
    innerGlass.suppressBackdrop = YES;
    [innerGlass reloadMaterial];

    // Keep all restart actions on one shared icon/text grid. On iPhone the
    // content uses almost the full pill width so the longest localized title
    // does not get squeezed by the old 72% centered content constraint.
    BOOL isPad = [[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad;
    CGFloat iconSize = isPad ? 24.0 : 21.0;
    CGFloat iconToTitleSpacing = isPad ? 10.0 : 8.0;

    UIView *contentRow = [[UIView alloc] init];
    contentRow.translatesAutoresizingMaskIntoConstraints = NO;
    [innerGlass.contentView addSubview:contentRow];

    CGFloat restartSymbolPointSize = isPad ? 23.0 : 20.0;
    UIImageSymbolConfiguration *restartSymbolConfiguration =
        [UIImageSymbolConfiguration configurationWithPointSize:restartSymbolPointSize
                                                        weight:UIImageSymbolWeightMedium
                                                         scale:UIImageSymbolScaleMedium];

    // SF Symbols have different intrinsic visual mass even inside identical
    // image-view frames. Apply tiny optical corrections so the three restart
    // glyphs read as the same apparent size without changing their alignment.
    CGFloat restartIconOpticalScale = 1.0;
    if ([imageName isEqualToString:@"arrow.clockwise"]) {
        restartIconOpticalScale = 1.04;
    }
    else if ([imageName isEqualToString:@"arrow.clockwise.circle"]) {
        restartIconOpticalScale = 1.06;
    }
    else if ([imageName isEqualToString:@"power"]) {
        restartIconOpticalScale = 0.96;
    }

    UIImageView *iconView = [[UIImageView alloc] initWithImage:
        [UIImage systemImageNamed:imageName withConfiguration:restartSymbolConfiguration]];
    iconView.translatesAutoresizingMaskIntoConstraints = NO;
    iconView.tintColor = UIColor.whiteColor;
    iconView.alpha = enabled ? 1.0 : 0.46;
    iconView.contentMode = UIViewContentModeScaleAspectFit;
    iconView.transform = CGAffineTransformMakeScale(restartIconOpticalScale, restartIconOpticalScale);
    [contentRow addSubview:iconView];

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.text = title;
    titleLabel.textColor = UIColor.whiteColor;
    titleLabel.alpha = enabled ? 1.0 : 0.46;
    titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    titleLabel.textAlignment = NSTextAlignmentLeft;
    titleLabel.numberOfLines = 1;
    titleLabel.adjustsFontSizeToFitWidth = YES;
    titleLabel.minimumScaleFactor = 0.94;
    titleLabel.allowsDefaultTighteningForTruncation = YES;
    [contentRow addSubview:titleLabel];

    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.enabled = enabled;
    button.accessibilityLabel = title;
    [button addAction:action forControlEvents:UIControlEventTouchUpInside];
    [innerGlass.contentView addSubview:button];

    NSMutableArray<NSLayoutConstraint *> *contentConstraints = [NSMutableArray arrayWithArray:@[
        [contentRow.centerYAnchor constraintEqualToAnchor:innerGlass.contentView.centerYAnchor],
        [contentRow.heightAnchor constraintEqualToConstant:28],

        [iconView.leadingAnchor constraintEqualToAnchor:contentRow.leadingAnchor],
        [iconView.centerYAnchor constraintEqualToAnchor:contentRow.centerYAnchor],
        [iconView.widthAnchor constraintEqualToConstant:iconSize],
        [iconView.heightAnchor constraintEqualToConstant:iconSize],

        [titleLabel.leadingAnchor constraintEqualToAnchor:iconView.trailingAnchor constant:iconToTitleSpacing],
        [titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:contentRow.trailingAnchor],
        [titleLabel.centerYAnchor constraintEqualToAnchor:contentRow.centerYAnchor],

        [button.leadingAnchor constraintEqualToAnchor:innerGlass.contentView.leadingAnchor],
        [button.trailingAnchor constraintEqualToAnchor:innerGlass.contentView.trailingAnchor],
        [button.topAnchor constraintEqualToAnchor:innerGlass.contentView.topAnchor],
        [button.bottomAnchor constraintEqualToAnchor:innerGlass.contentView.bottomAnchor]
    ]];

    if (isPad) {
        [contentConstraints addObjectsFromArray:@[
            [contentRow.centerXAnchor constraintEqualToAnchor:innerGlass.contentView.centerXAnchor],
            [contentRow.widthAnchor constraintEqualToAnchor:innerGlass.contentView.widthAnchor multiplier:0.72]
        ]];
    }
    else {
        [contentConstraints addObjectsFromArray:@[
            [contentRow.leadingAnchor constraintEqualToAnchor:innerGlass.contentView.leadingAnchor constant:18.0],
            [contentRow.trailingAnchor constraintEqualToAnchor:innerGlass.contentView.trailingAnchor constant:-12.0]
        ]];
    }

    [NSLayoutConstraint activateConstraints:contentConstraints];
    return innerGlass;
}

- (void)setCustomGlassProfileFocusEnabled:(BOOL)enabled
                                 dockRight:(BOOL)dockRight
                                  animated:(BOOL)animated
                                   persist:(BOOL)persist
{
    if (!self.customGlassAvatarContainerView)
        return;

    self.customGlassProfileFocusEnabled = enabled;
    self.customGlassProfileFocusDockRight = dockRight;

    if (persist) {
        NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
        [defaults setBool:enabled forKey:DOCustomGlassProfileFocusEnabledKey];
        [defaults setBool:dockRight forKey:DOCustomGlassProfileFocusDockRightKey];
    }

    [self.view layoutIfNeeded];

    if (enabled) {
        self.customGlassAvatarCenterXConstraint.active = NO;
        self.customGlassAvatarLeadingDockConstraint.active = !dockRight;
        self.customGlassAvatarTrailingDockConstraint.active = dockRight;
    }
    else {
        self.customGlassAvatarLeadingDockConstraint.active = NO;
        self.customGlassAvatarTrailingDockConstraint.active = NO;
        self.customGlassAvatarCenterXConstraint.active = YES;
    }

    CGFloat avatarSize = enabled ? self.customGlassAvatarFocusSize : self.customGlassAvatarNormalSize;
    CGFloat avatarIconSize = avatarSize * 0.62;
    self.customGlassAvatarWidthConstraint.constant = avatarSize;
    self.customGlassAvatarHeightConstraint.constant = avatarSize;
    self.customGlassAvatarIconWidthConstraint.constant = avatarIconSize;
    self.customGlassAvatarIconHeightConstraint.constant = avatarIconSize;

    // Focus mode is a small translucent Liquid Glass lens instead of an opaque
    // profile sticker. Keep the photo readable, but let the live wallpaper/video
    // transmit through it so the docked avatar belongs to the same material family.
    DOCustomLiquidGlassView *avatarMaterial = self.customGlassAvatarMaterialView;
    if (avatarMaterial) {
        avatarMaterial.preferredCornerRadius = avatarSize / 2.0;
        avatarMaterial.materialScale = enabled ? 0.70 : 0.46;
        avatarMaterial.materialBodyScale = enabled ? 0.68 : 0.34;
        avatarMaterial.materialOpticalScale = enabled ? 0.82 : 0.52;
        avatarMaterial.materialBackdropScale = enabled ? 0.78 : 0.34;
        avatarMaterial.materialSpecularScale = enabled ? 1.00 : 0.54;
        avatarMaterial.materialEdgeDarkScale = enabled ? 0.38 : 0.42;
        avatarMaterial.suppressBackdrop = NO;
        [avatarMaterial reloadMaterial];
    }

    self.customGlassAvatarContainerView.accessibilityLabel = enabled ? @"恢复个人资料" : @"更换头像";
    self.customGlassUsernameLabel.userInteractionEnabled = !enabled;
    self.customGlassMottoLabel.userInteractionEnabled = !enabled;

    void (^updates)(void) = ^{
        self.customGlassAvatarContainerView.transform = CGAffineTransformIdentity;
        self.customGlassAvatarContainerView.layer.cornerRadius = avatarSize / 2.0;
        self.customGlassAvatarContainerView.layer.shadowOpacity = enabled ? 0.035 : 0.16;
        self.customGlassAvatarContainerView.layer.shadowRadius = enabled ? 4.0 : 6.0;
        self.customGlassAvatarPhotoView.layer.cornerRadius = MAX(0.0, (avatarSize - 2.0) / 2.0);
        self.customGlassAvatarPhotoView.alpha = enabled ? 0.34 : 1.0;
        self.customGlassAvatarFallbackIconView.alpha = enabled ? 0.44 : 1.0;

        CGFloat detailAlpha = enabled ? 0.0 : 1.0;
        self.customGlassUsernameLabel.alpha = detailAlpha;
        self.customGlassSystemLabel.alpha = detailAlpha;
        self.customGlassMottoLabel.alpha = detailAlpha;
        for (UIView *label in self.customGlassHeaderSubtitleLabels)
            label.alpha = detailAlpha;

        [self.view layoutIfNeeded];
    };

    if (animated) {
        [UIView animateWithDuration:0.26
                              delay:0.0
             usingSpringWithDamping:0.88
              initialSpringVelocity:0.35
                            options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionBeginFromCurrentState
                         animations:updates
                         completion:nil];
    }
    else {
        updates();
    }
}

- (void)customGlassAvatarTapped:(UITapGestureRecognizer *)gesture
{
    if (gesture.state != UIGestureRecognizerStateEnded)
        return;

    if (self.customGlassProfileFocusEnabled) {
        [self setCustomGlassProfileFocusEnabled:NO
                                      dockRight:self.customGlassProfileFocusDockRight
                                       animated:YES
                                        persist:YES];
        return;
    }

    if (![self requireCustomGlassSupporterAuthorization])
        return;

    [self presentCustomGlassAvatarPicker];
}

- (void)customGlassAvatarPanned:(UIPanGestureRecognizer *)gesture
{
    UIView *avatarView = self.customGlassAvatarContainerView;
    if (!avatarView)
        return;

    CGPoint translation = [gesture translationInView:self.view];
    CGPoint velocity = [gesture velocityInView:self.view];

    // Docking is deliberately edge-gated: the avatar follows the finger all the
    // way to a real screen edge, and only becomes Focus when it actually reaches
    // the magnetic edge zone. A quick short flick near the center never docks.
    CGRect screenFrame = self.view.bounds;
    CGPoint avatarCenter = [avatarView.superview convertPoint:avatarView.center toView:self.view];
    // Dock by the avatar's *center* against the physical view edge. Roughly 30%
    // of the compact Focus avatar is allowed to sit outside the screen so it reads
    // as an edge tab instead of a floating badge with an inset margin.
    CGFloat focusPeekCenter = MAX(8.0, self.customGlassAvatarFocusSize * 0.20);
    CGFloat leftTargetX = CGRectGetMinX(screenFrame) + focusPeekCenter;
    CGFloat rightTargetX = CGRectGetMaxX(screenFrame) - focusPeekCenter;
    CGFloat leftTravel = leftTargetX - avatarCenter.x;
    CGFloat rightTravel = rightTargetX - avatarCenter.x;

    if (gesture.state == UIGestureRecognizerStateChanged) {
        CGFloat drag = translation.x;
        if (self.customGlassProfileFocusEnabled) {
            BOOL towardCenter = self.customGlassProfileFocusDockRight ? (drag < 0.0) : (drag > 0.0);
            drag *= towardCenter ? 0.72 : 0.10;
        }
        else {
            drag = MAX(leftTravel, MIN(rightTravel, drag));
        }
        avatarView.transform = CGAffineTransformMakeTranslation(drag, 0.0);
        return;
    }

    if (gesture.state != UIGestureRecognizerStateEnded &&
        gesture.state != UIGestureRecognizerStateCancelled &&
        gesture.state != UIGestureRecognizerStateFailed)
        return;

    if (self.customGlassProfileFocusEnabled) {
        BOOL towardCenter = self.customGlassProfileFocusDockRight ?
            (translation.x < 0.0) : (translation.x > 0.0);
        BOOL shouldRestore = towardCenter &&
            (fabs(translation.x) >= 28.0 || fabs(velocity.x) >= 360.0);
        if (shouldRestore) {
            [self setCustomGlassProfileFocusEnabled:NO
                                          dockRight:self.customGlassProfileFocusDockRight
                                           animated:YES
                                            persist:YES];
        }
        else {
            [UIView animateWithDuration:0.20
                             animations:^{ avatarView.transform = CGAffineTransformIdentity; }];
        }
        return;
    }

    CGFloat edgeMagnet = 14.0;
    BOOL reachedLeftEdge = translation.x <= (leftTravel + edgeMagnet);
    BOOL reachedRightEdge = translation.x >= (rightTravel - edgeMagnet);
    if (!reachedLeftEdge && !reachedRightEdge) {
        [UIView animateWithDuration:0.22
                              delay:0.0
             usingSpringWithDamping:0.82
              initialSpringVelocity:0.25
                            options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState
                         animations:^{ avatarView.transform = CGAffineTransformIdentity; }
                         completion:nil];
        return;
    }

    [self setCustomGlassProfileFocusEnabled:YES
                                  dockRight:reachedRightEdge
                                   animated:YES
                                    persist:YES];
}

- (void)configureCustomGlassHeaderView:(DOHeaderView *)headerView logoHeight:(CGFloat)logoHeight subtitleScale:(CGFloat)subtitleScale
{
    [headerView applyGlassLayoutWithLogoHeight:logoHeight subtitleScale:subtitleScale];
}

- (void)setupCustomGlassHome
{
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(customGlassThemeDidChange:)
                                                 name:DOCustomGlassThemeDidChangeNotification
                                               object:nil];

    // Shared wallpaper/blur lives below the navigation transition container.
    // Home only owns foreground content and Glass surfaces.

    BOOL isPad = [[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad;
    CGFloat availableHeight = CGRectGetHeight(self.view.bounds);
    BOOL compactLayout = !isPad && availableHeight < 720.0;

    // Keep one visual structure on every device. Only dimensions change so the
    // reference layout remains intact on compact iPhones, regular iPhones and iPad.
    CGFloat mainSpacing = compactLayout ? 8.0 : 12.0;
    CGFloat topInset = isPad ? 24.0 : (compactLayout ? 6.0 : 10.0);
    CGFloat horizontalInset = compactLayout ? 20.0 : 25.0;
    CGFloat headerToProfileSpacing = isPad ? 29.0 : (compactLayout ? 14.0 : 18.0);
    CGFloat logoHeight = isPad ? 55.0 : (compactLayout ? 39.0 : 40.0);
    CGFloat headerSubtitleScale = isPad ? 1.09 : (compactLayout ? 0.93 : 0.95);
    CGFloat avatarSize = isPad ? 104.0 : (compactLayout ? 72.0 : 84.0);
    CGFloat avatarIconSize = avatarSize * 0.62;
    CGFloat gridDrop = isPad ? 14.0 : (compactLayout ? 6.0 : 8.0);
    CGFloat profileToGridSpacing = (isPad ? 15.0 : (compactLayout ? 15.0 : 18.0)) + gridDrop;
    CGFloat gridHeight = isPad ? 300.0 : (compactLayout ? 214.0 : 250.0);
    CGFloat themeCardHeight = isPad ? 60.0 : (compactLayout ? 48.0 : 52.0);
    CGFloat restartPadding = isPad ? 14.0 : (compactLayout ? 10.0 : 12.0);
    CGFloat restartSpacing = isPad ? 12.0 : (compactLayout ? 8.0 : 10.0);
    CGFloat restartContainerHeight = gridHeight - themeCardHeight - mainSpacing;
    CGFloat restartButtonHeight = (restartContainerHeight - (restartPadding * 2.0) - (restartSpacing * 2.0)) / 3.0;
    CGFloat restartCornerRadius = restartButtonHeight / 2.0;
    CGFloat usernameFontSize = isPad ? 24.0 : (compactLayout ? 16.0 : 19.0);
    CGFloat systemFontSize = isPad ? 18.0 : (compactLayout ? 12.0 : 15.0);
    CGFloat mottoFontSize = isPad ? 21.0 : (compactLayout ? 13.0 : 16.0);
    CGFloat avatarToUsernameSpacing = isPad ? 12.0 : (compactLayout ? 9.0 : 10.0);
    CGFloat usernameToSystemSpacing = isPad ? 4.0 : (compactLayout ? 2.0 : 3.0);
    CGFloat systemToMottoSpacing = isPad ? 12.0 : (compactLayout ? 9.0 : 10.0);
    CGFloat leftColumnWidthMultiplier = isPad ? 0.34 : 0.35;
    CGFloat jailbreakButtonHeight = isPad ? 60.0 : (compactLayout ? 44.0 : 48.0);
    CGFloat jailbreakVerticalOffset = isPad ? -12.0 : (compactLayout ? -24.0 : -30.0);
    CGFloat jailbreakHorizontalInset = isPad ? 0.0 : 4.0;

    UIStackView *mainStack = [[UIStackView alloc] init];
    mainStack.axis = UILayoutConstraintAxisVertical;
    mainStack.alignment = UIStackViewAlignmentFill;
    mainStack.distribution = UIStackViewDistributionFill;
    mainStack.spacing = mainSpacing;
    mainStack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:mainStack];

    self.mainStack = mainStack;
    UILayoutGuide *safeArea = self.view.safeAreaLayoutGuide;
    if (isPad) {
        NSLayoutConstraint *relativeWidthConstraint = [mainStack.widthAnchor constraintEqualToAnchor:self.view.widthAnchor multiplier:0.8];
        relativeWidthConstraint.priority = UILayoutPriorityDefaultHigh;
        NSLayoutConstraint *maxWidthConstraint = [mainStack.widthAnchor constraintLessThanOrEqualToConstant:UI_IPAD_MAX_WIDTH];
        NSLayoutConstraint *verticalPositionConstraint = [mainStack.centerYAnchor constraintEqualToAnchor:safeArea.centerYAnchor constant:-10.0];
        verticalPositionConstraint.priority = UILayoutPriorityDefaultHigh;
        [NSLayoutConstraint activateConstraints:@[
            [mainStack.topAnchor constraintGreaterThanOrEqualToAnchor:safeArea.topAnchor constant:topInset],
            [mainStack.bottomAnchor constraintLessThanOrEqualToAnchor:safeArea.bottomAnchor constant:-12.0],
            [mainStack.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
            verticalPositionConstraint,
            relativeWidthConstraint,
            maxWidthConstraint
        ]];
    }
    else {
        NSLayoutConstraint *verticalPositionConstraint = [mainStack.centerYAnchor constraintEqualToAnchor:safeArea.centerYAnchor];
        verticalPositionConstraint.priority = UILayoutPriorityDefaultHigh;
        [NSLayoutConstraint activateConstraints:@[
            [mainStack.topAnchor constraintGreaterThanOrEqualToAnchor:safeArea.topAnchor constant:topInset],
            [mainStack.bottomAnchor constraintLessThanOrEqualToAnchor:safeArea.bottomAnchor constant:-8.0],
            [mainStack.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:horizontalInset],
            [mainStack.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-horizontalInset],
            verticalPositionConstraint
        ]];
    }

    // Keep the original DOHeaderView so version/author/uptime retain Dopamine's
    // existing internal spacing and behavior. Custom Home only centers that stack
    // and gives the Dopamine logo slightly more visual weight.
    DOHeaderView *headerView = [[DOHeaderView alloc] initWithImage:[UIImage imageNamed:@"Dopamine"] subtitles:@[
        [DOGlobalAppearance mainSubtitleString:[[DOEnvironmentManager sharedManager] versionSupportString]],
        [DOGlobalAppearance secondarySubtitleString:DOLocalizedString(@"Credits_Made_By")]
    ]];
    self.systemUptimeLabel = [headerView addSubtitle:
        [DOGlobalAppearance secondarySubtitleString:
            [NSString stringWithFormat:DOLocalizedString(@"Home_Uptime_Format"), [self systemUptimeDescription]]]];
    [self configureCustomGlassHeaderView:headerView logoHeight:logoHeight subtitleScale:headerSubtitleScale];

    NSMutableArray<UIView *> *headerSubtitleLabels = [NSMutableArray array];
    for (UIView *subview in headerView.subviews) {
        if (![subview isKindOfClass:[UIStackView class]])
            continue;
        for (UIView *arrangedSubview in ((UIStackView *)subview).arrangedSubviews) {
            if ([arrangedSubview isKindOfClass:[UILabel class]] || [arrangedSubview isKindOfClass:[UIStackView class]])
                [headerSubtitleLabels addObject:arrangedSubview];
        }
    }
    self.customGlassHeaderSubtitleLabels = headerSubtitleLabels;

    [mainStack addArrangedSubview:headerView];
    [mainStack setCustomSpacing:headerToProfileSpacing afterView:headerView];

    UIView *profileView = [[UIView alloc] init];
    profileView.translatesAutoresizingMaskIntoConstraints = NO;
    [mainStack addArrangedSubview:profileView];
    [mainStack setCustomSpacing:profileToGridSpacing afterView:profileView];

    UIView *avatarGlass = [[UIView alloc] init];
    avatarGlass.translatesAutoresizingMaskIntoConstraints = NO;
    avatarGlass.backgroundColor = UIColor.clearColor;
    avatarGlass.layer.cornerRadius = avatarSize / 2.0;
    avatarGlass.layer.cornerCurve = kCACornerCurveContinuous;
    avatarGlass.layer.shadowColor = UIColor.blackColor.CGColor;
    avatarGlass.layer.shadowOpacity = 0.16;
    avatarGlass.layer.shadowRadius = 6.0;
    avatarGlass.layer.shadowOffset = CGSizeMake(0.0, 3.0);
    // Keep the avatar as a root-view overlay rather than a child of profileView.
    // A subview outside profileView's bounds cannot reliably receive hit-testing;
    // placing it here lets the pan gesture reach and remain interactive at the
    // physical left/right screen edges while its Y position still follows profileView.
    [self.view addSubview:avatarGlass];
    self.customGlassAvatarContainerView = avatarGlass;
    self.customGlassAvatarNormalSize = avatarSize;
    self.customGlassAvatarFocusSize = isPad ? 58.0 : (compactLayout ? 46.0 : 50.0);

    self.customGlassAvatarWidthConstraint = [avatarGlass.widthAnchor constraintEqualToConstant:avatarSize];
    self.customGlassAvatarHeightConstraint = [avatarGlass.heightAnchor constraintEqualToConstant:avatarSize];
    self.customGlassAvatarCenterXConstraint = [avatarGlass.centerXAnchor constraintEqualToAnchor:profileView.centerXAnchor];
    // Focus is an edge tab: anchor the avatar center close to the physical screen
    // edge so part of the circle intentionally peeks offscreen. This is visually
    // quieter over video/Live Photo and removes the previous floating inset.
    CGFloat focusPeekCenter = MAX(8.0, self.customGlassAvatarFocusSize * 0.20);
    self.customGlassAvatarLeadingDockConstraint =
        [avatarGlass.centerXAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:focusPeekCenter];
    self.customGlassAvatarTrailingDockConstraint =
        [avatarGlass.centerXAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-focusPeekCenter];

    [NSLayoutConstraint activateConstraints:@[
        self.customGlassAvatarWidthConstraint,
        self.customGlassAvatarHeightConstraint,
        self.customGlassAvatarCenterXConstraint,
        [avatarGlass.topAnchor constraintEqualToAnchor:profileView.topAnchor]
    ]];

    DOCustomLiquidGlassView *avatarMaterial =
        [[DOCustomLiquidGlassView alloc] initWithCornerRadius:(avatarSize / 2.0) baseTintAlpha:0.03];
    avatarMaterial.translatesAutoresizingMaskIntoConstraints = NO;
    avatarMaterial.userInteractionEnabled = NO;
    avatarMaterial.materialScale = 0.46;
    avatarMaterial.materialBodyScale = 0.34;
    avatarMaterial.materialOpticalScale = 0.52;
    avatarMaterial.materialBackdropScale = 0.34;
    avatarMaterial.materialSpecularScale = 0.54;
    avatarMaterial.materialEdgeDarkScale = 0.42;
    [avatarGlass addSubview:avatarMaterial];
    self.customGlassAvatarMaterialView = avatarMaterial;
    [NSLayoutConstraint activateConstraints:@[
        [avatarMaterial.leadingAnchor constraintEqualToAnchor:avatarGlass.leadingAnchor],
        [avatarMaterial.trailingAnchor constraintEqualToAnchor:avatarGlass.trailingAnchor],
        [avatarMaterial.topAnchor constraintEqualToAnchor:avatarGlass.topAnchor],
        [avatarMaterial.bottomAnchor constraintEqualToAnchor:avatarGlass.bottomAnchor]
    ]];

    UIImageView *avatarImageView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"person.crop.circle.fill"]];
    avatarImageView.translatesAutoresizingMaskIntoConstraints = NO;
    avatarImageView.tintColor = [UIColor colorWithWhite:1.0 alpha:0.92];
    avatarImageView.contentMode = UIViewContentModeScaleAspectFit;
    [avatarGlass addSubview:avatarImageView];
    self.customGlassAvatarFallbackIconView = avatarImageView;
    self.customGlassAvatarIconWidthConstraint = [avatarImageView.widthAnchor constraintEqualToConstant:avatarIconSize];
    self.customGlassAvatarIconHeightConstraint = [avatarImageView.heightAnchor constraintEqualToConstant:avatarIconSize];
    [NSLayoutConstraint activateConstraints:@[
        [avatarImageView.centerXAnchor constraintEqualToAnchor:avatarGlass.centerXAnchor],
        [avatarImageView.centerYAnchor constraintEqualToAnchor:avatarGlass.centerYAnchor],
        self.customGlassAvatarIconWidthConstraint,
        self.customGlassAvatarIconHeightConstraint
    ]];

    self.customGlassAvatarPhotoView = [[UIImageView alloc] init];
    self.customGlassAvatarPhotoView.translatesAutoresizingMaskIntoConstraints = NO;
    self.customGlassAvatarPhotoView.contentMode = UIViewContentModeScaleAspectFill;
    self.customGlassAvatarPhotoView.clipsToBounds = YES;
    self.customGlassAvatarPhotoView.layer.cornerRadius = (avatarSize - 2.0) / 2.0;
    self.customGlassAvatarPhotoView.hidden = YES;
    [avatarGlass addSubview:self.customGlassAvatarPhotoView];

    [NSLayoutConstraint activateConstraints:@[
        [self.customGlassAvatarPhotoView.leadingAnchor constraintEqualToAnchor:avatarGlass.leadingAnchor constant:1.0],
        [self.customGlassAvatarPhotoView.trailingAnchor constraintEqualToAnchor:avatarGlass.trailingAnchor constant:-1.0],
        [self.customGlassAvatarPhotoView.topAnchor constraintEqualToAnchor:avatarGlass.topAnchor constant:1.0],
        [self.customGlassAvatarPhotoView.bottomAnchor constraintEqualToAnchor:avatarGlass.bottomAnchor constant:-1.0]
    ]];

    UIImage *savedAvatar = DOCustomGlassMediaStoreLoadAvatar();
    if (savedAvatar) {
        self.customGlassAvatarPhotoView.image = savedAvatar;
        self.customGlassAvatarPhotoView.hidden = NO;
        self.customGlassAvatarFallbackIconView.hidden = YES;
    }

    avatarGlass.userInteractionEnabled = YES;
    avatarGlass.isAccessibilityElement = YES;
    avatarGlass.accessibilityLabel = @"更换头像";
    [avatarGlass addGestureRecognizer:[[UITapGestureRecognizer alloc]
        initWithTarget:self action:@selector(customGlassAvatarTapped:)]];
    [avatarGlass addGestureRecognizer:[[UIPanGestureRecognizer alloc]
        initWithTarget:self action:@selector(customGlassAvatarPanned:)]];

    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSString *username = [defaults stringForKey:DOCustomGlassUsernameKey];
    if (username.length == 0)
        username = @"RootHide User";
    NSString *motto = [defaults stringForKey:DOCustomGlassMottoKey];
    if (motto.length == 0)
        motto = @"motto";

    UILabel *usernameLabel = [[UILabel alloc] init];
    usernameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    usernameLabel.text = username;
    usernameLabel.textColor = UIColor.whiteColor;
    usernameLabel.textAlignment = NSTextAlignmentCenter;
    usernameLabel.font = [UIFont systemFontOfSize:usernameFontSize weight:UIFontWeightSemibold];
    usernameLabel.userInteractionEnabled = YES;
    usernameLabel.isAccessibilityElement = YES;
    usernameLabel.accessibilityLabel = @"编辑用户名";
    [usernameLabel addGestureRecognizer:[[UITapGestureRecognizer alloc]
        initWithTarget:self action:@selector(presentCustomGlassUsernameEditor)]];
    [profileView addSubview:usernameLabel];
    self.customGlassUsernameLabel = usernameLabel;

    UILabel *systemLabel = [[UILabel alloc] init];
    systemLabel.translatesAutoresizingMaskIntoConstraints = NO;
    systemLabel.text = [NSString stringWithFormat:@"iOS %@", UIDevice.currentDevice.systemVersion];
    systemLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.72];
    systemLabel.textAlignment = NSTextAlignmentCenter;
    systemLabel.font = [UIFont systemFontOfSize:systemFontSize weight:UIFontWeightMedium];
    [profileView addSubview:systemLabel];
    self.customGlassSystemLabel = systemLabel;

    UILabel *mottoLabel = [[UILabel alloc] init];
    mottoLabel.translatesAutoresizingMaskIntoConstraints = NO;
    mottoLabel.text = motto;
    mottoLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.78];
    mottoLabel.textAlignment = NSTextAlignmentCenter;
    mottoLabel.font = [UIFont systemFontOfSize:mottoFontSize weight:UIFontWeightRegular];
    mottoLabel.numberOfLines = 2;
    mottoLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    mottoLabel.userInteractionEnabled = YES;
    mottoLabel.isAccessibilityElement = YES;
    mottoLabel.accessibilityLabel = @"编辑个性签名";
    [mottoLabel addGestureRecognizer:[[UITapGestureRecognizer alloc]
        initWithTarget:self action:@selector(presentCustomGlassMottoEditor)]];
    [profileView addSubview:mottoLabel];
    self.customGlassMottoLabel = mottoLabel;

    NSLayoutConstraint *mottoMaxWidth = [mottoLabel.widthAnchor constraintLessThanOrEqualToAnchor:profileView.widthAnchor multiplier:0.78];
    mottoMaxWidth.priority = UILayoutPriorityRequired;

    [NSLayoutConstraint activateConstraints:@[
        [usernameLabel.topAnchor constraintEqualToAnchor:avatarGlass.bottomAnchor constant:avatarToUsernameSpacing],
        [usernameLabel.leadingAnchor constraintEqualToAnchor:profileView.leadingAnchor constant:12],
        [usernameLabel.trailingAnchor constraintEqualToAnchor:profileView.trailingAnchor constant:-12],
        [systemLabel.topAnchor constraintEqualToAnchor:usernameLabel.bottomAnchor constant:usernameToSystemSpacing],
        [systemLabel.leadingAnchor constraintEqualToAnchor:profileView.leadingAnchor constant:12],
        [systemLabel.trailingAnchor constraintEqualToAnchor:profileView.trailingAnchor constant:-12],
        [mottoLabel.topAnchor constraintEqualToAnchor:systemLabel.bottomAnchor constant:systemToMottoSpacing],
        [mottoLabel.centerXAnchor constraintEqualToAnchor:profileView.centerXAnchor],
        [mottoLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:profileView.leadingAnchor constant:18],
        [mottoLabel.trailingAnchor constraintLessThanOrEqualToAnchor:profileView.trailingAnchor constant:-18],
        [mottoLabel.bottomAnchor constraintEqualToAnchor:profileView.bottomAnchor],
        mottoMaxWidth
    ]];

    UIView *actionGrid = [[UIView alloc] init];
    actionGrid.translatesAutoresizingMaskIntoConstraints = NO;
    [mainStack addArrangedSubview:actionGrid];
    NSLayoutConstraint *gridHeightConstraint = [actionGrid.heightAnchor constraintEqualToConstant:gridHeight];
    gridHeightConstraint.priority = UILayoutPriorityRequired;
    gridHeightConstraint.active = YES;

    UIStackView *leftColumn = [[UIStackView alloc] init];
    leftColumn.axis = UILayoutConstraintAxisVertical;
    leftColumn.alignment = UIStackViewAlignmentFill;
    leftColumn.distribution = UIStackViewDistributionFillEqually;
    leftColumn.spacing = mainSpacing;
    leftColumn.translatesAutoresizingMaskIntoConstraints = NO;
    [actionGrid addSubview:leftColumn];

    UIStackView *rightColumn = [[UIStackView alloc] init];
    rightColumn.axis = UILayoutConstraintAxisVertical;
    rightColumn.alignment = UIStackViewAlignmentFill;
    rightColumn.distribution = UIStackViewDistributionFill;
    rightColumn.spacing = mainSpacing;
    rightColumn.translatesAutoresizingMaskIntoConstraints = NO;
    [actionGrid addSubview:rightColumn];

    [NSLayoutConstraint activateConstraints:@[
        [leftColumn.leadingAnchor constraintEqualToAnchor:actionGrid.leadingAnchor],
        [leftColumn.topAnchor constraintEqualToAnchor:actionGrid.topAnchor],
        [leftColumn.bottomAnchor constraintEqualToAnchor:actionGrid.bottomAnchor],
        [leftColumn.widthAnchor constraintEqualToAnchor:actionGrid.widthAnchor multiplier:leftColumnWidthMultiplier],
        [rightColumn.leadingAnchor constraintEqualToAnchor:leftColumn.trailingAnchor constant:mainSpacing],
        [rightColumn.trailingAnchor constraintEqualToAnchor:actionGrid.trailingAnchor],
        [rightColumn.topAnchor constraintEqualToAnchor:actionGrid.topAnchor],
        [rightColumn.bottomAnchor constraintEqualToAnchor:actionGrid.bottomAnchor]
    ]];

    UIAction *settingsAction = [UIAction actionWithHandler:^(__kindof UIAction * _Nonnull action) {
        [self.navigationController pushViewController:[[DOSettingsController alloc] init] animated:YES];
    }];
    UIAction *creditsAction = [UIAction actionWithHandler:^(__kindof UIAction * _Nonnull action) {
        [self.navigationController pushViewController:[[DOCreditsViewController alloc] init] animated:YES];
    }];

    DOCustomLiquidGlassView *settingsCard = [self customGlassCardWithTitle:DOLocalizedString(@"Menu_Settings_Title") imageName:@"gearshape" action:settingsAction];
    DOCustomLiquidGlassView *creditsCard = [self customGlassCardWithTitle:DOLocalizedString(@"Menu_Credits_Title") imageName:@"info.circle" action:creditsAction];
    [leftColumn addArrangedSubview:settingsCard];
    [leftColumn addArrangedSubview:creditsCard];

    UIAction *themeAction = [UIAction actionWithHandler:^(__kindof UIAction * _Nonnull action) {
        if (![self requireCustomGlassSupporterAuthorization])
            return;

        DOCustomGlassThemeSettingsViewController *themeSettingsController =
            [[DOCustomGlassThemeSettingsViewController alloc] init];
        [themeSettingsController prepareForPresentation];
        [self.navigationController pushViewController:themeSettingsController animated:YES];
    }];
    DOCustomLiquidGlassView *themeCard = [self customGlassCardWithTitle:@"主题设置" imageName:@"slider.horizontal.3" action:themeAction];
    self.customGlassThemeCard = themeCard;
    themeCard.preferredCornerRadius = themeCardHeight / 2.0;
    themeCard.layer.cornerRadius = themeCard.preferredCornerRadius;
    [rightColumn addArrangedSubview:themeCard];
    [themeCard.heightAnchor constraintEqualToConstant:themeCardHeight].active = YES;
    [self refreshCustomGlassButtonState];

    DOCustomLiquidGlassView *restartContainer = [self customGlassViewWithCornerRadius:24 tintAlpha:0.05];
    // Restart Outer is a true Main Glass surface. The three nested actions keep
    // their suppressBackdrop Inset role, so this does not introduce double blur.
    DOCustomGlassApplyMainMaterialProfile(restartContainer);
    [restartContainer reloadMaterial];
    [rightColumn addArrangedSubview:restartContainer];

    UIStackView *restartStack = [[UIStackView alloc] init];
    restartStack.axis = UILayoutConstraintAxisVertical;
    restartStack.alignment = UIStackViewAlignmentFill;
    restartStack.distribution = UIStackViewDistributionFillEqually;
    restartStack.spacing = restartSpacing;
    restartStack.translatesAutoresizingMaskIntoConstraints = NO;
    [restartContainer.contentView addSubview:restartStack];
    [NSLayoutConstraint activateConstraints:@[
        [restartStack.leadingAnchor constraintEqualToAnchor:restartContainer.contentView.leadingAnchor constant:restartPadding],
        [restartStack.trailingAnchor constraintEqualToAnchor:restartContainer.contentView.trailingAnchor constant:-restartPadding],
        [restartStack.topAnchor constraintEqualToAnchor:restartContainer.contentView.topAnchor constant:restartPadding],
        [restartStack.bottomAnchor constraintEqualToAnchor:restartContainer.contentView.bottomAnchor constant:-restartPadding]
    ]];

    BOOL isJailbroken = [[DOEnvironmentManager sharedManager] isJailbroken] || [[DOEnvironmentManager sharedManager] isJailbrokenWithOtherJailbreak];
    BOOL isSupported = [[DOEnvironmentManager sharedManager] isSupported];

    UIAction *respringAction = [UIAction actionWithHandler:^(__kindof UIAction * _Nonnull action) {
        [self fadeToBlack:^{
            [[DOEnvironmentManager sharedManager] respring];
        }];
    }];
    UIAction *userspaceAction = [UIAction actionWithHandler:^(__kindof UIAction * _Nonnull action) {
        [self fadeToBlack:^{
            [[DOEnvironmentManager sharedManager] rebootUserspace];
        }];
    }];
    UIAction *rebootAction = [UIAction actionWithHandler:^(__kindof UIAction * _Nonnull action) {
        UIAlertController *confirmation = [UIAlertController alertControllerWithTitle:DOLocalizedString(@"Menu_Reboot_Device_Title") message:DOLocalizedString(@"Alert_Reboot_Device_Body") preferredStyle:UIAlertControllerStyleAlert];
        [confirmation addAction:[UIAlertAction actionWithTitle:DOLocalizedString(@"Button_Cancel") style:UIAlertActionStyleCancel handler:nil]];
        [confirmation addAction:[UIAlertAction actionWithTitle:DOLocalizedString(@"Button_Reboot") style:UIAlertActionStyleDestructive handler:^(__kindof UIAlertAction * _Nonnull alertAction) {
            [self fadeToBlack:^{
                [[DOEnvironmentManager sharedManager] reboot];
            }];
        }]];
        [self presentViewController:confirmation animated:YES completion:nil];
    }];

    [restartStack addArrangedSubview:[self customGlassRestartButtonWithTitle:DOLocalizedString(@"Menu_Restart_SpringBoard_Title") imageName:@"arrow.clockwise" action:respringAction enabled:isJailbroken cornerRadius:restartCornerRadius]];
    [restartStack addArrangedSubview:[self customGlassRestartButtonWithTitle:DOLocalizedString(@"Menu_Reboot_Userspace_Title") imageName:@"arrow.clockwise.circle" action:userspaceAction enabled:isJailbroken cornerRadius:restartCornerRadius]];
    [restartStack addArrangedSubview:[self customGlassRestartButtonWithTitle:DOLocalizedString(@"Menu_Reboot_Device_Title") imageName:@"power" action:rebootAction enabled:YES cornerRadius:restartCornerRadius]];

    // Keep a dedicated gap for the optional update button. setupUpdateAvailable:
    // positions that button above jailbreakBtn, so without this reserve it can overlap
    // the lower edge of the glass action grid.
    UIView *updateReserve = [[UIView alloc] init];
    updateReserve.translatesAutoresizingMaskIntoConstraints = NO;
    [mainStack addArrangedSubview:updateReserve];
    CGFloat updateReserveHeight = ([DOGlobalAppearance isHomeButtonDevice] ? 42.0 : 52.0) - gridDrop;
    [updateReserve.heightAnchor constraintEqualToConstant:updateReserveHeight].active = YES;

    UIView *buttonPlaceHolder = [[UIView alloc] init];
    buttonPlaceHolder.translatesAutoresizingMaskIntoConstraints = NO;
    [mainStack addArrangedSubview:buttonPlaceHolder];
    [buttonPlaceHolder.heightAnchor constraintEqualToConstant:jailbreakButtonHeight].active = YES;

    NSString *jailbreakButtonTitle = [self jailbreakButtonTitle];
    UIImage *jailbreakButtonImage = isSupported ?
        [UIImage systemImageNamed:@"lock.open" withConfiguration:[DOGlobalAppearance smallIconImageConfiguration]] :
        [UIImage systemImageNamed:@"lock.slash" withConfiguration:[DOGlobalAppearance smallIconImageConfiguration]];

    __block UIColor *jailbreakExpandedBackgroundColor = nil;
    __block DOCustomLiquidGlassView *jailbreakMaterialGlass = nil;

    self.jailbreakBtn = [[DOJailbreakButton alloc] initWithAction:[UIAction actionWithTitle:jailbreakButtonTitle image:jailbreakButtonImage identifier:@"jailbreak" handler:^(__kindof UIAction * _Nonnull action) {
/********************************** roothide specific ************************************/
        if (![self requireCustomGlassSupporterAuthorization])
            return;

        if (otherJailbreakActived(false)) {
            UIAlertController *alertController = [UIAlertController alertControllerWithTitle:DOLocalizedString(@"Error") message:DOLocalizedString(@"Your device currently has another jailbreak activated, please reboot device.") preferredStyle:UIAlertControllerStyleAlert];
            UIAlertAction *closeAction = [UIAlertAction actionWithTitle:DOLocalizedString(@"Button_Close") style:UIAlertActionStyleDefault handler:nil];
            [alertController addAction:closeAction];
            [self presentViewController:alertController animated:YES completion:nil];
            return;
        }
/********************************** roothide specific ************************************/

        actionGrid.userInteractionEnabled = NO;
        self.updateButton.userInteractionEnabled = NO;

        // Hide the compact Glass surface before expansion so the existing
        // jailbreak/progress interface keeps its opaque background.
        jailbreakMaterialGlass.hidden = YES;
        self.jailbreakBtn.backgroundColor = jailbreakExpandedBackgroundColor;
        self.informationVisible = NO;
        [self stopUptimeTimer];
        [(DONavigationController *)self.navigationController customGlassPauseForJailbreak];
        CGRect buttonFrame = [self.jailbreakBtn convertRect:self.jailbreakBtn.bounds toView:self.view];
        [NSLayoutConstraint deactivateConstraints:self.jailbreakButtonConstraints];
        [self.view addSubview:self.jailbreakBtn];
        self.jailbreakButtonConstraints = @[
            [self.jailbreakBtn.leftAnchor constraintEqualToAnchor:self.view.leftAnchor constant:CGRectGetMinX(buttonFrame)],
            [self.jailbreakBtn.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:CGRectGetMinY(buttonFrame)],
            [self.jailbreakBtn.widthAnchor constraintEqualToConstant:CGRectGetWidth(buttonFrame)],
            [self.jailbreakBtn.heightAnchor constraintEqualToConstant:CGRectGetHeight(buttonFrame)]
        ];
        [NSLayoutConstraint activateConstraints:self.jailbreakButtonConstraints];
        [self.jailbreakBtn expandButton:self.jailbreakButtonConstraints];

        [UIView animateWithDuration:0.75 delay:0 usingSpringWithDamping:0.9 initialSpringVelocity:2.0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
            actionGrid.alpha = 0.0;
            actionGrid.transform = CGAffineTransformMakeTranslation(0, 20);
            headerView.transform = CGAffineTransformMakeTranslation(0, -20);
            self.updateButton.alpha = 0.0;
        } completion:nil];

        [self startJailbreak];
    }]];
    self.jailbreakBtn.enabled = DORHSupporterIsVerified() && !isJailbroken && isSupported;

    // DOJailbreakButton dims its whole view to 70% when disabled. When the Glass
    // layer lives inside that view, the disabled "Jailbroken" state therefore
    // fades the blur/body/specular together and no longer matches Main Glass.
    // Keep the material itself at full opacity and dim only the button content;
    [self refreshCustomGlassButtonState];

    // Preserve the original DOJailbreakButton color for expanded/progress mode.
    jailbreakExpandedBackgroundColor = self.jailbreakBtn.backgroundColor;

    // Glass V2.2: CTA uses the same single Liquid Glass material as the surrounding
    // Main surfaces. Directional perimeter optics are now produced by
    // DOCustomLiquidGlassView itself, so no second Metal edge pass is layered above it.
    jailbreakMaterialGlass = [self customGlassViewWithCornerRadius:14.0 tintAlpha:0.05];
    jailbreakMaterialGlass.userInteractionEnabled = NO;
    DOCustomGlassApplyMainMaterialProfile(jailbreakMaterialGlass);
    [jailbreakMaterialGlass reloadMaterial];



    self.jailbreakBtn.backgroundColor = UIColor.clearColor;
    [self.jailbreakBtn insertSubview:jailbreakMaterialGlass atIndex:0];
    [NSLayoutConstraint activateConstraints:@[
        [jailbreakMaterialGlass.leadingAnchor constraintEqualToAnchor:self.jailbreakBtn.leadingAnchor],
        [jailbreakMaterialGlass.trailingAnchor constraintEqualToAnchor:self.jailbreakBtn.trailingAnchor],
        [jailbreakMaterialGlass.topAnchor constraintEqualToAnchor:self.jailbreakBtn.topAnchor],
        [jailbreakMaterialGlass.bottomAnchor constraintEqualToAnchor:self.jailbreakBtn.bottomAnchor]
    ]];

    // Keep an unmistakable disabled state when the package is not authorized.
    // The overlay is visual only; DOJailbreakButton.enabled remains the actual
    // interaction gate and the action performs a second authorization check.
    UIView *disabledOverlay = [[UIView alloc] init];
    disabledOverlay.translatesAutoresizingMaskIntoConstraints = NO;
    disabledOverlay.backgroundColor = [UIColor colorWithWhite:0.18 alpha:0.34];
    disabledOverlay.userInteractionEnabled = NO;
    self.customGlassJailbreakDisabledOverlay = disabledOverlay;
    [self.jailbreakBtn addSubview:disabledOverlay];
    [NSLayoutConstraint activateConstraints:@[
        [disabledOverlay.leadingAnchor constraintEqualToAnchor:self.jailbreakBtn.leadingAnchor],
        [disabledOverlay.trailingAnchor constraintEqualToAnchor:self.jailbreakBtn.trailingAnchor],
        [disabledOverlay.topAnchor constraintEqualToAnchor:self.jailbreakBtn.topAnchor],
        [disabledOverlay.bottomAnchor constraintEqualToAnchor:self.jailbreakBtn.bottomAnchor]
    ]];

    [self.view addSubview:self.jailbreakBtn];

    self.customGlassJailbreakCenterYConstraint =
        [self.jailbreakBtn.centerYAnchor constraintEqualToAnchor:buttonPlaceHolder.centerYAnchor constant:jailbreakVerticalOffset];

    [NSLayoutConstraint activateConstraints:(self.jailbreakButtonConstraints = @[
        [self.jailbreakBtn.leadingAnchor constraintEqualToAnchor:buttonPlaceHolder.leadingAnchor constant:jailbreakHorizontalInset],
        [self.jailbreakBtn.trailingAnchor constraintEqualToAnchor:buttonPlaceHolder.trailingAnchor constant:-jailbreakHorizontalInset],
        [self.jailbreakBtn.heightAnchor constraintEqualToAnchor:buttonPlaceHolder.heightAnchor],
        self.customGlassJailbreakCenterYConstraint
    ])];

    NSUserDefaults *profileDefaults = NSUserDefaults.standardUserDefaults;
    BOOL focusEnabled = [profileDefaults boolForKey:DOCustomGlassProfileFocusEnabledKey];
    BOOL focusDockRight = [profileDefaults objectForKey:DOCustomGlassProfileFocusDockRightKey]
        ? [profileDefaults boolForKey:DOCustomGlassProfileFocusDockRightKey]
        : YES;
    [self setCustomGlassProfileFocusEnabled:focusEnabled
                                  dockRight:focusDockRight
                                   animated:NO
                                    persist:NO];

    [self applyCustomGlassHomeAppearance];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.1 * NSEC_PER_SEC), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        if ([[DOUIManager sharedInstance] environmentUpdateAvailable]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self setupUpdateAvailable:YES];
            });
        }
        else if ([[DOUIManager sharedInstance] isUpdateAvailable]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self setupUpdateAvailable:NO];
            });
        }
    });
}


- (NSString *)jailbreakButtonTitle
{
    BOOL isJailbroken = [[DOEnvironmentManager sharedManager] isJailbroken];
    BOOL isSupported = [[DOEnvironmentManager sharedManager] isSupported];
    BOOL removeJailbreakEnabled = [[DOPreferenceManager sharedManager] boolPreferenceValueForKey:@"removeJailbreakEnabled" fallback:NO];

    NSString *jailbreakButtonTitle = DOLocalizedString(@"Button_Jailbreak_Title");
    if (!isSupported)
        jailbreakButtonTitle = DOLocalizedString(@"Unsupported");
    else if (isJailbroken)
        jailbreakButtonTitle = DOLocalizedString(@"Status_Title_Jailbroken");
    else if (removeJailbreakEnabled)
        jailbreakButtonTitle = DOLocalizedString(@"Button_Remove_Jailbreak");

    return jailbreakButtonTitle;
}

// 读取含休眠时间的系统运行时长，不受修改日期或定时器延迟影响。
- (NSString *)systemUptimeDescription
{
    static mach_timebase_info_data_t timebase;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ mach_timebase_info(&timebase); });
    if (timebase.denom == 0) return DOLocalizedString(@"Unknown");
    NSTimeInterval seconds = (double)mach_continuous_time() * timebase.numer / timebase.denom / NSEC_PER_SEC;
    if (seconds < 60) return DOLocalizedString(@"Uptime_Less_Than_Minute");
    NSDateComponentsFormatter *formatter = [[NSDateComponentsFormatter alloc] init];
    formatter.allowedUnits = NSCalendarUnitDay | NSCalendarUnitHour | NSCalendarUnitMinute;
    formatter.unitsStyle = NSDateComponentsFormatterUnitsStyleFull;
    formatter.zeroFormattingBehavior = NSDateComponentsFormatterZeroFormattingBehaviorDropAll;
    formatter.maximumUnitCount = 3;
    return [formatter stringFromTimeInterval:seconds] ?: DOLocalizedString(@"Unknown");
}

// 每次直接读取系统时钟刷新时长，避免逐秒累加造成误差。
- (void)refreshSystemUptime
{
    self.systemUptimeLabel.text =
        [NSString stringWithFormat:DOLocalizedString(@"Home_Uptime_Format"), [self systemUptimeDescription]];
}

// 仅在主页可见且应用活跃时刷新，分钟显示无需逐秒重绘。
- (void)resumeSystemInformationUpdates
{
    if (!self.informationVisible) return;
    [self refreshSystemUptime];
    if (self.uptimeTimer || UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
    __weak typeof(self) weakSelf = self;
    self.uptimeTimer = [NSTimer timerWithTimeInterval:60 repeats:YES block:^(NSTimer *timer) {
        [weakSelf refreshSystemUptime];
    }];
    mach_timebase_info_data_t timebase;
    mach_timebase_info(&timebase);
    if (timebase.denom != 0) {
        uint64_t seconds = (uint64_t)((double)mach_continuous_time() * timebase.numer / timebase.denom / NSEC_PER_SEC);
        self.uptimeTimer.fireDate = [NSDate dateWithTimeIntervalSinceNow:60 - (seconds % 60)];
    }
    [[NSRunLoop mainRunLoop] addTimer:self.uptimeTimer forMode:NSRunLoopCommonModes];
}

// 离开主页或进入后台时停止无用刷新。
- (void)stopUptimeTimer
{
    [self.uptimeTimer invalidate];
    self.uptimeTimer = nil;
}

// 显示主页时刷新信息及越狱按钮状态。
- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    self.informationVisible = YES;
    [self applyCustomGlassHomeAppearance];
    [self refreshCustomGlassButtonState];
    [self resumeSystemInformationUpdates];
    [self.jailbreakBtn.button setTitle:[self jailbreakButtonTitle] forState:UIControlStateNormal];
}

// 页面隐藏后停止计时，返回时按系统时钟恢复。
- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    self.informationVisible = NO;
    [self stopUptimeTimer];
}

// 释放定时器及通知观察，避免页面退出后继续刷新。
- (void)dealloc
{
    [_uptimeTimer invalidate];
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)startJailbreak
{
    if (![self requireCustomGlassSupporterAuthorization])
        return;

    DOJailbreaker *jailbreaker = [[DOJailbreaker alloc] init];

    [[DOUIManager sharedInstance] startLogCapture];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        if ([jailbreaker contiguousMappingWorkaroundNeeded]) {

            NSString *workaroundMessage = DOLocalizedString(@"Respring_Required_Message");

            UIAlertController *contiguousMappingWorkaroundAlertController = [UIAlertController alertControllerWithTitle:DOLocalizedString(@"Respring_Required") message:workaroundMessage preferredStyle:UIAlertControllerStyleAlert];

            UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:DOLocalizedString(@"Respring_Cancel") style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
                exit(0);
            }];

            UIAlertAction *workaroundAction = [UIAlertAction actionWithTitle:DOLocalizedString(@"Apply_Workaround") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                [jailbreaker applyContiguousMappingWorkaround];
            }];

            [contiguousMappingWorkaroundAlertController addAction:cancelAction];
            [contiguousMappingWorkaroundAlertController addAction:workaroundAction];
            contiguousMappingWorkaroundAlertController.preferredAction = workaroundAction;

            dispatch_async(dispatch_get_main_queue(), ^{
                [self presentViewController:contiguousMappingWorkaroundAlertController animated:YES completion:nil];
            });
            return;
        }

        //We need to get the preconfig mutex to start the jailbreak (self.jailbreakBtn.canStartJailbreak)
        [self.jailbreakBtn lockMutex];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.hideHomeIndicator = YES;
        });

        NSError *error;
        BOOL didRemove = NO;
        BOOL showLogs = YES;
        [jailbreaker runWithError:&error didRemoveJailbreak:&didRemove showLogs:&showLogs];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error && showLogs) {
                [[DOUIManager sharedInstance] sendLog:[NSString stringWithFormat:@"Jailbreak failed with error: %@", error] debug:NO];
                [self.navigationController pushViewController:[[DOLogCrashViewController alloc] initWithTitle:[error localizedDescription]] animated:YES];
            }
            else if (error && !showLogs) {
                // Used when there is an error that is explainable in such detail that additional logs are not needed
                UIAlertController *alertController = [UIAlertController alertControllerWithTitle:DOLocalizedString(@"Log_Error") message:[error localizedDescription] preferredStyle:UIAlertControllerStyleAlert];
                UIAlertAction *rebootAction = [UIAlertAction actionWithTitle:DOLocalizedString(@"Button_Reboot") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                    exec_cmd_trusted(JBROOT_PATH("/sbin/reboot"), NULL);
                }];
                [alertController addAction:rebootAction];
                [self presentViewController:alertController animated:YES completion:nil];
            }
            else if (didRemove) {
                UIAlertController *alertController = [UIAlertController alertControllerWithTitle:DOLocalizedString(@"Removed_Jailbreak_Alert_Title") message:DOLocalizedString(@"Removed_Jailbreak_Alert_Message") preferredStyle:UIAlertControllerStyleAlert];
                UIAlertAction *rebootAction = [UIAlertAction actionWithTitle:DOLocalizedString(@"Button_Close") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                    exit(0);
                }];
                [alertController addAction:rebootAction];
                [self presentViewController:alertController animated:YES completion:nil];
            }
            else {
                // No errors
                [[DOUIManager sharedInstance] completeJailbreak];
                [self fadeToBlack: ^{
                    [jailbreaker finalize];
                }];
            }
        });
        [self.jailbreakBtn unlockMutex];
    });
}

-(void)setupUpdateAvailable:(BOOL)environmentUpdate
{
    if (self.jailbreakBtn.didExpand)
        return;

    NSString *title = environmentUpdate ? DOLocalizedString(@"Button_Update_Environment") : DOLocalizedString(@"Button_Update_Available");

    NSString *releaseFrom = [[DOUIManager sharedInstance] getLaunchedReleaseTag];
    NSString *releaseTo = [[DOUIManager sharedInstance] getLatestReleaseTag];

    if (environmentUpdate)
    {
/************************************* roothide specfic ***********************************/
        releaseFrom = [[DOEnvironmentManager sharedManager] jailbrokenVersionRootHide];
/************************************* roothide specfic ***********************************/
        releaseTo = [[DOUIManager sharedInstance] getLaunchedReleaseTag];
    }

    self.updateButton = [DOActionMenuButton buttonWithAction:[UIAction actionWithTitle:title image:[UIImage systemImageNamed:@"arrow.down.circle" withConfiguration:[DOGlobalAppearance smallIconImageConfiguration]] identifier:@"update-available" handler:^(__kindof UIAction * _Nonnull action) {
        [self.navigationController pushViewController:[[DOUpdateViewController alloc] initFromTag:releaseFrom toTag:releaseTo] animated:YES];
    }] chevron:NO];

    self.updateButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.updateButton];

    // 为更新入口预留间距，随内容一起参与小屏布局。
    // The glass home already reserves space above the jailbreak button.

    [NSLayoutConstraint activateConstraints:@[
        [self.updateButton.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.updateButton.heightAnchor constraintEqualToConstant:30],
        [self.updateButton.bottomAnchor constraintEqualToAnchor:self.jailbreakBtn.topAnchor constant:-12]
    ]];

    [self.updateButton setTransform:CGAffineTransformMakeTranslation(0, 25)];
    [self.updateButton setAlpha:0];
    [UIView animateWithDuration:0.5 delay:0 usingSpringWithDamping:0.9 initialSpringVelocity:2.0  options: UIViewAnimationOptionCurveEaseInOut animations:^{
        [self.updateButton setTransform:CGAffineTransformIdentity];
        [self.updateButton setAlpha:1];
    } completion:nil];
}

-(void)simulateJailbreak
{
    // Let's simulate a "jailbreak" using grand central dispatch

    DOUIManager *uiManager = [DOUIManager sharedInstance];

    static BOOL didFinish = NO; //not thread safe lol


    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [uiManager completeJailbreak];
        [uiManager sendLog:@"Rebooting Userspace" debug: NO];
        didFinish = YES;
        [self fadeToBlack: ^{

        }];
    });

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [NSThread sleepForTimeInterval:0.2];
        [uiManager sendLog:@"Launching kexploitd" debug: NO];
        [NSThread sleepForTimeInterval:0.5];
        [uiManager sendLog:@"Launching oobPCI" debug: NO];
        [NSThread sleepForTimeInterval:0.15];
        [uiManager sendLog:@"Gaining r/w" debug: NO];
        [NSThread sleepForTimeInterval:0.8];
        [uiManager sendLog:@"Patchfinding" debug: NO];
        NSArray *types = @[@"AMFI", @"PAC", @"KTRR", @"KPP", @"PPL", @"KPF", @"APRR", @"AMCC", @"PAN", @"PXN", @"ASLR", @"OPA"]; //Ever heard of the legendary opa bypass
        while (true)
        {
            [NSThread sleepForTimeInterval:0.6 * rand() / RAND_MAX];
            if (didFinish) break;
            NSString *type = types[arc4random_uniform((uint32_t)types.count)];
            [uiManager sendLog:[NSString stringWithFormat:@"Bypassing %@", type] debug: NO];
        }
    });
}

- (void)fadeToBlack:(void (^)(void))completion
{
    static bool didFade = false;
    if (didFade)
        return;
    didFade = true;
    UIView *mainView = self.parentViewController.view;
    float deviceCornerRadius = [[[UIScreen mainScreen] valueForKey:@"_displayCornerRadius"] floatValue];

    mainView.layer.cornerRadius = deviceCornerRadius;
    mainView.layer.cornerCurve = kCACornerCurveContinuous;
    mainView.layer.masksToBounds = YES;

    self.hideStatusBar = YES;

    [UIView animateWithDuration:0.5 delay:0 usingSpringWithDamping:0.9 initialSpringVelocity:2.0 options: UIViewAnimationOptionCurveEaseInOut animations:^{
        mainView.transform = CGAffineTransformMakeScale(0.9, 0.9);
        mainView.alpha = 0.0;
    } completion:^(BOOL success) {
        completion();
    }];
}

#pragma mark - Action Menu Delegate

- (BOOL)actionMenuShowsChevronForAction:(UIAction *)action
{
    if ([action.identifier isEqualToString:@"settings"] || [action.identifier isEqualToString:@"credits"]) return YES;
    return NO;
}

- (BOOL)actionMenuActionIsEnabled:(UIAction *)action
{
    if ([action.identifier isEqualToString:@"respring"] || [action.identifier isEqualToString:@"reboot-userspace"]) {
        return [[DOEnvironmentManager sharedManager] isJailbroken];
    }
    return YES;
}

#pragma mark - Status Bar

- (UIStatusBarStyle)preferredStatusBarStyle
{
    return UIStatusBarStyleLightContent;
}

- (BOOL)prefersStatusBarHidden
{
    return self.hideStatusBar;
}

- (BOOL)prefersHomeIndicatorAutoHidden
{
    return self.hideHomeIndicator;
}

- (void)setHideStatusBar:(BOOL)hideStatusBar
{
    _hideStatusBar = hideStatusBar;
    [self setNeedsStatusBarAppearanceUpdate];
}

- (void)setHideHomeIndicator:(BOOL)hideHomeIndicator
{
    _hideHomeIndicator = hideHomeIndicator;
    [self setNeedsUpdateOfHomeIndicatorAutoHidden];
}

@end
