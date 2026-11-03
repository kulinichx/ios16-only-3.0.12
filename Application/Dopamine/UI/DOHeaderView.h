//
//  DOHeaderView.h
//  Dopamine
//
//  Created by tomt000 on 04/01/2024.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface DOHeaderView : UIView

-(id)initWithImage:(UIImage *)image subtitles:(NSArray<NSAttributedString *> *)subtitles;
- (UILabel *)addSubtitle:(NSAttributedString *)subtitle;
- (UILabel *)addInformationRowWithTitle:(NSAttributedString *)title;
- (void)applyGlassLayoutWithLogoHeight:(CGFloat)height subtitleScale:(CGFloat)scale;

@end

NS_ASSUME_NONNULL_END
