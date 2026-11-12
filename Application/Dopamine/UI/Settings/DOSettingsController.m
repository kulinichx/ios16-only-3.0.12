//
//  DOSettingsController.m
//  Dopamine
//
//  Created by tomt000 on 08/01/2024.
//

#import "DOSettingsController.h"
#import <objc/runtime.h>
#import <Photos/Photos.h>
#import <libjailbreak/util.h>
#import "DOUIManager.h"
#import "DOPkgManagerPickerViewController.h"
#import "DOHeaderCell.h"
#import "DOEnvironmentManager.h"
#import "DOExploitManager.h"
#import "DOSceneDelegate.h"
#import "DOPSListItemsController.h"
#import "DOPSExploitListItemsController.h"
#import "DOPSJetsamListItemsController.h"
#import "DOButtonCell.h"
#import "DOCustomGlassView.h"
#import "../DOSupporterLicenseUI.h"
#import "DOLowPowerScheduleController.h"

@interface DOSettingsController ()

@property(nonatomic, strong) NSMutableDictionary<NSNumber *, DOCustomLiquidGlassView *> *customGlassSectionBackdrops;
@property(nonatomic, strong) UIButton *customGlassBackButton;
@property(nonatomic, strong) UIActivityIndicatorView *customMountActivity;
@property(nonatomic) BOOL customMountBusy;

@end

@implementation DOSettingsController

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
    _table.layer.cornerRadius = 0.0;
    _table.layer.borderWidth = 0.0;
    _table.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    self.customGlassSectionBackdrops = [NSMutableDictionary dictionary];

    // Navigation must work independently of appearance or future authorization.
    UIButton *backButton = [UIButton buttonWithType:UIButtonTypeSystem];
    backButton.translatesAutoresizingMaskIntoConstraints = NO;
    backButton.tintColor = UIColor.whiteColor;
    backButton.accessibilityLabel = DOLocalizedString(@"Button_Back");
    UIImageSymbolConfiguration *configuration =
        [UIImageSymbolConfiguration configurationWithPointSize:22.0 weight:UIImageSymbolWeightMedium];
    [backButton setImage:[UIImage systemImageNamed:@"chevron.left" withConfiguration:configuration]
               forState:UIControlStateNormal];
    [backButton addTarget:self action:@selector(customGlassBackPressed)
        forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:backButton];
    self.customGlassBackButton = backButton;
    [NSLayoutConstraint activateConstraints:@[
        [backButton.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:10.0],
        [backButton.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:6.0],
        [backButton.widthAnchor constraintEqualToConstant:44.0],
        [backButton.heightAnchor constraintEqualToConstant:44.0]
    ]];

    UIScreenEdgePanGestureRecognizer *edgeGesture =
        [[UIScreenEdgePanGestureRecognizer alloc] initWithTarget:self action:@selector(customGlassEdgeBackGesture:)];
    edgeGesture.edges = UIRectEdgeLeft;
    [self.view addGestureRecognizer:edgeGesture];
    [_table.panGestureRecognizer requireGestureRecognizerToFail:edgeGesture];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(customGlassThemeDidChange:)
                                                 name:DOCustomGlassThemeDidChangeNotification
                                               object:nil];
}

- (void)customGlassBackPressed
{
    if (self.customMountBusy)
        return;
    if (self.navigationController.topViewController == self)
        [self.navigationController popViewControllerAnimated:YES];
}

- (void)customGlassEdgeBackGesture:(UIScreenEdgePanGestureRecognizer *)gesture
{
    if (gesture.state != UIGestureRecognizerStateEnded)
        return;
    CGPoint translation = [gesture translationInView:self.view];
    CGPoint velocity = [gesture velocityInView:self.view];
    if (translation.x > 60.0 && velocity.x >= 0.0)
        [self customGlassBackPressed];
}

- (void)customGlassStyleContent:(UIView *)view header:(BOOL)isHeader
{
    // Keep Preferences controls intact; the section owns the only glass frame.
    if ([view isKindOfClass:UISwitch.class] ||
        [view isKindOfClass:UISlider.class] ||
        [view isKindOfClass:UISegmentedControl.class] ||
        [view isKindOfClass:UITextField.class] ||
        [view isKindOfClass:UITextView.class])
        return;

    if (isHeader)
        view.backgroundColor = UIColor.clearColor;

    if ([view isKindOfClass:UILabel.class]) {
        UILabel *label = (UILabel *)view;
        label.textColor = [UIColor.labelColor colorWithAlphaComponent:(isHeader ? 0.74 : 0.96)];
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

    for (UIView *subview in view.subviews) {
        // Only remove simple header rules, never control or image content.
        BOOL hairline = isHeader && subview.class == UIView.class &&
            CGRectGetHeight(subview.bounds) > 0.0 &&
            CGRectGetHeight(subview.bounds) <= 2.0 &&
            CGRectGetWidth(subview.bounds) >= 40.0;
        if (hairline)
            subview.hidden = YES;
        [self customGlassStyleContent:subview header:isHeader];
    }
}

- (void)customGlassStyleCell:(UITableViewCell *)cell
{
    cell.backgroundColor = UIColor.clearColor;
    cell.contentView.backgroundColor = UIColor.clearColor;
    cell.backgroundView = nil;
    cell.layer.borderWidth = 0.0;
    cell.contentView.layer.borderWidth = 0.0;
    BOOL isHeader = [cell isKindOfClass:DOHeaderCell.class];
    if (isHeader) {
        cell.selectedBackgroundView = nil;
    }
    else {
        UIView *selected = cell.selectedBackgroundView ?: [[UIView alloc] initWithFrame:CGRectZero];
        selected.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.05];
        cell.selectedBackgroundView = selected;
    }
    [self customGlassStyleContent:cell.contentView header:isHeader];
}

- (void)customGlassRefreshSectionBackdrops
{
    NSMutableSet<NSNumber *> *activeSections = [NSMutableSet set];
    for (NSInteger section = 0; section < _table.numberOfSections; section++) {
        NSInteger rows = [_table numberOfRowsInSection:section];
        if (rows == 0)
            continue;
        CGRect firstRect = [_table rectForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:section]];
        CGRect lastRect = [_table rectForRowAtIndexPath:[NSIndexPath indexPathForRow:rows - 1 inSection:section]];
        CGRect rect = CGRectUnion(firstRect, lastRect);
        if (CGRectIsEmpty(rect))
            continue;
        NSNumber *key = @(section);
        [activeSections addObject:key];
        DOCustomLiquidGlassView *glass = self.customGlassSectionBackdrops[key];
        if (!glass) {
            glass = [[DOCustomLiquidGlassView alloc] initWithCornerRadius:18.0 baseTintAlpha:0.038];
            glass.materialScale = 0.88;
            glass.userInteractionEnabled = NO;
            self.customGlassSectionBackdrops[key] = glass;
            [_table insertSubview:glass atIndex:0];
            [glass reloadMaterial];
        }
        glass.frame = CGRectInset(rect, 1.0, 0.5);
        [_table sendSubviewToBack:glass];
    }
    for (NSNumber *key in self.customGlassSectionBackdrops.allKeys) {
        if (![activeSections containsObject:key]) {
            [self.customGlassSectionBackdrops[key] removeFromSuperview];
            [self.customGlassSectionBackdrops removeObjectForKey:key];
        }
    }
}

