#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

// The real Preferences framework is unavailable in the simulator. This parent
// supplies rows and deliberately reapplies its native frame on every layout.
// The material and all geometry/scroll callbacks below come from production.
/* PRODUCTION_MATERIAL_HEADER */
static BOOL DORHSupporterRenderIsVerified(void) { return YES; }
/* PRODUCTION_MATERIAL */

#define CHECK(condition) do { if (!(condition)) @throw [NSException exceptionWithName:@"LayoutFailure" reason:@#condition userInfo:nil]; } while (0)

@interface CountingTable : UITableView
@property(nonatomic) NSUInteger frameChanges;
@end
@implementation CountingTable
- (void)setFrame:(CGRect)frame
{
    if (!CGRectEqualToRect(self.frame, frame))
        self.frameChanges++;
    [super setFrame:frame];
}
@end

@interface PSListController : UIViewController <UITableViewDelegate, UITableViewDataSource> {
@public CountingTable *_table;
}
@end
@implementation PSListController
- (void)viewDidLoad
{
    [super viewDidLoad];
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(24, 24)];
    UIImage *pattern = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [[UIColor colorWithWhite:0.06 alpha:1.0] setFill];
        UIRectFill(CGRectMake(0, 0, 24, 24));
        [[UIColor colorWithWhite:0.25 alpha:1.0] setFill];
        UIRectFill(CGRectMake(0, 0, 12, 12));
        UIRectFill(CGRectMake(12, 12, 12, 12));
    }];
    self.view.backgroundColor = [UIColor colorWithPatternImage:pattern];
    _table = [[CountingTable alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    _table.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _table.backgroundColor = UIColor.clearColor;
    _table.opaque = NO;
    _table.delegate = self;
    _table.dataSource = self;
    _table.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    _table.estimatedRowHeight = 0.0;
    _table.estimatedSectionHeaderHeight = 0.0;
    _table.estimatedSectionFooterHeight = 0.0;
    [self.view addSubview:_table];
}
- (void)viewDidLayoutSubviews { [super viewDidLayoutSubviews]; _table.frame = self.view.bounds; }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 3; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return section == 0 ? 3 : 16; }
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath { return 44.0; }
- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section { return section == 0 ? 60.0 : 30.0; }
- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section { return 12.0; }
- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section
{
    UILabel *label = [UILabel new];
    label.text = section == 0 ? @"Dopamine - layout verification" : @"DEVELOPERS";
    label.textAlignment = NSTextAlignmentCenter;
    label.textColor = UIColor.whiteColor;
    return label;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"row"];
    if (!cell)
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"row"];
    cell.backgroundColor = UIColor.clearColor;
    cell.contentView.backgroundColor = UIColor.clearColor;
    cell.textLabel.textColor = UIColor.whiteColor;
    cell.textLabel.text = @"Sharp text 0123456789";
    cell.accessoryView = [[UISwitch alloc] initWithFrame:CGRectZero];
    ((UISwitch *)cell.accessoryView).on = YES;
    return cell;
}
@end

@interface DOPSListController : PSListController
@property(nonatomic, strong) CALayer *preferencesTableMask;
@property(nonatomic) BOOL preferencesTableInsetsInitialized;
- (BOOL)preferencesUsesNativeTableLayout;
- (void)updatePreferencesTableInsets;
- (void)updatePreferencesTableMask;
@end
@implementation DOPSListController
/* PRODUCTION_BASE */
@end

@interface SettingsHarness : DOPSListController
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, DOCustomLiquidGlassView *> *customGlassSectionBackdrops;
- (void)customGlassRefreshSectionBackdrops;
@end
@implementation SettingsHarness
- (void)viewDidLoad
{
    [super viewDidLoad];
    /* PRODUCTION_SETTINGS_BACKGROUND */
    self.customGlassSectionBackdrops = [NSMutableDictionary dictionary];
}
/* PRODUCTION_SETTINGS_REFRESH */
/* PRODUCTION_SETTINGS_LAYOUT */
@end

@interface CreditsHarness : DOPSListController
@property(nonatomic, strong) DOCustomLiquidGlassView *customGlassPageBackdrop;
- (void)customGlassRefreshPageBackdrop;
@end
@implementation CreditsHarness
- (void)viewDidLoad
{
    [super viewDidLoad];
    /* PRODUCTION_CREDITS_BACKGROUND */
}
/* PRODUCTION_CREDITS_REFRESH */
/* PRODUCTION_CREDITS_LAYOUT */
@end

static NSArray<DOCustomLiquidGlassView *> *Glasses(DOPSListController *page)
{
    if ([page isKindOfClass:SettingsHarness.class])
        return ((SettingsHarness *)page).customGlassSectionBackdrops.allValues;
    return @[((CreditsHarness *)page).customGlassPageBackdrop];
}

static void CheckLayers(DOPSListController *page)
{
    UITableView *table = page->_table;
    for (DOCustomLiquidGlassView *glass in Glasses(page)) {
        CHECK(glass.superview == table.backgroundView);
        for (UITableViewCell *cell in table.visibleCells) {
            // Compare the first branches below the common ancestor, including
            // UIKit's actual internal wrapper views rather than assuming names.
            UIView *common = cell.superview;
            while (common && ![glass isDescendantOfView:common])
                common = common.superview;
            CHECK(common != nil);
            UIView *back = glass;
            UIView *front = cell;
            while (back.superview != common) back = back.superview;
            while (front.superview != common) front = front.superview;
            CHECK([common.subviews indexOfObject:back] < [common.subviews indexOfObject:front]);
            CHECK(back.layer.zPosition <= front.layer.zPosition);
        }
    }
    CGRect mask = table.layer.mask.frame;
    CHECK(fabs(CGRectGetMinY(mask) - CGRectGetMinY(table.bounds) - table.contentInset.top) < 0.5);
}

