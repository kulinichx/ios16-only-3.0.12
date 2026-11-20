#import "DOBatteryRecordController.h"
#import "DOScheduleTimePicker.h"
#import "DOEnvironmentManager.h"
#import "DOUIManager.h"
#import "../../../../BaseBin/roothidehooks/src/RCBatteryRecord.h"
#include <notify.h>

@interface DOBatteryRecordController () <UITableViewDataSource, UITableViewDelegate>
@property(nonatomic, strong) UITableView *table;
@property(nonatomic, strong) UISwitch *enabled;
@property(nonatomic, strong) UISwitch *repeat;
@property(nonatomic, strong) NSMutableDictionary *draft;
@property(nonatomic, strong) NSDictionary *saved;
@property(nonatomic, strong) NSDictionary *status;
@property(nonatomic, strong) NSMutableArray<NSDictionary *> *comparison;
@property(nonatomic, strong) UIDatePicker *picker;
@property(nonatomic, copy) NSString *editingKey;
@property(nonatomic, copy) NSString *pendingCommand;
@property(nonatomic, strong) NSDate *queryDate;
@property(nonatomic) BOOL waiting;
@property(nonatomic) int statusToken;
@end

@implementation DOBatteryRecordController
- (void)viewDidLoad
{
    [super viewDidLoad];
    self.statusToken = -1;
    self.title = DOLocalizedString(@"BatteryRecord_Title");
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.view.backgroundColor = UIColor.clearColor;
    self.saved = [DOEnvironmentManager.sharedManager batteryRecordConfiguration];
    self.draft = [self.saved mutableCopy];
    self.comparison = [NSMutableArray new];
    self.enabled = [UISwitch new]; self.enabled.on = [self.draft[@"Enabled"] boolValue];
    self.repeat = [UISwitch new]; self.repeat.on = [self.draft[@"Repeat"] boolValue];
    [self.enabled addTarget:self action:@selector(switchChanged) forControlEvents:UIControlEventValueChanged];
    [self.repeat addTarget:self action:@selector(switchChanged) forControlEvents:UIControlEventValueChanged];
    self.table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.table.translatesAutoresizingMaskIntoConstraints = NO;
    self.table.backgroundColor = UIColor.clearColor;
    self.table.dataSource = self; self.table.delegate = self;
    self.table.rowHeight = UITableViewAutomaticDimension; self.table.estimatedRowHeight = 64;
    UIButton *back = [UIButton buttonWithType:UIButtonTypeSystem];
    [back setImage:[UIImage systemImageNamed:@"chevron.left"] forState:UIControlStateNormal];
    back.accessibilityLabel = DOLocalizedString(@"Button_Cancel");
    [back addTarget:self action:@selector(backPressed) forControlEvents:UIControlEventTouchUpInside];
    UIButton *save = [UIButton buttonWithType:UIButtonTypeSystem];
    [save setTitle:DOLocalizedString(@"LowPowerSchedule_Save") forState:UIControlStateNormal];
    [save addTarget:self action:@selector(savePressed) forControlEvents:UIControlEventTouchUpInside];
    UILabel *title = [UILabel new]; title.text = self.title;
    title.textColor = UIColor.labelColor; title.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    title.numberOfLines = 2; title.textAlignment = NSTextAlignmentCenter;
    for (UIView *view in @[back, title, save, self.table]) { view.translatesAutoresizingMaskIntoConstraints = NO; [self.view addSubview:view]; }
    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [back.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:10],
        [back.topAnchor constraintEqualToAnchor:safe.topAnchor constant:6],
        [back.widthAnchor constraintEqualToConstant:44], [back.heightAnchor constraintEqualToConstant:44],
        [save.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-14],
        [save.topAnchor constraintEqualToAnchor:back.topAnchor], [save.heightAnchor constraintEqualToConstant:44],
        [save.widthAnchor constraintGreaterThanOrEqualToConstant:60],
        [title.leadingAnchor constraintEqualToAnchor:back.trailingAnchor constant:8],
        [title.trailingAnchor constraintEqualToAnchor:save.leadingAnchor constant:-8],
        [title.topAnchor constraintEqualToAnchor:back.topAnchor], [title.heightAnchor constraintGreaterThanOrEqualToConstant:44],
        [self.table.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:8],
        [self.table.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],
        [self.table.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor],
        [self.table.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor]
    ]];
    __weak typeof(self) weakSelf = self;
    int token = -1;
    if (notify_register_dispatch(RC_BATTERY_STATUS, &token, dispatch_get_main_queue(), ^(int value) {
        if (weakSelf.viewIfLoaded.window && weakSelf.navigationController.topViewController == weakSelf) [weakSelf refreshStatus];
    }) == NOTIFY_STATUS_OK) self.statusToken = token;
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(applicationDidBecomeActive:) name:UIApplicationDidBecomeActiveNotification object:nil];
}