- (void)customGlassRefreshPageAppearance
{
    [self customGlassRefreshSectionBackdrops];
    for (UITableViewCell *cell in _table.visibleCells)
        [self customGlassStyleCell:cell];
    for (NSInteger section = 0; section < _table.numberOfSections; section++) {
        UIView *header = [_table headerViewForSection:section];
        UIView *footer = [_table footerViewForSection:section];
        [self customGlassStyleContent:header header:YES];
        [self customGlassStyleContent:footer header:YES];
    }
    if (self.customGlassBackButton)
        [self.view bringSubviewToFront:self.customGlassBackButton];
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
    for (DOCustomLiquidGlassView *glass in self.customGlassSectionBackdrops.allValues)
        [glass reloadMaterial];
    [self customGlassRefreshPageAppearance];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self.view setNeedsLayout];
    [self customGlassThemeDidChange:nil];
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    // The base class lays out a compact modal. Reserve a fixed navigation row
    // here so scrolling settings can never cover the back button.
    UIEdgeInsets safeArea = self.view.safeAreaInsets;
    CGFloat availableWidth = MAX(0.0, CGRectGetWidth(self.view.bounds) - safeArea.left - safeArea.right);
    CGFloat width = MAX(0.0, MIN(620.0, availableWidth - 24.0));
    CGFloat top = safeArea.top + 56.0;
    _table.frame = CGRectMake(safeArea.left + (availableWidth - width) * 0.5,
                             top, width,
                             MAX(0.0, CGRectGetHeight(self.view.bounds) - top - safeArea.bottom));
    [self customGlassRefreshPageAppearance];
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath
{
    [super tableView:tableView willDisplayCell:cell forRowAtIndexPath:indexPath];
    [self customGlassStyleCell:cell];
    __weak typeof(self) weakSelf = self;
    __weak UITableViewCell *weakCell = cell;
    dispatch_async(dispatch_get_main_queue(), ^{
        UITableViewCell *visibleCell = weakCell;
        if (visibleCell.window && [tableView indexPathForCell:visibleCell])
            [weakSelf customGlassStyleCell:visibleCell];
        [weakSelf customGlassRefreshSectionBackdrops];
    });
}

- (void)tableView:(UITableView *)tableView willDisplayHeaderView:(UIView *)view forSection:(NSInteger)section
{
    [self customGlassStyleContent:view header:YES];
}

- (void)tableView:(UITableView *)tableView willDisplayFooterView:(UIView *)view forSection:(NSInteger)section
{
    [self customGlassStyleContent:view header:YES];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:DOCustomGlassThemeDidChangeNotification
                                                  object:nil];
}

- (NSArray *)availableKernelExploitIdentifiers
{
    NSMutableArray *identifiers = [NSMutableArray new];
    for (DOExploit *exploit in _availableKernelExploits) {
        [identifiers addObject:exploit.identifier];
    }
    return identifiers;
}

- (NSArray *)availableKernelExploitNames
{
    NSMutableArray *names = [NSMutableArray new];
    for (DOExploit *exploit in _availableKernelExploits) {
        [names addObject:exploit.name];
    }
    return names;
}

- (NSArray *)availablePACBypassIdentifiers
{
    NSMutableArray *identifiers = [NSMutableArray new];
    if (![DOEnvironmentManager sharedManager].isPACBypassRequired) {
        [identifiers addObject:@"none"];
    }
    for (DOExploit *exploit in _availablePACBypasses) {
        [identifiers addObject:exploit.identifier];
    }
    return identifiers;
}

- (NSArray *)availablePACBypassNames
{
    NSMutableArray *names = [NSMutableArray new];
    if (![DOEnvironmentManager sharedManager].isPACBypassRequired) {
        [names addObject:DOLocalizedString(@"None")];
    }
    for (DOExploit *exploit in _availablePACBypasses) {
        [names addObject:exploit.name];
    }
    return names;
}

- (NSArray *)availablePPLBypassIdentifiers
{
    NSMutableArray *identifiers = [NSMutableArray new];
    for (DOExploit *exploit in _availablePPLBypasses) {
        [identifiers addObject:exploit.identifier];
    }
    return identifiers;
}

- (NSArray *)availablePPLBypassNames
{
    NSMutableArray *names = [NSMutableArray new];
    for (DOExploit *exploit in _availablePPLBypasses) {
        [names addObject:exploit.name];
    }
    return names;
}

- (NSArray *)jetsamOptionNumbers
{
    return @[
    @2,
    @3,
    @4,
    @5,
    @6,
    @7,
    @8,
    ];
}

- (NSArray *)jetsamOptionTitles
{
    return @[
        DOLocalizedString(@"Jetsam_Disabled"),
        @"+15 MB",
        @"+20 MB",
        @"+25 MB",
        [NSString stringWithFormat:@"+30 MB (%@)", DOLocalizedString(@"Recommended")],
        @"+35 MB",
        @"+40 MB",
    ];
}

