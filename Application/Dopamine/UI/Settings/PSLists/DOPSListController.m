//
//  DOPSListController.m
//  Dopamine
//
//  Created by tomt000 on 26/01/2024.
//

#import "DOPSListController.h"
#import "DOThemeManager.h"
#import <QuartzCore/QuartzCore.h>

@interface DOPSListController ()

@property(nonatomic, strong) CALayer *preferencesTableMask;
@property(nonatomic) BOOL preferencesTableInsetsInitialized;

@end

@implementation DOPSListController

- (void)viewDidLoad {
    [super viewDidLoad];

    [_table setSeparatorColor:[UIColor clearColor]];
    [_table setBackgroundColor:[UIColor clearColor]];
    [DOPSListController setupViewControllerStyle:self];
}

+ (void)setupViewControllerStyle:(UIViewController*)vc
{
    DOTheme *theme = [[DOThemeManager sharedInstance] enabledTheme];

    vc.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    vc.view.backgroundColor = theme.windowColor;
    vc.view.layer.cornerRadius = 16;
    vc.view.layer.masksToBounds = YES;
    vc.view.layer.cornerCurve = kCACornerCurveContinuous;

    [UISwitch appearanceWhenContainedInInstancesOfClasses:@[[vc class]]].onTintColor = [UIColor colorWithRed: 71.0/255.0 green: 169.0/255.0 blue: 135.0/255.0 alpha: 1.0];
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    cell.backgroundColor = [UIColor clearColor];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if ([self preferencesUsesNativeTableLayout]) {
        [self updatePreferencesTableInsets];
        [self updatePreferencesTableMask];
        return;
    }
    CGRect frame = CGRectMake(12, 5, self.view.bounds.size.width - 24, self.view.bounds.size.height - 10);
    if (!CGRectEqualToRect(_table.frame, frame))
        _table.frame = frame;
}

- (BOOL)preferencesUsesNativeTableLayout
{
    return NO;
}

- (void)updatePreferencesTableInsets
{
    if (CGRectIsEmpty(_table.bounds))
        return;

    UIEdgeInsets safeArea = self.view.safeAreaInsets;
    CGRect viewport = [_table convertRect:_table.bounds toView:self.view];
    UIEdgeInsets insets = UIEdgeInsetsMake(
        MAX(0.0, safeArea.top + 56.0 - CGRectGetMinY(viewport)), 0.0,
        MAX(0.0, CGRectGetMaxY(viewport) - (CGRectGetHeight(self.view.bounds) - safeArea.bottom - 5.0)), 0.0);
    BOOL firstLayout = !self.preferencesTableInsetsInitialized;
    BOOL insetsChanged = !UIEdgeInsetsEqualToEdgeInsets(_table.contentInset, insets);
    BOOL restingAtTop = !_table.dragging && !_table.tracking && !_table.decelerating &&
        _table.contentOffset.y <= -_table.contentInset.top + 0.5;
    self.preferencesTableInsetsInitialized = YES;
    if (insetsChanged)
        _table.contentInset = insets;
    if (!UIEdgeInsetsEqualToEdgeInsets(_table.scrollIndicatorInsets, insets))
        _table.scrollIndicatorInsets = insets;
    // Only initialize the top position or preserve it across a safe-area change.
    // Ordinary layout/scroll callbacks never reset the user's scroll position.
    if ((firstLayout || (insetsChanged && restingAtTop)) &&
        !_table.dragging && !_table.tracking && !_table.decelerating) {
        CGPoint offset = CGPointMake(_table.contentOffset.x, -insets.top);
        if (!CGPointEqualToPoint(_table.contentOffset, offset))
            [_table setContentOffset:offset animated:NO];
    }
}

- (void)updatePreferencesTableMask
{
    if (![self preferencesUsesNativeTableLayout])
        return;
    // Clip content below the fixed back row without changing scroll geometry.
    // UIScrollView changes bounds.origin while scrolling, so the mask follows it.
    CGRect bounds = _table.bounds;
    UIEdgeInsets insets = _table.contentInset;
    CGRect frame = CGRectMake(CGRectGetMinX(bounds), CGRectGetMinY(bounds) + insets.top,
                              CGRectGetWidth(bounds), MAX(0.0, CGRectGetHeight(bounds) - insets.top - insets.bottom));
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    if (!self.preferencesTableMask) {
        self.preferencesTableMask = [CALayer layer];
        self.preferencesTableMask.backgroundColor = UIColor.blackColor.CGColor;
        _table.layer.mask = self.preferencesTableMask;
    }
    if (!CGRectEqualToRect(self.preferencesTableMask.frame, frame))
        self.preferencesTableMask.frame = frame;
    [CATransaction commit];
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView
{
    if ([PSListController instancesRespondToSelector:_cmd])
        [super scrollViewDidScroll:scrollView];
    if (scrollView == _table)
        [self updatePreferencesTableMask];
}

#pragma mark - Status Bar

- (UIStatusBarStyle)preferredStatusBarStyle
{
    return UIStatusBarStyleLightContent;
}

@end