- (void)viewDidAppear:(BOOL)animated { [super viewDidAppear:animated]; [self requestStatus]; }
- (void)applicationDidBecomeActive:(NSNotification *)notification { [self requestStatus]; }
- (void)dealloc
{
    if (self.isViewLoaded && self.statusToken >= 0) notify_cancel(self.statusToken);
    [NSNotificationCenter.defaultCenter removeObserver:self];
}
- (void)switchChanged { self.draft[@"Enabled"] = @(self.enabled.on); self.draft[@"Repeat"] = @(self.repeat.on); }
- (void)message:(NSString *)text
{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:self.title message:text preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:DOLocalizedString(@"Supporter_OK") style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)backPressed
{
    if ([self.draft isEqual:self.saved]) { [self.navigationController popViewControllerAnimated:YES]; return; }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:self.title message:DOLocalizedString(@"LowPowerSchedule_Discard") preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:DOLocalizedString(@"Button_Cancel") style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:DOLocalizedString(@"LowPowerSchedule_DiscardButton") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) { [self.navigationController popViewControllerAnimated:YES]; }]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)savePressed
{
    if ([self.draft[@"StartMinute"] isEqual:self.draft[@"EndMinute"]]) { [self message:DOLocalizedString(@"LowPowerSchedule_SameTime")]; return; }
    if ([self.status[@"Active"][@"Source"] isEqual:@"scheduled"]) { [self message:DOLocalizedString(@"BatteryRecord_StopBeforeEdit")]; return; }
    NSMutableDictionary *configuration = [self.draft mutableCopy];
    configuration[@"Revision"] = NSUUID.UUID.UUIDString;
    NSDate *start = rcLowPowerDateForMinute([configuration[@"StartMinute"] integerValue], NSDate.date, rcLowPowerLocalCalendar(), YES);
    if (!start) { [self message:DOLocalizedString(@"LowPowerSchedule_RuntimeFailed")]; return; }
    configuration[@"FirstStart"] = start;
    NSError *error = nil;
    if (![DOEnvironmentManager.sharedManager saveBatteryRecordConfiguration:configuration error:&error]) { [self message:error.localizedDescription ?: DOLocalizedString(@"LowPowerSchedule_RuntimeFailed")]; return; }
    self.saved = configuration; self.draft = [configuration mutableCopy];
    [self requestStatus];
}
- (void)requestStatus
{
    if (!self.viewIfLoaded.window || self.navigationController.topViewController != self) return;
    if (self.queryDate && -self.queryDate.timeIntervalSinceNow > 60) self.pendingCommand = nil;
    self.queryDate = NSDate.date; self.waiting = YES;
    notify_post(RC_BATTERY_QUERY);
    [self refreshStatus];
    NSDate *query = self.queryDate;
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if ([weakSelf.queryDate isEqual:query] && weakSelf.viewIfLoaded.window &&
            UIApplication.sharedApplication.applicationState == UIApplicationStateActive) {
            weakSelf.waiting = NO; [weakSelf refreshStatus];
        }
    });
}
- (BOOL)statusFresh
{
    NSDate *date = self.status[@"Updated"];
    return [date isKindOfClass:NSDate.class] && [date timeIntervalSinceDate:self.queryDate] >= -0.5 &&
        [self.status[@"Revision"] isEqual:self.saved[@"Revision"]];
}
- (void)refreshStatus
{
    self.status = [DOEnvironmentManager.sharedManager batteryRecordStatus];
    if ([self statusFresh]) self.waiting = NO;
    if (self.pendingCommand && [self.status[@"CommandID"] isEqual:self.pendingCommand]) {
        NSString *result = self.status[@"CommandResult"];
        self.pendingCommand = nil;
        if (![@[@"started", @"stopped"] containsObject:result])
            [self message:DOLocalizedString([@"BatteryRecord_Result_" stringByAppendingString:result ?: @"sampleFailed"])];
    }
    [self.table reloadData];
}
- (NSString *)dateText:(id)value
{
    if (![value isKindOfClass:NSDate.class]) return @"—";
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.dateStyle = NSDateFormatterShortStyle; formatter.timeStyle = NSDateFormatterMediumStyle;
    return [formatter stringFromDate:value];
}
- (NSString *)pointText:(NSDictionary *)point
{
    if (![point isKindOfClass:NSDictionary.class]) return DOLocalizedString(@"Unknown");
    NSInteger thermal = [point[@"Thermal"] integerValue];
    NSArray *keys = @[@"Thermal_State_Nominal", @"Thermal_State_Fair", @"Thermal_State_Serious", @"Thermal_State_Critical"];
    NSString *heat = DOLocalizedString(thermal >= 0 && thermal < 4 ? keys[thermal] : @"Unknown");
    NSString *power = DOLocalizedString([point[@"LowPower"] boolValue] ? @"BatteryRecord_LPMOn" : @"BatteryRecord_LPMOff");
    NSString *charge = DOLocalizedString([point[@"BatteryState"] integerValue] == 1 ? @"BatteryRecord_Unplugged" : @"BatteryRecord_Charging");
    return [NSString stringWithFormat:@"%@ · %@%% · %@ · %@ · %@", [self dateText:point[@"Date"]], point[@"Level"] ?: @"—", power, charge, heat];
}
- (NSString *)recordText:(NSDictionary *)record
{
    NSString *result = DOLocalizedString([@"BatteryRecord_Result_" stringByAppendingString:record[@"Result"] ?: @"interrupted"]);
    NSMutableString *text = [NSMutableString stringWithFormat:@"%@\n%@\n%@", result, [self pointText:record[@"Start"]], [self pointText:record[@"End"]]];
    if (record[@"PlannedStart"]) [text appendFormat:@"\n%@: %@ → %@", DOLocalizedString(@"BatteryRecord_Planned"), [self dateText:record[@"PlannedStart"]], [self dateText:record[@"PlannedEnd"]]];
    NSNumber *rate = rcBatteryDropRate(record);
    if (rate) {
        double drop = [record[@"Start"][@"Level"] doubleValue] - [record[@"End"][@"Level"] doubleValue];
        double hours = ([record[@"End"][@"Continuous"] doubleValue] - [record[@"Start"][@"Continuous"] doubleValue]) / 3600;
        [text appendFormat:@"\n%@", [NSString stringWithFormat:DOLocalizedString(@"BatteryRecord_Rate"), hours, drop, rate.doubleValue]];
    } else [text appendFormat:@"\n%@", DOLocalizedString(@"BatteryRecord_NoRate")];
    return text;
}
- (NSString *)statusText
{
    if (self.pendingCommand || ![self statusFresh]) return DOLocalizedString(self.waiting ? @"BatteryRecord_Waiting" : @"BatteryRecord_Unavailable");
    NSString *state = self.status[@"State"] ?: @"idle";
    NSString *text = DOLocalizedString([@"BatteryRecord_State_" stringByAppendingString:state]);
    if ([state isEqual:@"recording"]) return [text stringByAppendingFormat:@"\n%@", [self pointText:self.status[@"Active"][@"Start"]]];
    if ([state isEqual:@"scheduled"]) return [text stringByAppendingFormat:@"\n%@", [self dateText:self.status[@"NextStart"]]];
    if ([self.status[@"Completed"] boolValue]) return DOLocalizedString(@"BatteryRecord_OnceFinished");
    return text;
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 3; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return section == 0 ? 5 : section == 1 ? 2 : MAX(1, [self.status[@"History"] count]);
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    return DOLocalizedString(section == 0 ? @"BatteryRecord_Plan" : section == 1 ? @"LowPowerSchedule_Status" : @"BatteryRecord_History");
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    return DOLocalizedString(section == 0 ? @"BatteryRecord_PlanFooter" : section == 1 ? @"BatteryRecord_EndpointFooter" : @"BatteryRecord_CompareFooter");
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.backgroundColor = [UIColor.secondarySystemGroupedBackgroundColor colorWithAlphaComponent:0.82];
    cell.textLabel.numberOfLines = 0; cell.detailTextLabel.numberOfLines = 0;
    cell.textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    cell.textLabel.adjustsFontForContentSizeCategory = YES;
    cell.detailTextLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    cell.detailTextLabel.adjustsFontForContentSizeCategory = YES;
    if (indexPath.section == 0) {
        NSArray *keys = @[@"BatteryRecord_Enable", @"BatteryRecord_StartTime", @"BatteryRecord_EndTime", @"BatteryRecord_Repeat", @"BatteryRecord_Copy"];
        cell.textLabel.text = DOLocalizedString(keys[indexPath.row]);
        if (indexPath.row == 0) cell.accessoryView = self.enabled;
        else if (indexPath.row == 3) cell.accessoryView = self.repeat;
        else if (indexPath.row < 3) {
            NSInteger minute = [self.draft[indexPath.row == 1 ? @"StartMinute" : @"EndMinute"] integerValue];
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%02ld:%02ld", (long)minute / 60, (long)minute % 60];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        }
    } else if (indexPath.section == 1) {
        cell.textLabel.text = indexPath.row == 0 ? [self statusText] : DOLocalizedString(self.status[@"Active"] ? @"BatteryRecord_Stop" : @"BatteryRecord_Start");
        cell.userInteractionEnabled = indexPath.row == 0 || (!self.pendingCommand && [self statusFresh]);
        if (indexPath.row == 1 && !cell.userInteractionEnabled) cell.textLabel.textColor = UIColor.secondaryLabelColor;
    } else {
        NSArray *history = self.status[@"History"];
        if (!history.count) cell.textLabel.text = DOLocalizedString(@"BatteryRecord_Empty");
        else {
            NSDictionary *record = history[indexPath.row];
            cell.textLabel.text = [self dateText:record[@"Start"][@"Date"] ?: record[@"PlannedStart"] ?: record[@"Recorded"]];
            cell.detailTextLabel.text = [self recordText:record];
            if ([self.comparison containsObject:record]) cell.accessoryType = UITableViewCellAccessoryCheckmark;
        }
    }
    return cell;
}
- (void)timeChanged:(UIDatePicker *)picker { self.draft[self.editingKey] = @(DOSchedulePickerMinute(picker)); }
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 0 && (indexPath.row == 1 || indexPath.row == 2)) {
        self.editingKey = indexPath.row == 1 ? @"StartMinute" : @"EndMinute";
        UIViewController *sheet = [UIViewController new];
        sheet.view.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
        self.picker = DOScheduleTimePicker([self.draft[self.editingKey] integerValue], self, @selector(timeChanged:));
        [sheet.view addSubview:self.picker];
        UIButton *done = [UIButton buttonWithType:UIButtonTypeSystem]; done.translatesAutoresizingMaskIntoConstraints = NO;
        [done setTitle:DOLocalizedString(@"Supporter_OK") forState:UIControlStateNormal];
        [done addTarget:self action:@selector(finishTimeEditing) forControlEvents:UIControlEventTouchUpInside];
        [sheet.view addSubview:done];
        [NSLayoutConstraint activateConstraints:@[
            [self.picker.centerXAnchor constraintEqualToAnchor:sheet.view.centerXAnchor],
            [self.picker.widthAnchor constraintLessThanOrEqualToAnchor:sheet.view.widthAnchor],
            [self.picker.topAnchor constraintEqualToAnchor:sheet.view.safeAreaLayoutGuide.topAnchor constant:16],
            [done.topAnchor constraintEqualToAnchor:self.picker.bottomAnchor constant:8],
            [done.centerXAnchor constraintEqualToAnchor:sheet.view.centerXAnchor], [done.heightAnchor constraintEqualToConstant:44]
        ]];
        sheet.modalInPresentation = YES;
        sheet.sheetPresentationController.detents = @[UISheetPresentationControllerDetent.mediumDetent];
        [self presentViewController:sheet animated:YES completion:nil];
    } else if (indexPath.section == 0 && indexPath.row == 4) {
        NSDictionary *lowPower = [DOEnvironmentManager.sharedManager lowPowerScheduleConfiguration];
        self.draft[@"StartMinute"] = lowPower[@"StartMinute"]; self.draft[@"EndMinute"] = lowPower[@"EndMinute"];
        [self.table reloadData];
    } else if (indexPath.section == 1 && indexPath.row == 0) {
        [self requestStatus];
    } else if (indexPath.section == 1 && indexPath.row == 1 && !self.pendingCommand && [self statusFresh]) {
        NSError *error = nil;
        self.pendingCommand = [DOEnvironmentManager.sharedManager sendBatteryRecordCommand:self.status[@"Active"] ? @"stop" : @"start" error:&error];
        if (!self.pendingCommand) [self message:error.localizedDescription ?: DOLocalizedString(@"BatteryRecord_Unavailable")];
        [self requestStatus];
    } else if (indexPath.section == 2 && [self.status[@"History"] count]) {
        NSDictionary *record = self.status[@"History"][indexPath.row];
        if ([self.comparison containsObject:record]) [self.comparison removeObject:record];
        else [self.comparison addObject:record];
        if (self.comparison.count == 2) {
            NSString *text = [NSString stringWithFormat:@"A\n%@\n\nB\n%@\n\n%@", [self recordText:self.comparison[0]], [self recordText:self.comparison[1]], DOLocalizedString(@"BatteryRecord_EndpointFooter")];
            [self message:text]; [self.comparison removeAllObjects];
        }
        [self.table reloadData];
    }
}
- (void)finishTimeEditing { [self dismissViewControllerAnimated:YES completion:^{ [self.table reloadData]; }]; }
@end