- (id)specifiers
{
    if(_specifiers == nil) {
        NSMutableArray *specifiers = [NSMutableArray new];
        DOEnvironmentManager *envManager = [DOEnvironmentManager sharedManager];
        DOExploitManager *exploitManager = [DOExploitManager sharedManager];

        NSNumber *buttonHeight = @(44);

        SEL defGetter = @selector(readPreferenceValue:);
        SEL defSetter = @selector(setPreferenceValue:specifier:);
        SEL expGetter = @selector(readExploitPreferenceValue:);

        NSSortDescriptor *prioritySortDescriptor = [NSSortDescriptor sortDescriptorWithKey:@"priority" ascending:NO];

        _availableKernelExploits = [[exploitManager availableExploitsForType:EXPLOIT_TYPE_KERNEL] sortedArrayUsingDescriptors:@[prioritySortDescriptor]];
        if (envManager.isArm64e) {
            _availablePACBypasses = [[exploitManager availableExploitsForType:EXPLOIT_TYPE_PAC] sortedArrayUsingDescriptors:@[prioritySortDescriptor]];
            _availablePPLBypasses = [[exploitManager availableExploitsForType:EXPLOIT_TYPE_PPL] sortedArrayUsingDescriptors:@[prioritySortDescriptor]];
        }

        PSSpecifier *headerSpecifier = [PSSpecifier emptyGroupSpecifier];
        [headerSpecifier setProperty:@"DOHeaderCell" forKey:@"headerCellClass"];
        [headerSpecifier setProperty:[NSString stringWithFormat:@"Settings"] forKey:@"title"];
        [specifiers addObject:headerSpecifier];

        if (envManager.isSupported) {
            if (!envManager.isJailbroken) {
                PSSpecifier *exploitGroupSpecifier = [PSSpecifier emptyGroupSpecifier];
                exploitGroupSpecifier.name = DOLocalizedString(@"Section_Exploits");
                [specifiers addObject:exploitGroupSpecifier];

                PSSpecifier *kernelExploitSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedString(@"Kernel Exploit") target:self set:defSetter get:expGetter detail:nil cell:PSLinkListCell edit:nil];
                [kernelExploitSpecifier setProperty:@YES forKey:@"enabled"];
                [kernelExploitSpecifier setProperty:exploitManager.preferredKernelExploit.identifier forKey:@"default"];
                kernelExploitSpecifier.detailControllerClass = [DOPSExploitListItemsController class];
                [kernelExploitSpecifier setProperty:@"availableKernelExploitIdentifiers" forKey:@"valuesDataSource"];
                [kernelExploitSpecifier setProperty:@"availableKernelExploitNames" forKey:@"titlesDataSource"];
                [kernelExploitSpecifier setProperty:@"selectedKernelExploit" forKey:@"key"];
                [kernelExploitSpecifier setProperty:(_availableKernelExploits.firstObject.identifier ?: @"none") forKey:@"recommendedExploitIdentifier"];
                [specifiers addObject:kernelExploitSpecifier];

                if (envManager.isArm64e) {
                    PSSpecifier *pacBypassSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedString(@"PAC Bypass") target:self set:defSetter get:expGetter detail:nil cell:PSLinkListCell edit:nil];
                    [pacBypassSpecifier setProperty:@YES forKey:@"enabled"];
                    DOExploit *preferredPACBypass = exploitManager.preferredPACBypass;
                    if (!preferredPACBypass) {
                        [pacBypassSpecifier setProperty:@"none" forKey:@"default"];
                    }
                    else {
                        [pacBypassSpecifier setProperty:preferredPACBypass.identifier forKey:@"default"];
                    }
                    pacBypassSpecifier.detailControllerClass = [DOPSExploitListItemsController class];
                    [pacBypassSpecifier setProperty:@"availablePACBypassIdentifiers" forKey:@"valuesDataSource"];
                    [pacBypassSpecifier setProperty:@"availablePACBypassNames" forKey:@"titlesDataSource"];
                    [pacBypassSpecifier setProperty:@"selectedPACBypass" forKey:@"key"];
                    [pacBypassSpecifier setProperty:([envManager isPACBypassRequired] ? _availablePACBypasses.firstObject.identifier : @"none") forKey:@"recommendedExploitIdentifier"];
                    [specifiers addObject:pacBypassSpecifier];

                    NSString *pplBypassName = @"PPL Bypass";

                    PSSpecifier *pplBypassSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedString(pplBypassName) target:self set:defSetter get:expGetter detail:nil cell:PSLinkListCell edit:nil];
                    [pplBypassSpecifier setProperty:@YES forKey:@"enabled"];
                    [pplBypassSpecifier setProperty:exploitManager.preferredPPLBypass.identifier forKey:@"default"];
                    pplBypassSpecifier.detailControllerClass = [DOPSExploitListItemsController class];
                    [pplBypassSpecifier setProperty:@"availablePPLBypassIdentifiers" forKey:@"valuesDataSource"];
                    [pplBypassSpecifier setProperty:@"availablePPLBypassNames" forKey:@"titlesDataSource"];
                    [pplBypassSpecifier setProperty:@"selectedPPLBypass" forKey:@"key"];
                    [pplBypassSpecifier setProperty:(_availablePPLBypasses.firstObject.identifier ?: @"none") forKey:@"recommendedExploitIdentifier"];
                    [specifiers addObject:pplBypassSpecifier];
                }
            }

            PSSpecifier *settingsGroupSpecifier = [PSSpecifier emptyGroupSpecifier];
            settingsGroupSpecifier.name = DOLocalizedString(@"Section_Jailbreak_Settings");
            [specifiers addObject:settingsGroupSpecifier];

            PSSpecifier *tweakInjectionSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedString(@"Settings_Tweak_Injection") target:self set:@selector(setTweakInjectionEnabled:specifier:) get:@selector(readTweakInjectionEnabled:) detail:nil cell:PSSwitchCell edit:nil];
            [tweakInjectionSpecifier setProperty:@YES forKey:@"enabled"];
            [tweakInjectionSpecifier setProperty:@"tweakInjectionEnabled" forKey:@"key"];
            [tweakInjectionSpecifier setProperty:@YES forKey:@"default"];
            [specifiers addObject:tweakInjectionSpecifier];

            if (!envManager.isJailbroken) {
                PSSpecifier *verboseLogSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedString(@"Settings_Verbose_Logs") target:self set:defSetter get:defGetter detail:nil cell:PSSwitchCell edit:nil];
                [verboseLogSpecifier setProperty:@YES forKey:@"enabled"];
                [verboseLogSpecifier setProperty:@"verboseLogsEnabled" forKey:@"key"];
                [verboseLogSpecifier setProperty:@NO forKey:@"default"];
                [specifiers addObject:verboseLogSpecifier];
            }

            PSSpecifier *idownloadSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedString(@"Settings_iDownload") target:self set:@selector(setIDownloadEnabled:specifier:) get:@selector(readIDownloadEnabled:) detail:nil cell:PSSwitchCell edit:nil];
            [idownloadSpecifier setProperty:@YES forKey:@"enabled"];
            [idownloadSpecifier setProperty:@"idownloadEnabled" forKey:@"key"];
            [idownloadSpecifier setProperty:@NO forKey:@"default"];
            [specifiers addObject:idownloadSpecifier];

            PSSpecifier *appJitSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedString(@"Settings_Apps_JIT") target:self set:@selector(setAppJITEnabled:specifier:) get:@selector(readAppJITEnabled:) detail:nil cell:PSSwitchCell edit:nil];
            [appJitSpecifier setProperty:@YES forKey:@"enabled"];
            [appJitSpecifier setProperty:@"appJITEnabled" forKey:@"key"];
            [appJitSpecifier setProperty:@YES forKey:@"default"];
            [specifiers addObject:appJitSpecifier];

            /**************************** roothide specfic *********************************/
            NSString* namedesc = DOLocalizedString(@"Enable dyld patch");
            PSSpecifier *dyldPatchSpecifier = [PSSpecifier preferenceSpecifierNamed:namedesc target:self set:@selector(setDyldPatchEnabled:specifier:) get:@selector(readDyldPatchEnabled:) detail:nil cell:PSSwitchCell edit:nil];
            [dyldPatchSpecifier setProperty:@YES forKey:@"enabled"];
            [dyldPatchSpecifier setProperty:@"dyldPatchEnabled" forKey:@"key"];
            [dyldPatchSpecifier setProperty:@NO forKey:@"default"];
            [specifiers addObject:dyldPatchSpecifier];
            /**************************** roothide specfic *********************************/

            PSSpecifier *jetsamSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedString(@"Settings_Jetsam_Multiplier") target:self set:@selector(setJetsamMultiplier:specifier:) get:@selector(readJetsamMultiplier:) detail:nil cell:PSLinkListCell edit:nil];
            [jetsamSpecifier setProperty:@YES forKey:@"enabled"];
            [jetsamSpecifier setProperty:@"jetsamMultiplier" forKey:@"key"];
            [jetsamSpecifier setProperty:@6 forKey:@"default"];
            jetsamSpecifier.detailControllerClass = [DOPSJetsamListItemsController class];
            [jetsamSpecifier setProperty:@"jetsamOptionNumbers" forKey:@"valuesDataSource"];
            [jetsamSpecifier setProperty:@"jetsamOptionTitles" forKey:@"titlesDataSource"];
            [specifiers addObject:jetsamSpecifier];

            PSSpecifier *supporterSpecifier = [PSSpecifier preferenceSpecifierNamed:@"" target:self set:defSetter get:defGetter detail:nil cell:PSStaticTextCell edit:nil];
            [supporterSpecifier setProperty:@"Supporter_Title" forKey:@"title"];
            [supporterSpecifier setProperty:[DOButtonCell class] forKey:@"cellClass"];
            [supporterSpecifier setProperty:buttonHeight forKey:@"height"];
            [supporterSpecifier setProperty:@"checkmark.seal" forKey:@"image"];
            [supporterSpecifier setProperty:@"supporterLicensePressed" forKey:@"action"];
            [specifiers addObject:supporterSpecifier];

            if (!envManager.isJailbroken && !envManager.isInstalledThroughTrollStore) {
                PSSpecifier *removeJailbreakSwitchSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedString(@"Button_Remove_Jailbreak") target:self set:@selector(setRemoveJailbreakEnabled:specifier:) get:defGetter detail:nil cell:PSSwitchCell edit:nil];
                [removeJailbreakSwitchSpecifier setProperty:@YES forKey:@"enabled"];
                [removeJailbreakSwitchSpecifier setProperty:@"removeJailbreakEnabled" forKey:@"key"];
                [specifiers addObject:removeJailbreakSwitchSpecifier];
            }

            if (envManager.isBootstrapped) {
                PSSpecifier *actionsGroupSpecifier = [PSSpecifier emptyGroupSpecifier];
                actionsGroupSpecifier.name = DOLocalizedString(@"Section_Actions");
                [specifiers addObject:actionsGroupSpecifier];

                if (envManager.isJailbroken) {
                    PSSpecifier *lowPowerSchedule = [PSSpecifier preferenceSpecifierNamed:@"" target:self set:nil get:nil detail:nil cell:PSStaticTextCell edit:nil];
                    [lowPowerSchedule setProperty:@"LowPowerSchedule_Title" forKey:@"title"];
                    [lowPowerSchedule setProperty:[DOButtonCell class] forKey:@"cellClass"];
                    [lowPowerSchedule setProperty:buttonHeight forKey:@"height"];
                    [lowPowerSchedule setProperty:@"calendar.badge.clock" forKey:@"image"];
                    [lowPowerSchedule setProperty:@"lowPowerSchedulePressed" forKey:@"action"];
                    [specifiers addObject:lowPowerSchedule];

                    PSSpecifier *mountSpecifier = [PSSpecifier preferenceSpecifierNamed:@"" target:self set:nil get:nil detail:nil cell:PSStaticTextCell edit:nil];
                    [mountSpecifier setProperty:@"CustomMount_Add" forKey:@"title"];
                    [mountSpecifier setProperty:[DOButtonCell class] forKey:@"cellClass"];
                    [mountSpecifier setProperty:buttonHeight forKey:@"height"];
                    [mountSpecifier setProperty:@"folder.badge.plus" forKey:@"image"];
                    [mountSpecifier setProperty:@"mountCustomDirectoryPressed" forKey:@"action"];
                    [specifiers addObject:mountSpecifier];

                    PSSpecifier *manageMountSpecifier = [PSSpecifier preferenceSpecifierNamed:@"" target:self set:nil get:nil detail:nil cell:PSStaticTextCell edit:nil];
                    [manageMountSpecifier setProperty:@"CustomMount_Manage" forKey:@"title"];
                    [manageMountSpecifier setProperty:[DOButtonCell class] forKey:@"cellClass"];
                    [manageMountSpecifier setProperty:buttonHeight forKey:@"height"];
                    [manageMountSpecifier setProperty:@"folder.badge.gearshape" forKey:@"image"];
                    [manageMountSpecifier setProperty:@"manageCustomMountsPressed" forKey:@"action"];
                    [specifiers addObject:manageMountSpecifier];

                    PSSpecifier *refreshAppsSpecifier = [PSSpecifier preferenceSpecifierNamed:@"" target:self set:defSetter get:defGetter detail:nil cell:PSStaticTextCell edit:nil];
                    [refreshAppsSpecifier setProperty:@"Button_Refresh_Jailbreak_Apps" forKey:@"title"];
                    [refreshAppsSpecifier setProperty:[DOButtonCell class] forKey:@"cellClass"];
                    [refreshAppsSpecifier setProperty:buttonHeight forKey:@"height"];
                    [refreshAppsSpecifier setProperty:@"arrow.triangle.2.circlepath" forKey:@"image"];
                    [refreshAppsSpecifier setProperty:@"refreshJailbreakAppsPressed" forKey:@"action"];
                    [specifiers addObject:refreshAppsSpecifier];

                    PSSpecifier *changeMobilePasswordSpecifier = [PSSpecifier preferenceSpecifierNamed:@"" target:self set:defSetter get:defGetter detail:nil cell:PSStaticTextCell edit:nil];
                    [changeMobilePasswordSpecifier setProperty:@"Button_Change_Mobile_Password" forKey:@"title"];
                    [changeMobilePasswordSpecifier setProperty:[DOButtonCell class] forKey:@"cellClass"];
                    [changeMobilePasswordSpecifier setProperty:buttonHeight forKey:@"height"];
                    [changeMobilePasswordSpecifier setProperty:@"key" forKey:@"image"];
                    [changeMobilePasswordSpecifier setProperty:@"changeMobilePasswordWithAuthenticationPressed" forKey:@"action"];
                    [specifiers addObject:changeMobilePasswordSpecifier];

                    PSSpecifier *reinstallPackageManagersSpecifier = [PSSpecifier preferenceSpecifierNamed:@"" target:self set:defSetter get:defGetter detail:nil cell:PSStaticTextCell edit:nil];
                    [reinstallPackageManagersSpecifier setProperty:@"Button_Reinstall_Package_Managers" forKey:@"title"];
                    [reinstallPackageManagersSpecifier setProperty:[DOButtonCell class] forKey:@"cellClass"];
                    [reinstallPackageManagersSpecifier setProperty:buttonHeight forKey:@"height"];
                    [reinstallPackageManagersSpecifier setProperty:@"shippingbox.and.arrow.backward" forKey:@"image"];
                    [reinstallPackageManagersSpecifier setProperty:@"reinstallPackageManagersPressed" forKey:@"action"];
                    [specifiers addObject:reinstallPackageManagersSpecifier];
                }

/*
                BOOL hideJailbreakButtonShown = (envManager.isJailbroken || (envManager.isInstalledThroughTrollStore && !envManager.isJailbreakHidden));
                if (hideJailbreakButtonShown) {
                    // The "Hide Jailbreak" button should be shown
                    // - When jailbroken
                    // - When Dopamine is installed by TrollStore and the jailbreak is not hidden yet
                    PSSpecifier *hideUnhideJailbreakSpecifier = [PSSpecifier preferenceSpecifierNamed:@"" target:self set:defSetter get:defGetter detail:nil cell:PSStaticTextCell edit:nil];
                    [hideUnhideJailbreakSpecifier setProperty:[DOButtonCell class] forKey:@"cellClass"];
                    [hideUnhideJailbreakSpecifier setProperty:buttonHeight forKey:@"height"];
                    if (envManager.isJailbreakHidden) {
                        [hideUnhideJailbreakSpecifier setProperty:@"Button_Unhide_Jailbreak" forKey:@"title"];
                        [hideUnhideJailbreakSpecifier setProperty:@"eye" forKey:@"image"];
                    }
                    else {
                        [hideUnhideJailbreakSpecifier setProperty:@"Button_Hide_Jailbreak" forKey:@"title"];
                        [hideUnhideJailbreakSpecifier setProperty:@"eye.slash" forKey:@"image"];
                    }
                    [hideUnhideJailbreakSpecifier setProperty:@"hideUnhideJailbreakPressed" forKey:@"action"];
                    [specifiers addObject:hideUnhideJailbreakSpecifier];
                }
*/

                if (!envManager.isJailbroken && envManager.isInstalledThroughTrollStore) {
                    // The "Remove Jailbreak" button cannot show when being jailbroken since pressing it would kinda be russian roulette
                    // It might work, it might not and panic your device and leave it in a half uninstalled state
                    // So this button is only for when you're not jailbroken and have Dopamine installed with TrollStore
                    // The only supported uninstallation flow without TrollStore is to reboot and "rejailbreak" with "Remove Jailbreak" toggle enabled
                    PSSpecifier *removeJailbreakSpecifier = [PSSpecifier preferenceSpecifierNamed:@"" target:self set:defSetter get:defGetter detail:nil cell:PSStaticTextCell edit:nil];
                    [removeJailbreakSpecifier setProperty:@"Button_Remove_Jailbreak" forKey:@"title"];
                    [removeJailbreakSpecifier setProperty:[DOButtonCell class] forKey:@"cellClass"];
                    [removeJailbreakSpecifier setProperty:buttonHeight forKey:@"height"];
                    [removeJailbreakSpecifier setProperty:@"trash" forKey:@"image"];
                    [removeJailbreakSpecifier setProperty:@"removeJailbreakPressed" forKey:@"action"];
                    [specifiers addObject:removeJailbreakSpecifier];
                }

/*
                if (hideJailbreakButtonShown) {
                    [actionsGroupSpecifier setProperty:DOLocalizedString(envManager.isJailbroken ? @"Hint_Hide_Jailbreak_Jailbroken" : @"Hint_Hide_Jailbreak") forKey:@"footerText"];
                }
*/
            }
        }

        PSSpecifier *bootlogoGropSpecifier = [PSSpecifier emptyGroupSpecifier];
        bootlogoGropSpecifier.name = DOLocalizedString(@"Section_Boot_Logo");
        [specifiers addObject:bootlogoGropSpecifier];

        PSSpecifier *bootlogoEnabledSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedString(@"Enabled") target:self set:@selector(setBootlogoEnabled:specifier:) get:defGetter detail:nil cell:PSSwitchCell edit:nil];
        [bootlogoEnabledSpecifier setProperty:@YES forKey:@"enabled"];
        [bootlogoEnabledSpecifier setProperty:@"bootlogoEnabled" forKey:@"key"];
        [bootlogoEnabledSpecifier setProperty:@YES forKey:@"default"];
        bootlogoEnabledSpecifier.identifier = @"bootlogoEnabled";
        [specifiers addObject:bootlogoEnabledSpecifier];

        _customBootlogoEnabledSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedString(@"Custom_Boot_Logo") target:self set:@selector(setCustomBootlogoEnabled:specifier:) get:defGetter detail:nil cell:PSSwitchCell edit:nil];
        [_customBootlogoEnabledSpecifier setProperty:@YES forKey:@"enabled"];
        [_customBootlogoEnabledSpecifier setProperty:@"customBootlogoEnabled" forKey:@"key"];
        [_customBootlogoEnabledSpecifier setProperty:@NO forKey:@"default"];
        _customBootlogoEnabledSpecifier.identifier = @"customBootlogoEnabled";

        _customBootlogoSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedString(@"Select_Image") target:self set:defSetter get:defGetter detail:nil cell:PSButtonCell edit:nil];
        _customBootlogoSpecifier.buttonAction = @selector(selectCustomBootlogoPressed);
        [_customBootlogoSpecifier setProperty:@YES forKey:@"enabled"];
        [_customBootlogoSpecifier setProperty:@"customBootlogo" forKey:@"key"];
        _customBootlogoSpecifier.identifier = @"customBootlogo";

        if ([[DOPreferenceManager sharedManager] boolPreferenceValueForKey:@"bootlogoEnabled" fallback:YES]) {
            [specifiers addObject:_customBootlogoEnabledSpecifier];

            if ([[DOPreferenceManager sharedManager] boolPreferenceValueForKey:@"customBootlogoEnabled" fallback:NO]) {
                [specifiers addObject:_customBootlogoSpecifier];
            }
        }

        _specifiers = specifiers;
    }
    return _specifiers;
}

