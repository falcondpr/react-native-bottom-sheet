#import "BottomSheetPresentationPolicy.h"
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, BottomSheetPresentationMode) {
  BottomSheetPresentationModePortal,
  BottomSheetPresentationModeNativeOverlay,
};

@interface BottomSheetPresentationUIKitOrderResolver : NSObject

+ (BottomSheetPresentationOrder)orderOfAnchor:(UIView *)first
                                     relativeTo:(UIView *)second
                                       inWindow:(UIWindow *)window;
+ (BOOL)isAnchor:(UIView *)anchor attachedToWindow:(UIWindow *)window;

@end

@interface BottomSheetPresentationController : NSObject

- (instancetype)initWithAnchor:(UIView *)anchor NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@property (nonatomic, strong, readonly) BottomSheetPresentationIdentity *identity;
@property (nonatomic, readonly, getter=isTopPresentation) BOOL topPresentation;

- (void)updateModal:(BOOL)modal
             active:(BOOL)active
               mode:(BottomSheetPresentationMode)mode;
- (void)beginHierarchyMutation;
- (void)endHierarchyMutation;
- (void)reconcilePresentationOrder;
- (BottomSheetPresentationEscapeRoute)routeForVoiceOverEscape;
- (void)invalidate;

@end

@interface BottomSheetPresentationCoordinator : NSObject

+ (nullable BottomSheetPresentationIdentity *)topPresentationIdentityInWindow:(UIWindow *)window;

@end

NS_ASSUME_NONNULL_END
