#import <UIKit/UIKit.h>

// Shared schedule editor. The recording page overrides only its data and actions.
@interface DOLowPowerScheduleController : UIViewController <UITableViewDataSource, UITableViewDelegate>
@property(nonatomic, strong) UITableView *tableView;
@property(nonatomic, strong) UISwitch *enabledSwitch;
@property(nonatomic, strong) UIDatePicker *timePicker;
@property(nonatomic, strong) UIButton *saveButton;
@property(nonatomic) NSInteger lastStartMinute;
@property(nonatomic) NSInteger lastEndMinute;
@property(nonatomic) NSInteger editingTime;
@property(nonatomic) BOOL timePickerExpanded;
@property(nonatomic, copy) NSDictionary *savedConfiguration;
@property(nonatomic, copy) NSDictionary *runtimeStatus;
@property(nonatomic, strong) NSDate *queryDate;
@property(nonatomic) BOOL statusWaiting;
@property(nonatomic, copy) void (^modeSelectionHandler)(NSInteger index);
@property(nonatomic, copy) void (^backHandler)(void);
- (NSString *)scheduleTitle;
- (NSInteger)scheduleMode;
- (NSDictionary *)loadScheduleConfiguration;
- (NSDictionary *)loadRuntimeStatus;
- (const char *)scheduleStatusNotification;
- (const char *)scheduleQueryNotification;
- (BOOL)isScheduleVisible;
- (BOOL)hasChanges;
- (BOOL)statusFresh;
- (NSString *)statusText;
- (BOOL)runtimeHasError;
- (void)draftChanged;
- (void)savePressed;
- (void)backPressed;
- (void)requestStatus;
- (void)postStatusQuery;
- (void)refreshStatus;
- (void)didRefreshStatus;
- (void)didSaveConfiguration:(NSDictionary *)configuration;
- (void)showScheduleFeedback:(NSString *)message error:(BOOL)error;
- (void)showMessage:(NSString *)message;
- (void)styleScheduleCell:(UITableViewCell *)cell;
- (void)configureStatusCell:(UITableViewCell *)cell;
- (void)refreshScheduleGlassFrames;
- (void)setTimePickerExpanded:(BOOL)expanded animated:(BOOL)animated;
- (void)updateTimeLabels;
@end