#pragma mark - Getters & Setters

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier
{
    NSString *key = [specifier propertyForKey:@"key"];
    [[DOPreferenceManager sharedManager] setPreferenceValue:value forKey:key];
}

- (id)readPreferenceValue:(PSSpecifier*)specifier
{
    NSString *key = [specifier propertyForKey:@"key"];
    id value = [[DOPreferenceManager sharedManager] preferenceValueForKey:key];
    if (!value) {
        return [specifier propertyForKey:@"default"];
    }
    return value;
}

- (id)readExploitPreferenceValue:(PSSpecifier *)specifier
{
    id value = [self readPreferenceValue:specifier];

    SEL dataSourceSel = nil;
    NSString *selString = [specifier propertyForKey:@"valuesDataSource"];
    if (selString) {
        dataSourceSel = NSSelectorFromString(selString);
    }

    if (dataSourceSel && [value isKindOfClass:[NSString class]]) {
        NSString *valueString = (NSString *)value;

        IMP imp = [specifier.target methodForSelector:dataSourceSel];
        if (imp) {
            NSArray *(*func)(id, SEL) = (void *)imp;
            NSArray *availableIdentifiers = func(specifier.target, dataSourceSel);
            if (![availableIdentifiers containsObject:valueString]) {
                return [specifier propertyForKey:@"default"];
            }
        }
    }

    return value;
}

