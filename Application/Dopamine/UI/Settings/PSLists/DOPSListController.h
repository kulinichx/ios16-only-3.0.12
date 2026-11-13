//
//  DOPSListController.h
//  Dopamine
//
//  Created by tomt000 on 26/01/2024.
//

#import <UIKit/UIKit.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>


NS_ASSUME_NONNULL_BEGIN

@interface DOPSListController : PSListController

+ (void)setupViewControllerStyle:(UIViewController*)vc;

// Full-screen pages keep Preferences' table geometry and reserve their chrome
// with content insets instead of resizing the table after its own layout pass.
- (BOOL)preferencesUsesNativeTableLayout;

@end

NS_ASSUME_NONNULL_END
