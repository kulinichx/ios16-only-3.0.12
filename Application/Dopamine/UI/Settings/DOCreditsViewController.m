//
//  DOCreditsViewController.m
//  Dopamine
//
//  Created by tomt000 on 08/01/2024.
//

#import "DOCreditsViewController.h"
#import "DOLicenseViewController.h"
#import "DOUIManager.h"
#import "DOEnvironmentManager.h"
#import <Preferences/PSSpecifier.h>

@interface DOCreditsViewController ()

@property(nonatomic, strong) UIButton *backButton;

@end

@implementation DOCreditsViewController

- (void)viewDidLoad
{
    [super viewDidLoad];

    // The shared navigation bar is hidden, so Credits needs its own return
    // control outside the scrolling table, just like Settings.
    UIButton *backButton = [UIButton buttonWithType:UIButtonTypeSystem];
    backButton.translatesAutoresizingMaskIntoConstraints = NO;
    backButton.tintColor = UIColor.whiteColor;
    backButton.accessibilityLabel = DOLocalizedString(@"Button_Back");
    UIImageSymbolConfiguration *configuration =
        [UIImageSymbolConfiguration configurationWithPointSize:22.0 weight:UIImageSymbolWeightMedium];
    [backButton setImage:[UIImage systemImageNamed:@"chevron.left" withConfiguration:configuration]
               forState:UIControlStateNormal];
    [backButton addTarget:self action:@selector(backPressed)
        forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:backButton];
    self.backButton = backButton;
    [NSLayoutConstraint activateConstraints:@[
        [backButton.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:10.0],
        [backButton.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:6.0],
        [backButton.widthAnchor constraintEqualToConstant:44.0],
        [backButton.heightAnchor constraintEqualToConstant:44.0]
    ]];
    _table.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;

    UIScreenEdgePanGestureRecognizer *edgeGesture =
        [[UIScreenEdgePanGestureRecognizer alloc] initWithTarget:self action:@selector(edgeBackGesture:)];
    edgeGesture.edges = UIRectEdgeLeft;
    [self.view addGestureRecognizer:edgeGesture];
    [_table.panGestureRecognizer requireGestureRecognizerToFail:edgeGesture];
}

- (void)backPressed
{
    if (self.navigationController.topViewController == self)
        [self.navigationController popViewControllerAnimated:YES];
}

- (void)edgeBackGesture:(UIScreenEdgePanGestureRecognizer *)gesture
{
    if (gesture.state != UIGestureRecognizerStateEnded)
        return;
    CGPoint translation = [gesture translationInView:self.view];
    CGPoint velocity = [gesture velocityInView:self.view];
    if (translation.x > 60.0 && velocity.x >= 0.0)
        [self backPressed];
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    UIEdgeInsets safeArea = self.view.safeAreaInsets;
    CGFloat top = safeArea.top + 56.0;
    _table.frame = CGRectMake(safeArea.left + 12.0, top,
                             MAX(0.0, CGRectGetWidth(self.view.bounds) - safeArea.left - safeArea.right - 24.0),
                             MAX(0.0, CGRectGetHeight(self.view.bounds) - top - safeArea.bottom - 5.0));
    if (self.backButton)
        [self.view bringSubviewToFront:self.backButton];
}

- (id)specifiers
{
    if(_specifiers == nil) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Credits" target:self];

        PSSpecifier *headerSpecifier = _specifiers[0];
        [headerSpecifier setProperty:[NSString stringWithFormat:@"Dopamine %@ - %@", [DOEnvironmentManager sharedManager].appVersionDisplayString, DOLocalizedString(@"Menu_Credits_Title")] forKey:@"title"];
    }
    return _specifiers;
}

- (void)openSourceCode
{
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://github.com/roothide/Dopamine-roothide"] options:@{} completionHandler:nil];
}

- (void)openDiscord
{
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://discord.gg/jb"] options:@{} completionHandler:nil];
}

- (void)openLicense
{
    [self.navigationController pushViewController:[[DOLicenseViewController alloc] init] animated:YES];
}

@end