- (id)readIDownloadEnabled:(PSSpecifier *)specifier
{
    DOEnvironmentManager *envManager = [DOEnvironmentManager sharedManager];
    if (envManager.isJailbroken) {
        return @([DOEnvironmentManager sharedManager].isIDownloadEnabled);
    }
    return [self readPreferenceValue:specifier];
}

- (void)setIDownloadEnabled:(id)value specifier:(PSSpecifier *)specifier
{
    [self setPreferenceValue:value specifier:specifier];
    DOEnvironmentManager *envManager = [DOEnvironmentManager sharedManager];
    if (envManager.isJailbroken) {
        [[DOEnvironmentManager sharedManager] setIDownloadLoaded:((NSNumber *)value).boolValue needsUnsandbox:YES];
    }
}

- (id)readTweakInjectionEnabled:(PSSpecifier *)specifier
{
    DOEnvironmentManager *envManager = [DOEnvironmentManager sharedManager];
    if (envManager.isJailbroken) {
        return @([DOEnvironmentManager sharedManager].isTweakInjectionEnabled);
    }
    return [self readPreferenceValue:specifier];
}

- (void)setTweakInjectionEnabled:(id)value specifier:(PSSpecifier *)specifier
{
    [self setPreferenceValue:value specifier:specifier];
    DOEnvironmentManager *envManager = [DOEnvironmentManager sharedManager];
    if (envManager.isJailbroken) {
        [[DOEnvironmentManager sharedManager] setTweakInjectionEnabled:((NSNumber *)value).boolValue];
        UIAlertController *userspaceRebootAlertController = [UIAlertController alertControllerWithTitle:DOLocalizedString(@"Alert_Tweak_Injection_Toggled_Title") message:DOLocalizedString(@"Alert_Tweak_Injection_Toggled_Body") preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction *rebootNowAction = [UIAlertAction actionWithTitle:DOLocalizedString(@"Alert_Tweak_Injection_Toggled_Reboot_Now") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            [[DOEnvironmentManager sharedManager] rebootUserspace];
        }];
        UIAlertAction *rebootLaterAction = [UIAlertAction actionWithTitle:DOLocalizedString(@"Alert_Tweak_Injection_Toggled_Reboot_Later") style:UIAlertActionStyleCancel handler:nil];

        [userspaceRebootAlertController addAction:rebootNowAction];
        [userspaceRebootAlertController addAction:rebootLaterAction];
        [self presentViewController:userspaceRebootAlertController animated:YES completion:nil];
    }
}

