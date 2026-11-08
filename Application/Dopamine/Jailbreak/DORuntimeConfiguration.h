#import <Foundation/Foundation.h>

@interface DORuntimeConfiguration : NSObject
+ (NSError *)prepare;
+ (void)restoreCustomMounts;
@end
