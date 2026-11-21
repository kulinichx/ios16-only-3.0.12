#import "DOBatteryRecordController.h"
#import "DOScheduleTimePicker.h"
#import "DOEnvironmentManager.h"
#import "DOUIManager.h"
#import "../../../../BaseBin/roothidehooks/src/RCBatteryRecord.h"

@interface DOBatteryRecordController ()
@property(nonatomic, strong) UISwitch *repeatSwitch;
@property(nonatomic, strong) NSMutableArray<NSDictionary *> *comparison;
@property(nonatomic, copy) NSString *pendingCommand;
@property(nonatomic, strong) NSDate *pendingCommandDate;
@end

@implementation DOBatteryRecordController
- (NSString *)scheduleTitle { return DOLocalizedString(@"BatteryRecord_Title"); }
- (NSInteger)scheduleMode { return 1; }
- (NSDictionary *)loadScheduleConfiguration { return [DOEnvironmentManager.sharedManager batteryRecordConfiguration]; }
- (NSDictionary *)loadRuntimeStatus { return [DOEnvironmentManager.sharedManager batteryRecordStatus]; }
- (const char *)scheduleStatusNotification { return RC_BATTERY_STATUS; }
- (BOOL)writeConfiguration:(NSDictionary *)configuration error:(NSError **)error
{
    return [DOEnvironmentManager.sharedManager saveBatteryRecordConfiguration:configuration error:error];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.repeatSwitch = [UISwitch new];
    self.repeatSwitch.on = [self.savedConfiguration[@"Repeat"] boolValue];
    [self.repeatSwitch addTarget:self action:@selector(settingsChanged) forControlEvents:UIControlEventValueChanged];
    self.comparison = [NSMutableArray new];
}

- (BOOL)hasChanges
{
    return [super hasChanges] || self.repeatSwitch.on != [self.savedConfiguration[@"Repeat"] boolValue];
}

- (void)restoreControls
{
    [super restoreControls];
    self.repeatSwitch.on = [self.savedConfiguration[@"Repeat"] boolValue];
}

- (NSString *)prepareConfiguration:(NSMutableDictionary *)configuration
{
    if (self.pendingCommand) return DOLocalizedString(@"BatteryRecord_CommandPending");
    self.runtimeStatus = [self loadRuntimeStatus];
    if ([self.runtimeStatus[@"Revision"] isEqual:self.savedConfiguration[@"Revision"]] &&
        [self.runtimeStatus[@"Active"][@"Source"] isEqual:@"scheduled"])
        return DOLocalizedString(@"BatteryRecord_StopBeforeEdit");
    NSDate *start = rcLowPowerDateForMinute(self.lastStartMinute, NSDate.date, rcLowPowerLocalCalendar(), YES);
    if (!start) return DOLocalizedString(@"LowPowerSchedule_RuntimeFailed");
    configuration[@"Repeat"] = @(self.repeatSwitch.on);
    configuration[@"FirstStart"] = start;
    return nil;
}

