#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// Owns hidden-branch mutations, not the selection of presentation boundaries.
// Access on the main thread. New masks precede the synchronous boundary transfer
// callback; obsolete masks are restored after it returns.
@interface BottomSheetAccessibilityMaskLedger : NSObject

- (void)reconcileHiddenBranches:(NSSet<UIView *> *)hiddenBranches
       beforeRestoringBranches:(nullable void (NS_NOESCAPE ^)(void))transferBoundaries;

@end

NS_ASSUME_NONNULL_END