static void CheckGlassAlignment(DOPSListController *page)
{
    UITableView *table = page->_table;
    if ([page isKindOfClass:SettingsHarness.class]) {
        SettingsHarness *settings = (SettingsHarness *)page;
        for (NSNumber *key in settings.customGlassSectionBackdrops) {
            NSInteger s = key.integerValue;
            CGRect first = [table rectForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:s]];
            CGRect last = [table rectForRowAtIndexPath:[NSIndexPath indexPathForRow:[table numberOfRowsInSection:s] - 1 inSection:s]];
            CGRect expected = [table convertRect:CGRectInset(CGRectUnion(first, last), 1.0, 0.5) toView:table.backgroundView];
            CHECK(CGRectEqualToRect(expected, settings.customGlassSectionBackdrops[key].frame));
        }
    }
    else {
        CGRect section = [table rectForSection:0];
        CGRect row = [table rectForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
        section.origin.x = row.origin.x;
        section.size.width = row.size.width;
        CGRect expected = [table convertRect:section toView:table.backgroundView];
        CHECK(CGRectEqualToRect(expected, ((CreditsHarness *)page).customGlassPageBackdrop.frame));
    }
}

static void Layout(DOPSListController *page)
{
    [page.view setNeedsLayout];
    [page.view layoutIfNeeded];
    [page->_table layoutIfNeeded];
    [page viewDidLayoutSubviews];
}

static void Snapshot(DOPSListController *page, NSString *name, NSString *documents)
{
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:page.view.bounds.size];
    UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [page.view drawViewHierarchyInRect:page.view.bounds afterScreenUpdates:YES];
    }];
    CHECK([UIImagePNGRepresentation(image) writeToFile:[documents stringByAppendingPathComponent:name] atomically:YES]);
}

static NSDictionary *RunChecks(UIViewController *host, NSString *documents)
{
    NSUInteger checks = 0, viewports = 0;
    NSArray<NSValue *> *sizes = @[
        [NSValue valueWithCGSize:CGSizeMake(744, 1133)], [NSValue valueWithCGSize:CGSizeMake(1133, 744)],
        [NSValue valueWithCGSize:CGSizeMake(834, 1194)], [NSValue valueWithCGSize:CGSizeMake(1194, 834)],
        [NSValue valueWithCGSize:CGSizeMake(393, 852)], [NSValue valueWithCGSize:CGSizeMake(852, 393)]
    ];
    for (Class pageClass in @[SettingsHarness.class, CreditsHarness.class]) {
        DOPSListController *page = [pageClass new];
        [host addChildViewController:page];
        [host.view addSubview:page.view];
        [page didMoveToParentViewController:host];
        for (NSValue *value in sizes) {
            page.view.frame = (CGRect){CGPointZero, value.CGSizeValue};
            Layout(page);
            UITableView *table = page->_table;
            CHECK(CGRectEqualToRect(table.frame, page.view.bounds));
            NSUInteger changes = page->_table.frameChanges;
            CGFloat minimum = -table.contentInset.top;
            CGFloat maximum = MAX(minimum, table.contentSize.height - table.bounds.size.height + table.contentInset.bottom);
            for (NSUInteger i = 0; i < 200; i++) {
                CGPoint requested = CGPointMake(0.0, minimum + (maximum - minimum) * (i % 51) / 50.0);
                [table setContentOffset:requested animated:NO];
                Layout(page);
                CHECK(fabs(table.contentOffset.y - requested.y) < 0.5);
                CHECK(page->_table.frameChanges == changes);
                CheckLayers(page);
                CheckGlassAlignment(page);
                checks++;
            }
            // A reload inserts/reuses UIKit content containers; the background
            // must still stay beneath their text and controls afterwards.
            [table reloadData];
            Layout(page);
            CheckLayers(page);
            CheckGlassAlignment(page);
            [table setContentOffset:CGPointMake(0, minimum) animated:NO];
            Layout(page);
            if (viewports % 6 < 2) {
                NSString *name = [NSString stringWithFormat:@"%@-%@.png", pageClass == SettingsHarness.class ? @"settings" : @"credits",
                    value.CGSizeValue.width < value.CGSizeValue.height ? @"portrait" : @"landscape"];
                Snapshot(page, name, documents);
            }
            viewports++;
        }
        [page willMoveToParentViewController:nil];
        [page.view removeFromSuperview];
        [page removeFromParentViewController];
    }
    return @{@"status": @"passed", @"viewports": @(viewports), @"scrollChecks": @(checks),
        @"note": @"Real UIKit and production callbacks/material; synthetic Preferences parent. Not an iOS 16 device test."};
}

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic, strong) UIWindow *window;
@end
@implementation AppDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options
{
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    UIViewController *host = [UIViewController new];
    self.window.rootViewController = host;
    [self.window makeKeyAndVisible];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        NSString *documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
        NSDictionary *report;
        @try { report = RunChecks(host, documents); }
        @catch (NSException *exception) { report = @{@"status": @"failed", @"reason": exception.description}; }
        NSData *data = [NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:nil];
        [data writeToFile:[documents stringByAppendingPathComponent:@"report.json"] atomically:YES];
    });
    return YES;
}
@end
int main(int argc, char *argv[]) {
    @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass(AppDelegate.class)); }
}