- (id)readAppJITEnabled:(PSSpecifier *)specifier
{
    DOEnvironmentManager *envManager = [DOEnvironmentManager sharedManager];
    if (envManager.isJailbroken) {
        bool v = jbclient_jbsettings_get_bool("markAppsAsDebugged");
        return @(v);
    }
    return [self readPreferenceValue:specifier];
}

- (void)setAppJITEnabled:(id)value specifier:(PSSpecifier *)specifier
{
    [self setPreferenceValue:value specifier:specifier];
    DOEnvironmentManager *envManager = [DOEnvironmentManager sharedManager];
    if (envManager.isJailbroken) {
        jbclient_platform_jbsettings_set_bool("markAppsAsDebugged", ((NSNumber *)value).boolValue);
    }
}

- (id)readJetsamMultiplier:(PSSpecifier *)specifier
{
    DOEnvironmentManager *envManager = [DOEnvironmentManager sharedManager];
    if (envManager.isJailbroken) {
        double v = jbclient_jbsettings_get_double("jetsamMultiplier");
        return @((v < 1 || isnan(v)) ? 6 : ceil(v * 2));
    }
    return [self readPreferenceValue:specifier];
}

- (void)setJetsamMultiplier:(id)value specifier:(PSSpecifier *)specifier
{
    [self setPreferenceValue:value specifier:specifier];
    DOEnvironmentManager *envManager = [DOEnvironmentManager sharedManager];
    if (envManager.isJailbroken) {
        jbclient_platform_jbsettings_set_double("jetsamMultiplier", ((NSNumber *)value).doubleValue / 2);
    }
}

- (void)setRemoveJailbreakEnabled:(id)value specifier:(PSSpecifier *)specifier
{
    [self setPreferenceValue:value specifier:specifier];
    if (((NSNumber *)value).boolValue) {
        UIAlertController *confirmationAlertController = [UIAlertController alertControllerWithTitle:DOLocalizedString(@"Alert_Remove_Jailbreak_Title") message:DOLocalizedString(@"Alert_Remove_Jailbreak_Enabled_Body") preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction *uninstallAction = [UIAlertAction actionWithTitle:DOLocalizedString(@"Button_Continue") style:UIAlertActionStyleDestructive handler:nil];
        UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:DOLocalizedString(@"Button_Cancel") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            [self setPreferenceValue:@NO specifier:specifier];
            [self reloadSpecifiers];
        }];
        [confirmationAlertController addAction:uninstallAction];
        [confirmationAlertController addAction:cancelAction];
        [self presentViewController:confirmationAlertController animated:YES completion:nil];
    }
}

- (void)setBootlogoEnabled:(id)value specifier:(PSSpecifier *)specifier
{
    bool prevValueBool = ((NSNumber *)[self readPreferenceValue:specifier]).boolValue;
    [self setPreferenceValue:value specifier:specifier];
    bool valueBool = ((NSNumber *)value).boolValue;

    if (prevValueBool != valueBool) {
        NSMutableArray *affectedSpecifiers = [NSMutableArray new];
        [affectedSpecifiers addObject:_customBootlogoEnabledSpecifier];

        if (valueBool == ![self containsSpecifier:_customBootlogoSpecifier]) {
            [affectedSpecifiers addObject:_customBootlogoSpecifier];
        }

        if (valueBool) {
            [self insertContiguousSpecifiers:affectedSpecifiers afterSpecifier:specifier animated:YES];
        }
        else {
            [self removeContiguousSpecifiers:affectedSpecifiers animated:YES];
        }
    }

    if ([DOEnvironmentManager sharedManager].isJailbroken) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [[DOEnvironmentManager sharedManager] updateBootLogo];
        });
    }
}

- (void)setCustomBootlogoEnabled:(id)value specifier:(PSSpecifier *)specifier
{
    bool prevValueBool = ((NSNumber *)[self readPreferenceValue:specifier]).boolValue;
    [self setPreferenceValue:value specifier:specifier];
    bool valueBool = ((NSNumber *)value).boolValue;

    if (prevValueBool != valueBool) {
        if (valueBool) {
            [self insertSpecifier:_customBootlogoSpecifier afterSpecifier:specifier animated:YES];
        }
        else {
            [self removeSpecifier:_customBootlogoSpecifier animated:YES];
        }
    }

    if ([DOEnvironmentManager sharedManager].isJailbroken) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [[DOEnvironmentManager sharedManager] updateBootLogo];
        });
    }
}

- (void)selectCustomBootlogoPressed
{
    PHAuthorizationStatus status = [PHPhotoLibrary authorizationStatus];
    if (status == PHAuthorizationStatusDenied || status == PHAuthorizationStatusRestricted) {
        return;
    } else if (status == PHAuthorizationStatusNotDetermined) {
        [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
            if (status == PHAuthorizationStatusAuthorized) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self selectCustomBootlogoPressed];
                });
            }
        }];
        return;
    }

    UIImagePickerController *picker = [[UIImagePickerController alloc] init];
    picker.delegate = self;
    picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    [self presentViewController:picker animated:YES completion:nil];
}

