#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface BottomSheetTestComponentFactory : NSObject

+ (UIView *)makeProductionComponentWithNativeOverlay:(BOOL)nativeOverlay;
+ (void)prepareForRecycle:(UIView *)component;

@end

NS_ASSUME_NONNULL_END
