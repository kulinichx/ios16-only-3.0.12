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
#import "DOCustomGlassView.h"
#import <Preferences/PSSpecifier.h>

@interface DOCreditsViewController ()

@property(nonatomic, strong) UIButton *backButton;
@property(nonatomic, strong) DOCustomLiquidGlassView *customGlassPageBackdrop;

@end

@implementation DOCreditsViewController

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.view.backgroundColor = UIColor.clearColor;
    self.view.layer.cornerRadius = 0.0;
    self.view.layer.masksToBounds = NO;
    _table.backgroundColor = UIColor.clearColor;
    _table.opaque = NO;
    _table.backgroundView = nil;
    _table.separatorStyle = UITableViewCellSeparatorStyleNone;

    DOCustomLiquidGlassView *pageBackdrop =
        [[DOCustomLiquidGlassView alloc] initWithCornerRadius:24.0 baseTintAlpha:0.044];
    pageBackdrop.materialScale = 0.94;
    pageBackdrop.userInteractionEnabled = NO;
    self.customGlassPageBackdrop = pageBackdrop;
    [_table insertSubview:pageBackdrop atIndex:0];
    [pageBackdrop reloadMaterial];

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

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(customGlassThemeDidChange:)
                                                 name:DOCustomGlassThemeDidChangeNotification
                                               object:nil];
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
    CGFloat availableWidth = MAX(0.0, CGRectGetWidth(self.view.bounds) - safeArea.left - safeArea.right);
    CGFloat width = MAX(0.0, MIN(620.0, availableWidth - 24.0));
    CGFloat top = safeArea.top + 56.0;
    _table.frame = CGRectMake(safeArea.left + (availableWidth - width) * 0.5, top, width,
                             MAX(0.0, CGRectGetHeight(self.view.bounds) - top - safeArea.bottom - 5.0));
    [self customGlassRefreshPageAppearance];
    if (self.backButton)
        [self.view bringSubviewToFront:self.backButton];
}

- (void)customGlassStyleContent:(UIView *)view
{
    if (!view)
        return;

    if ([view isKindOfClass:UILabel.class]) {
        UILabel *label = (UILabel *)view;
        label.textColor = [UIColor.labelColor colorWithAlphaComponent:0.96];
        label.shadowColor = [UIColor colorWithWhite:0.0 alpha:0.14];
        label.shadowOffset = CGSizeMake(0.0, 0.35);
    }
    else if ([view isKindOfClass:UIButton.class]) {
        UIButton *button = (UIButton *)view;
        button.backgroundColor = UIColor.clearColor;
        button.layer.borderWidth = 0.0;
        button.layer.shadowOpacity = 0.0;
        button.tintColor = UIColor.whiteColor;
        if (button.configuration) {
            UIButtonConfiguration *configuration = [button.configuration copy];
            configuration.baseForegroundColor = UIColor.whiteColor;
            button.configuration = configuration;
        }
        [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    }
    else if ([view isKindOfClass:UIImageView.class]) {
        UIImageView *imageView = (UIImageView *)view;
        if (imageView.image.renderingMode == UIImageRenderingModeAlwaysTemplate)
            imageView.tintColor = UIColor.whiteColor;
    }
    else if ([view isKindOfClass:UITableViewHeaderFooterView.class]) {
        UITableViewHeaderFooterView *header = (UITableViewHeaderFooterView *)view;
        header.backgroundView = nil;
        header.contentView.backgroundColor = UIColor.clearColor;
    }

    if ([view isKindOfClass:UITableViewCell.class]) {
        UITableViewCell *cell = (UITableViewCell *)view;
        cell.backgroundColor = UIColor.clearColor;
        cell.contentView.backgroundColor = UIColor.clearColor;
        cell.backgroundView = nil;
        cell.layer.borderWidth = 0.0;
    }

    for (UIView *subview in view.subviews) {
        BOOL hairline = subview.class == UIView.class &&
            CGRectGetHeight(subview.bounds) > 0.0 &&
            CGRectGetHeight(subview.bounds) <= 2.0 &&
            CGRectGetWidth(subview.bounds) >= 40.0;
        if (hairline)
            subview.hidden = YES;
        [self customGlassStyleContent:subview];
    }
}

- (void)customGlassRefreshPageBackdrop
{
    if (!self.customGlassPageBackdrop || CGRectIsEmpty(_table.frame))
        return;

    if (_table.numberOfSections <= 0 || [_table numberOfRowsInSection:0] <= 0) {
        self.customGlassPageBackdrop.hidden = YES;
        return;
    }

    CGRect sectionRect = [_table rectForSection:0];
    if (CGRectIsEmpty(sectionRect)) {
        self.customGlassPageBackdrop.hidden = YES;
        return;
    }

    self.customGlassPageBackdrop.hidden = NO;
    self.customGlassPageBackdrop.frame = sectionRect;
    [_table sendSubviewToBack:self.customGlassPageBackdrop];
}

- (void)customGlassRefreshPageAppearance
{
    [self customGlassRefreshPageBackdrop];
    for (UITableViewCell *cell in _table.visibleCells)
        [self customGlassStyleContent:cell];
    for (NSInteger section = 0; section < _table.numberOfSections; section++) {
        [self customGlassStyleContent:[_table headerViewForSection:section]];
        [self customGlassStyleContent:[_table footerViewForSection:section]];
    }
}

- (void)customGlassThemeDidChange:(NSNotification *)notification
{
    if (!NSThread.isMainThread) {
        __weak typeof(self) weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf customGlassThemeDidChange:notification];
        });
        return;
    }
    [self.customGlassPageBackdrop reloadMaterial];
    [self customGlassRefreshPageAppearance];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self.view setNeedsLayout];
    [self customGlassThemeDidChange:nil];
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath
{
    [super tableView:tableView willDisplayCell:cell forRowAtIndexPath:indexPath];
    [self customGlassStyleContent:cell];
    __weak typeof(self) weakSelf = self;
    __weak UITableViewCell *weakCell = cell;
    dispatch_async(dispatch_get_main_queue(), ^{
        UITableViewCell *visibleCell = weakCell;
        if (visibleCell.window && [tableView indexPathForCell:visibleCell])
            [weakSelf customGlassStyleContent:visibleCell];
        [weakSelf customGlassRefreshPageBackdrop];
    });
}

- (void)tableView:(UITableView *)tableView willDisplayHeaderView:(UIView *)view forSection:(NSInteger)section
{
    [self customGlassStyleContent:view];
    [self customGlassRefreshPageBackdrop];
}

- (void)tableView:(UITableView *)tableView willDisplayFooterView:(UIView *)view forSection:(NSInteger)section
{
    [self customGlassStyleContent:view];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:DOCustomGlassThemeDidChangeNotification
                                                  object:nil];
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