#pragma mark - Boot Logo Picker

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<NSString *,id> *)info {
    UIImage *chosenImage = info[UIImagePickerControllerEditedImage];
    if (!chosenImage) {
        chosenImage = info[UIImagePickerControllerOriginalImage];
    }

    // Force correct the orientation
    // For some reason without rerendering the image, the stored file will have a wrong orientation for photos taken with the camera‚
    UIGraphicsBeginImageContextWithOptions(chosenImage.size, NO, 1.0);
    [chosenImage drawInRect:CGRectMake(0,0, chosenImage.size.width, chosenImage.size.height)];
    chosenImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();

    [UIImagePNGRepresentation(chosenImage) writeToFile:[DOUIManager sharedInstance].bootlogoPath atomically:YES];

    if ([DOEnvironmentManager sharedManager].isJailbroken) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [[DOEnvironmentManager sharedManager] updateBootLogo];
        });
    }

    [picker dismissViewControllerAnimated:YES completion:nil];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [picker dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Button Actions

- (void)setCustomMountBusy:(BOOL)busy
{
    _customMountBusy = busy;
    self.view.userInteractionEnabled = !busy;
    if (busy) {
        if (!self.customMountActivity) {
            UIActivityIndicatorView *activity = [[UIActivityIndicatorView alloc]
                initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
            activity.translatesAutoresizingMaskIntoConstraints = NO;
            activity.color = UIColor.whiteColor;
            activity.accessibilityLabel = DOLocalizedString(@"CustomMount_Working");
            [self.view addSubview:activity];
            [NSLayoutConstraint activateConstraints:@[
                [activity.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
                [activity.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor]
            ]];
            self.customMountActivity = activity;
        }
        [self.view bringSubviewToFront:self.customMountActivity];
        [self.customMountActivity startAnimating];
    } else {
        [self.customMountActivity stopAnimating];
    }
}

- (void)presentCustomMountMessage:(NSString *)message
{
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:DOLocalizedString(@"CustomMount_Title")
                         message:message
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:DOLocalizedString(@"OK")
                                              style:UIAlertActionStyleDefault
                                            handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)mountCustomDirectoryPressed
{
    DOEnvironmentManager *environment = DOEnvironmentManager.sharedManager;
    if (!environment.isJailbroken) return;

    UIAlertController *input = [UIAlertController
        alertControllerWithTitle:DOLocalizedString(@"CustomMount_Add")
                         message:DOLocalizedString(@"CustomMount_Path_Prompt")
                  preferredStyle:UIAlertControllerStyleAlert];
    [input addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"/System/Library/Fonts";
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
        field.autocorrectionType = UITextAutocorrectionTypeNo;
        field.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    [input addAction:[UIAlertAction actionWithTitle:DOLocalizedString(@"Button_Cancel")
                                               style:UIAlertActionStyleCancel
                                             handler:nil]];
    [input addAction:[UIAlertAction actionWithTitle:DOLocalizedString(@"CustomMount_Add")
                                               style:UIAlertActionStyleDefault
                                             handler:^(__unused UIAlertAction *action) {
        NSString *enteredPath = [input.textFields.firstObject.text
            stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        NSString *path = enteredPath.stringByStandardizingPath;
        if (![enteredPath hasPrefix:@"/"] || ![path isEqualToString:enteredPath]) {
            [self presentCustomMountMessage:DOLocalizedString(@"CustomMount_InvalidPath")];
            return;
        }

        NSArray<NSString *> *existingPaths = environment.customMountPaths;
        if ([existingPaths containsObject:path]) {
            [self presentCustomMountMessage:DOLocalizedString(@"CustomMount_AlreadyExists")];
            return;
        }
        NSString *conflict = [environment conflictingCustomMountPathForPath:path];
        if (conflict) {
            [self presentCustomMountMessage:
                [NSString stringWithFormat:DOLocalizedString(@"CustomMount_Overlap"), conflict]];
            return;
        }

        // Match ZQBB's save-before-mount order; a save failure owns no copy to delete.
        NSArray<NSString *> *updatedPaths = [existingPaths arrayByAddingObject:path];
        if (![environment saveCustomMountPaths:updatedPaths]) {
            [self presentCustomMountMessage:DOLocalizedString(@"CustomMount_SaveFailed")];
            return;
        }
        self.customMountBusy = YES;
        [environment mountCustomDirectory:path completion:^(int result) {
            self.customMountBusy = NO;
            if (result != 0) {
                BOOL restored = [environment saveCustomMountPaths:existingPaths];
                NSString *message = [NSString stringWithFormat:DOLocalizedString(@"CustomMount_Failed"), result];
                if (!restored)
                    message = [message stringByAppendingFormat:@"\n%@", DOLocalizedString(@"CustomMount_ListRestoreFailed")];
                [self reloadSpecifiers];
                [self presentCustomMountMessage:message];
                return;
            }
            [self reloadSpecifiers];
        }];
    }]];
    [self presentViewController:input animated:YES completion:nil];
}

- (void)manageCustomMountsPressed
{
    DOEnvironmentManager *environment = DOEnvironmentManager.sharedManager;
    if (!environment.isJailbroken) return;

    NSArray<NSString *> *paths = environment.customMountPaths;
    if (paths.count == 0) {
        [self presentCustomMountMessage:DOLocalizedString(@"CustomMount_Empty")];
        return;
    }

    UIAlertController *list = [UIAlertController
        alertControllerWithTitle:DOLocalizedString(@"CustomMount_Manage")
                         message:nil
                  preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSString *path in paths) {
        if (![path isKindOfClass:NSString.class]) continue;
        [list addAction:[UIAlertAction actionWithTitle:path
                                                 style:UIAlertActionStyleDefault
                                               handler:^(__unused UIAlertAction *action) {
            NSString *targetMountPath = [JBROOT_PATH(@"/mnt") stringByAppendingString:path];
            UIAlertController *confirm = [UIAlertController
                alertControllerWithTitle:path
                                 message:DOLocalizedString(@"CustomMount_ManagePrompt")
                          preferredStyle:UIAlertControllerStyleAlert];
            [confirm addAction:[UIAlertAction actionWithTitle:DOLocalizedString(@"Button_Cancel")
                                                        style:UIAlertActionStyleCancel
                                                      handler:nil]];
            [confirm addAction:[UIAlertAction actionWithTitle:DOLocalizedString(@"CustomMount_View")
                                                        style:UIAlertActionStyleDefault
                                                      handler:^(__unused UIAlertAction *viewAction) {
                NSString *encodedPath = [targetMountPath
                    stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLPathAllowedCharacterSet];
                NSURL *url = [NSURL URLWithString:[@"filza://view" stringByAppendingString:encodedPath ?: targetMountPath]];
                [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:^(BOOL success) {
                    if (!success) {
                        NSString *fallbackPath = [@"fffff://view" stringByAppendingString:encodedPath ?: targetMountPath];
                        NSURL *fallbackURL = [NSURL URLWithString:fallbackPath];
                        [[UIApplication sharedApplication] openURL:fallbackURL options:@{} completionHandler:^(BOOL fallbackSuccess) {
                            if (!fallbackSuccess) {
                                dispatch_async(dispatch_get_main_queue(), ^{
                                    [self presentCustomMountMessage:DOLocalizedString(@"CustomMount_ViewUnavailable")];
                                });
                            }
                        }];
                    }
                }];
            }]];
            [confirm addAction:[UIAlertAction actionWithTitle:DOLocalizedString(@"CustomMount_Forget")
                                                        style:UIAlertActionStyleDestructive
                                                      handler:^(__unused UIAlertAction *forgetAction) {
                NSString *blocker = [environment customMountRemovalBlockerForPath:path];
                if (blocker) {
                    [self presentCustomMountMessage:
                        [NSString stringWithFormat:DOLocalizedString(@"CustomMount_RemoveParentFirst"), blocker]];
                    return;
                }
                NSMutableArray<NSString *> *updatedPaths = [paths mutableCopy];
                [updatedPaths removeObject:path];
                if (![environment saveCustomMountPaths:updatedPaths]) {
                    [self presentCustomMountMessage:DOLocalizedString(@"CustomMount_SaveFailed")];
                    return;
                }
                [self reloadSpecifiers];
            }]];
            [confirm addAction:[UIAlertAction actionWithTitle:DOLocalizedString(@"CustomMount_Unmount")
                                                        style:UIAlertActionStyleDestructive
                                                      handler:^(__unused UIAlertAction *confirmAction) {
                NSString *blocker = [environment customMountRemovalBlockerForPath:path];
                if (blocker) {
                    [self presentCustomMountMessage:
                        [NSString stringWithFormat:DOLocalizedString(@"CustomMount_RemoveParentFirst"), blocker]];
                    return;
                }
                self.customMountBusy = YES;
                [environment unmountCustomDirectory:path completion:^(int result) {
                    if (result != 0) {
                        self.customMountBusy = NO;
                        [self presentCustomMountMessage:
                            [NSString stringWithFormat:DOLocalizedString(@"CustomMount_Failed"), result]];
                        return;
                    }
                    [environment finishCustomMountRemovalAtPath:path completion:^(DOCustomMountRemovalResult removal) {
                        self.customMountBusy = NO;
                        [self reloadSpecifiers];
                        NSString *messageKey = nil;
                        if (removal == DOCustomMountRemovalSaveFailed)
                            messageKey = @"CustomMount_UnmountedSaveFailed";
                        else if (removal == DOCustomMountRemovalCopyPreserved)
                            messageKey = @"CustomMount_SharedCopyPreserved";
                        else if (removal == DOCustomMountRemovalCleanupFailed)
                            messageKey = @"CustomMount_CleanupFailed";
                        if (messageKey) {
                            NSString *message = [NSString stringWithFormat:@"%@\n%@",
                                DOLocalizedString(messageKey), targetMountPath];
                            [self presentCustomMountMessage:message];
                        }
                    }];
                }];
            }]];
            [self presentViewController:confirm animated:YES completion:nil];
        }]];
    }
    [list addAction:[UIAlertAction actionWithTitle:DOLocalizedString(@"Button_Cancel")
                                             style:UIAlertActionStyleCancel
                                           handler:nil]];
    UIPopoverPresentationController *popover = list.popoverPresentationController;
    if (popover) {
        popover.sourceView = self.view;
        popover.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds),
                                        CGRectGetMidY(self.view.bounds), 1, 1);
    }
    [self presentViewController:list animated:YES completion:nil];
}

- (void)refreshJailbreakAppsPressed
{
    [[DOEnvironmentManager sharedManager] refreshJailbreakApps];
}

- (void)lowPowerSchedulePressed
{
    [self.navigationController pushViewController:[DOLowPowerScheduleController new] animated:YES];
}

- (void)reinstallPackageManagersPressed
{
    [self.navigationController pushViewController:[[DOPkgManagerPickerViewController alloc] init] animated:YES];
}

- (void)supporterLicensePressed
{
    DORHPresentSupporterLicense(self);
}

- (void)changeMobilePasswordWithAuthenticationPressed
{
	LAContext *context = [[LAContext alloc] init];
	NSError *authError = nil;
	NSString *reason = DOLocalizedString(@"Password_Auth_Required");

	if ([context canEvaluatePolicy:LAPolicyDeviceOwnerAuthentication error:&authError]) {
		[context evaluatePolicy:LAPolicyDeviceOwnerAuthentication
			localizedReason:reason
			reply:^(BOOL success, NSError * _Nullable error) {
			dispatch_async(dispatch_get_main_queue(), ^{
				if (success) {
					[self changeMobilePassword];
				}
			});
		}];
	}
	else {
		[self changeMobilePassword];
	}
}

- (void)changeMobilePassword
{
    UIAlertController *changeMobilePasswordAlert = [UIAlertController alertControllerWithTitle:DOLocalizedString(@"Button_Change_Mobile_Password") message:DOLocalizedString(@"Alert_Change_Mobile_Password_Body") preferredStyle:UIAlertControllerStyleAlert];

    [changeMobilePasswordAlert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = DOLocalizedString(@"Password_Placeholder");
        textField.secureTextEntry = YES;
    }];

    [changeMobilePasswordAlert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = DOLocalizedString(@"Repeat_Password_Placeholder");
        textField.secureTextEntry = YES;
    }];

    UIAlertAction *changeButton = [UIAlertAction actionWithTitle:DOLocalizedString(@"Button_Change") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action){
        NSString *password = changeMobilePasswordAlert.textFields[0].text;
        NSString *repeatPassword = changeMobilePasswordAlert.textFields[1].text;
        if (![password isEqualToString:repeatPassword]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self changeMobilePassword];
            });
        }
        else {
            [[DOEnvironmentManager sharedManager] changeMobilePassword:password];
        }
    }];
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:DOLocalizedString(@"Button_Cancel") style:UIAlertActionStyleCancel handler:nil];
    [changeMobilePasswordAlert addAction:changeButton];
    [changeMobilePasswordAlert addAction:cancelAction];
    [self presentViewController:changeMobilePasswordAlert animated:YES completion:nil];
}