- (void)didRefreshStatus
{
    if (self.pendingCommand && [self.runtimeStatus[@"CommandID"] isEqual:self.pendingCommand]) {
        NSString *result = self.runtimeStatus[@"CommandResult"] ?: @"sampleFailed";
        self.pendingCommand = nil;
        self.pendingCommandDate = nil;
        BOOL success = [@[@"started", @"stopped"] containsObject:result];
        [self showScheduleFeedback:DOLocalizedString([@"BatteryRecord_Result_" stringByAppendingString:result]) error:!success];
        [[[UINotificationFeedbackGenerator alloc] init] notificationOccurred:success ? UINotificationFeedbackTypeSuccess : UINotificationFeedbackTypeWarning];
    } else if (self.pendingCommand) {
        if (-self.pendingCommandDate.timeIntervalSinceNow > 60) {
            self.pendingCommand = nil;
            self.pendingCommandDate = nil;
            [self showScheduleFeedback:DOLocalizedString(@"BatteryRecord_Result_expired") error:YES];
        } else {
            [self showScheduleFeedback:DOLocalizedString(@"BatteryRecord_CommandPending") error:NO];
        }
    }
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
    NSDictionary *status = self.runtimeStatus;
    BOOL matching = [status[@"Revision"] isEqual:self.savedConfiguration[@"Revision"]];
    if (self.statusFresh && self.runtimeHasError)
        return DOLocalizedString([@"BatteryRecord_State_" stringByAppendingString:status[@"State"]]);
    if (self.statusFresh && status[@"Active"]) {
        NSDate *end = status[@"Active"][@"PlannedEnd"];
        if ([end isKindOfClass:NSDate.class] && end.timeIntervalSinceNow <= 0)
            return [NSString stringWithFormat:DOLocalizedString(@"BatteryRecord_EndPending"), DOScheduleDateText(end)];
        NSString *text = [NSString stringWithFormat:DOLocalizedString(@"BatteryRecord_StartedAt"),
            DOScheduleDateText(status[@"Active"][@"Start"][@"Date"])];
        if (status[@"Active"][@"PlannedEnd"]) text = [text stringByAppendingFormat:@"\n%@",
            [NSString stringWithFormat:DOLocalizedString(@"BatteryRecord_EndsAt"), DOScheduleDateText(status[@"Active"][@"PlannedEnd"])]];
        return text;
    }
    if (![self.savedConfiguration[@"Enabled"] boolValue]) {
        if (self.statusFresh && [status[@"State"] isEqual:@"idle"] &&
            [status[@"RecordEndedByStop"] isEqual:self.savedConfiguration[@"DisableRequest"]])
            return DOLocalizedString(@"BatteryRecord_StoppedAndDisabled");
        if (!self.savedConfiguration[@"DisableRequest"] || (self.statusFresh && [status[@"State"] isEqual:@"idle"]))
            return DOLocalizedString(@"BatteryRecord_Paused");
        return [self unconfirmedStopText];
    }
    if (matching && !status[@"Active"] && [status[@"Completed"] boolValue]) {
        NSDictionary *last = [status[@"History"] firstObject];
        if (last) return [NSString stringWithFormat:@"%@ · %@",
            DOScheduleDateText(last[@"End"][@"Date"] ?: last[@"Recorded"]),
            DOLocalizedString([@"BatteryRecord_Result_" stringByAppendingString:last[@"Result"] ?: @"interrupted"])];
        return DOLocalizedString(@"BatteryRecord_OnceFinished");
    }
    NSDate *start = matching ? status[@"NextStart"] : nil;
    if (![start isKindOfClass:NSDate.class]) start = self.savedConfiguration[@"FirstStart"];
    if ([self.savedConfiguration[@"Repeat"] boolValue] && [start timeIntervalSinceNow] <= 0)
        start = rcLowPowerDateForMinute([self.savedConfiguration[@"StartMinute"] integerValue], NSDate.date, rcLowPowerLocalCalendar(), YES);
    NSString *key = [start timeIntervalSinceNow] > 0 ? @"BatteryRecord_PlannedAt" : @"BatteryRecord_DueAt";
    return [NSString stringWithFormat:DOLocalizedString(key), DOScheduleDateText(start)];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 3; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return section == 0 ? 6 : section == 1 ? (self.statusFresh && self.runtimeStatus[@"Active"] ? 2 : 1) : MAX(1, [self.runtimeStatus[@"History"] count]);
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    return DOLocalizedString(section == 0 ? @"BatteryRecord_Plan" : section == 1 ? @"LowPowerSchedule_Status" : @"BatteryRecord_History");
}
- (NSString *)footerTextForSection:(NSInteger)section
{
    return DOLocalizedString(section == 0 ? @"BatteryRecord_PlanFooter" : section == 1 ? @"BatteryRecord_EndpointFooter" : @"BatteryRecord_CompareFooter");
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.section == 0 && indexPath.row < 4) {
        UITableViewCell *cell = [super tableView:tableView cellForRowAtIndexPath:indexPath];
        if (indexPath.row == 0) cell.textLabel.text = DOLocalizedString(@"BatteryRecord_Enable");
        return cell;
    }
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    [self styleScheduleCell:cell];
    if (indexPath.section == 0) {
        cell.textLabel.text = DOLocalizedString(indexPath.row == 4 ? @"BatteryRecord_Repeat" : @"BatteryRecord_Copy");
        if (indexPath.row == 4) { cell.accessoryView = self.repeatSwitch; cell.selectionStyle = UITableViewCellSelectionStyleNone; }
        else { cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator; cell.accessibilityTraits |= UIAccessibilityTraitButton; }
    } else if (indexPath.section == 1 && indexPath.row == 0) {
        [self configureStatusCell:cell];
    } else if (indexPath.section == 1) {
        cell.textLabel.text = DOLocalizedString(@"BatteryRecord_Stop");
        cell.accessibilityTraits |= UIAccessibilityTraitButton;
        cell.detailTextLabel.text = self.pendingCommand ? DOLocalizedString(@"BatteryRecord_CommandPending") : nil;
    } else {
        NSArray *history = self.runtimeStatus[@"History"];
        if (!history.count) { cell.textLabel.text = DOLocalizedString(@"BatteryRecord_Empty"); cell.selectionStyle = UITableViewCellSelectionStyleNone; }
        else {
            NSDictionary *record = history[indexPath.row];
            cell.textLabel.text = [self dateText:record[@"Start"][@"Date"] ?: record[@"PlannedStart"] ?: record[@"Recorded"]];
            cell.detailTextLabel.text = [self recordText:record];
            if ([self.comparison containsObject:record]) cell.accessoryType = UITableViewCellAccessoryCheckmark;
        }
    }
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if ((indexPath.section == 0 && indexPath.row < 4) || (indexPath.section == 1 && indexPath.row == 0)) {
        [super tableView:tableView didSelectRowAtIndexPath:indexPath];
    } else if (indexPath.section == 0 && indexPath.row == 5) {
        NSDictionary *lowPower = [DOEnvironmentManager.sharedManager lowPowerScheduleConfiguration];
        if (!rcLowPowerConfigurationValid(lowPower)) lowPower = rcLowPowerDefaultConfiguration();
        self.lastStartMinute = [lowPower[@"StartMinute"] integerValue];
        self.lastEndMinute = [lowPower[@"EndMinute"] integerValue];
        [self setTimePickerExpanded:NO animated:YES];
        [self updateTimeLabels];
        if (![self applySettings]) return;
        [self showScheduleFeedback:DOLocalizedString(@"BatteryRecord_Copied") error:NO];
        [[[UISelectionFeedbackGenerator alloc] init] selectionChanged];
    } else if (indexPath.section == 1 && indexPath.row == 1) {
        if (self.pendingCommand || !self.statusFresh || !self.runtimeStatus[@"Active"]) return;
        NSError *error = nil;
        self.pendingCommand = [DOEnvironmentManager.sharedManager sendBatteryRecordCommand:@"stop" error:&error];
        if (!self.pendingCommand) { [self showMessage:error.localizedDescription ?: DOLocalizedString(@"LowPowerSchedule_RuntimeFailed")]; return; }
        self.pendingCommandDate = NSDate.date;
        [self didRefreshStatus];
        [self showScheduleFeedback:DOLocalizedString(@"BatteryRecord_CommandPending") error:NO];
    } else if (indexPath.section == 2 && [self.runtimeStatus[@"History"] count]) {
        NSDictionary *record = self.runtimeStatus[@"History"][indexPath.row];
        if ([self.comparison containsObject:record]) [self.comparison removeObject:record];
        else [self.comparison addObject:record];
        if (self.comparison.count == 2) {
            NSString *text = [NSString stringWithFormat:@"A\n%@\n\nB\n%@\n\n%@", [self recordText:self.comparison[0]], [self recordText:self.comparison[1]], DOLocalizedString(@"BatteryRecord_EndpointFooter")];
            [self showMessage:text]; [self.comparison removeAllObjects];
        }
        [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:2] withRowAnimation:UITableViewRowAnimationNone];
    }
}
@end
