//
//  DOHeaderView.m
//  Dopamine
//
//  Created by tomt000 on 04/01/2024.
//

#import "DOHeaderView.h"
#import "DOThemeManager.h"

@interface DOHeaderView ()

@property (nonatomic) UIImageView *logoView;
@property (nonatomic) UIStackView *subtitleStack;
@property (nonatomic) UILabel *informationTitleLabel;
@property (nonatomic) NSLayoutConstraint *logoHeightConstraint;
@property (nonatomic) NSMutableArray<NSLayoutConstraint *> *subtitleWidthConstraints;
@property (nonatomic) UIStackView *glassSubtitleStack;

@end

@implementation DOHeaderView

// 创建标志与统一对齐的紧凑信息列。
-(id)initWithImage:(UIImage *)image subtitles:(NSArray<NSAttributedString *> *)subtitles {
    if (self = [super init]) {
        self.subtitleWidthConstraints = [NSMutableArray array];
        UIStackView *stackView = [[UIStackView alloc] init];
        stackView.axis = UILayoutConstraintAxisVertical;
        stackView.spacing = 2;
        stackView.translatesAutoresizingMaskIntoConstraints = NO;
        stackView.alignment = UIStackViewAlignmentLeading;
        self.subtitleStack = stackView;

        [self addSubview:stackView];

        [NSLayoutConstraint activateConstraints:@[
            [stackView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [stackView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [stackView.topAnchor constraintEqualToAnchor:self.topAnchor],
            [stackView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        ]];

        //1 - Add the logo to our stack
        self.logoView = [[UIImageView alloc] init];
        self.logoView.translatesAutoresizingMaskIntoConstraints = NO;
        self.logoView.image = [image imageWithAlignmentRectInsets:UIEdgeInsetsMake(7, 0, -7, 0)];
        [stackView addArrangedSubview:self.logoView];

        self.logoHeightConstraint = [self.logoView.heightAnchor constraintEqualToConstant:40];
        [NSLayoutConstraint activateConstraints:@[
            self.logoHeightConstraint,
            [self.logoView.widthAnchor constraintEqualToAnchor:self.logoView.heightAnchor multiplier:image.size.width / image.size.height],
        ]];

        //3 - Add our subtitles to our stack
        [subtitles enumerateObjectsUsingBlock:^(NSAttributedString *formatedText, NSUInteger idx, BOOL *stop) {
            [self addSubtitle:formatedText];
        }];

        self.translatesAutoresizingMaskIntoConstraints = NO;

        DOTheme *theme = [[DOThemeManager sharedInstance] enabledTheme];
        if (theme.titleShadow)
        {
            self.layer.shadowColor = [UIColor blackColor].CGColor;
            self.layer.shadowOffset = CGSizeZero;
            self.layer.shadowRadius = 30;
            self.layer.shadowOpacity = 0.3;
        }

    }
    return self;
}

// 新增可刷新的信息行，与作者行左对齐并按可用宽度换行。
- (UILabel *)addSubtitle:(NSAttributedString *)subtitle
{
    UILabel *label = [[UILabel alloc] init];
    label.attributedText = subtitle;
    label.numberOfLines = 0;
    label.textAlignment = NSTextAlignmentLeft;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [self.subtitleStack addArrangedSubview:label];
    NSLayoutConstraint *width = [label.widthAnchor constraintEqualToAnchor:self.subtitleStack.widthAnchor];
    width.active = YES;
    [self.subtitleWidthConstraints addObject:width];
    return label;
}

// 标题共用列宽，内容使用剩余宽度并与标题的首行基线对齐。
- (UILabel *)addInformationRowWithTitle:(NSAttributedString *)title
{
    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.attributedText = title;
    titleLabel.textAlignment = NSTextAlignmentLeft;
    [titleLabel setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [titleLabel setContentHuggingPriority:UILayoutPriorityDefaultHigh forAxis:UILayoutConstraintAxisHorizontal];

    UILabel *valueLabel = [[UILabel alloc] init];
    valueLabel.numberOfLines = 0;
    valueLabel.textAlignment = NSTextAlignmentLeft;

    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[titleLabel, valueLabel]];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.alignment = UIStackViewAlignmentFirstBaseline;
    row.spacing = 4;
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [self.subtitleStack addArrangedSubview:row];
    [row.widthAnchor constraintEqualToAnchor:self.subtitleStack.widthAnchor].active = YES;

    if (self.informationTitleLabel) {
        [titleLabel.widthAnchor constraintEqualToAnchor:self.informationTitleLabel.widthAnchor].active = YES;
    } else {
        self.informationTitleLabel = titleLabel;
    }
    return valueLabel;
}

- (void)applyGlassLayoutWithLogoHeight:(CGFloat)height subtitleScale:(CGFloat)scale
{
    self.logoHeightConstraint.constant = height;
    if (self.glassSubtitleStack) return;

    // RC9 centers the logo and a compact, left-aligned three-line information
    // block separately. Natural label widths keep the block centered as uptime
    // grows, while the maximum width permits wrapping on a narrow screen.
    [NSLayoutConstraint deactivateConstraints:self.subtitleWidthConstraints];
    [self.subtitleWidthConstraints removeAllObjects];
    self.subtitleStack.alignment = UIStackViewAlignmentCenter;
    self.subtitleStack.spacing = 2.0;

    UIStackView *information = [[UIStackView alloc] init];
    information.axis = UILayoutConstraintAxisVertical;
    information.alignment = UIStackViewAlignmentFill;
    information.spacing = 2.0;
    information.translatesAutoresizingMaskIntoConstraints = NO;
    NSUInteger index = 0;
    for (UIView *view in self.subtitleStack.arrangedSubviews.copy) {
        if (![view isKindOfClass:UILabel.class])
            continue;
        UILabel *label = (UILabel *)view;
        UIFont *originalFont = label.attributedText.length ?
            [label.attributedText attribute:NSFontAttributeName atIndex:0 effectiveRange:NULL] : label.font;
        UIFont *font = [(originalFont ?: [UIFont systemFontOfSize:14.0])
            fontWithSize:(originalFont ? originalFont.pointSize : 14.0) * scale];
        UIColor *color = [UIColor colorWithWhite:1.0 alpha:(index == 0 ? 1.0 : 0.8)];
        NSString *text = label.text ?: @"";
        label.attributedText = nil;
        label.font = font;
        label.textColor = color;
        label.text = text;
        label.textAlignment = NSTextAlignmentLeft;
        [self.subtitleStack removeArrangedSubview:label];
        [label removeFromSuperview];
        [information addArrangedSubview:label];
        index++;
    }
    [self.subtitleStack addArrangedSubview:information];
    [information.widthAnchor constraintLessThanOrEqualToAnchor:self.subtitleStack.widthAnchor].active = YES;
    self.glassSubtitleStack = information;
}

@end