/*
- (void)hideUnhideJailbreakPressed
{
    DOEnvironmentManager *envManager = [DOEnvironmentManager sharedManager];
    [envManager setJailbreakHidden:!envManager.isJailbreakHidden];
    [self reloadSpecifiers];
}
*/

- (void)removeJailbreakPressed
{
    UIAlertController *confirmationAlertController = [UIAlertController alertControllerWithTitle:DOLocalizedString(@"Alert_Remove_Jailbreak_Title") message:DOLocalizedString(@"Alert_Remove_Jailbreak_Pressed_Body") preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *uninstallAction = [UIAlertAction actionWithTitle:DOLocalizedString(@"Button_Continue") style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        [[DOEnvironmentManager sharedManager] deleteBootstrap];
        if ([DOEnvironmentManager sharedManager].isJailbroken) {
            [[DOEnvironmentManager sharedManager] reboot];
        }
        else {
            if (gSystemInfo.jailbreakInfo.rootPath) {
                free(gSystemInfo.jailbreakInfo.rootPath);
                gSystemInfo.jailbreakInfo.rootPath = NULL;
                [[DOEnvironmentManager sharedManager] locateJailbreakRoot];
            }
            [self reloadSpecifiers];
        }
    }];
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:DOLocalizedString(@"Button_Cancel") style:UIAlertActionStyleDefault handler:nil];
    [confirmationAlertController addAction:uninstallAction];
    [confirmationAlertController addAction:cancelAction];
    [self presentViewController:confirmationAlertController animated:YES completion:nil];
}

- (void)resetSettingsPressed
{
    [[DOUIManager sharedInstance] resetSettings];
    [self.navigationController popToRootViewControllerAnimated:YES];
    [self reloadSpecifiers];
}

- (id)readDyldPatchEnabled:(PSSpecifier *)specifier
{
    DOEnvironmentManager *envManager = [DOEnvironmentManager sharedManager];
    if (envManager.isJailbroken) {
        return @(jbclient_dyld_patch_enabled());
    }
    return [self readPreferenceValue:specifier];
}

- (void)setDyldPatchEnabled:(id)value specifier:(PSSpecifier *)specifier
{
    DOEnvironmentManager *envManager = [DOEnvironmentManager sharedManager];

    bool enable = ((NSNumber *)value).boolValue;

    void (^confirmAction)(void) = ^{

        if (!envManager.isJailbroken) {

            [self setPreferenceValue:value specifier:specifier];
            return;
        }

        UIAlertController *userspaceRebootAlertController = [UIAlertController alertControllerWithTitle:DOLocalizedString(@"Alert_Tweak_Injection_Toggled_Title") message:DOLocalizedString(@"Alert_Tweak_Injection_Toggled_Body") preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction *rebootNowAction = [UIAlertAction actionWithTitle:DOLocalizedString(@"Menu_Reboot_Userspace_Title") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            if(jbclient_set_dyld_patch(enable) == 0) {
                [self setPreferenceValue:value specifier:specifier];
                [[DOEnvironmentManager sharedManager] rebootUserspace];
            } else {
                [self reloadSpecifiers];
            }
        }];
        UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:DOLocalizedString(@"Button_Cancel") style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
            [self reloadSpecifiers];
        }];

        [userspaceRebootAlertController addAction:cancelAction];
        [userspaceRebootAlertController addAction:rebootNowAction];
        [self presentViewController:userspaceRebootAlertController animated:YES completion:nil];
    };

    confirmAction();
}

@end
