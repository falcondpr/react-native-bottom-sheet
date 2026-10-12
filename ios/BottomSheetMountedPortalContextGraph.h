#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "BottomSheetNativeViewDeletion.h"

#include "../common/cpp/react/renderer/components/ReactNativeBottomSheetSpec/PortalContextGraph.h"
#include <react/renderer/components/root/RootShadowNode.h>
#include <react/renderer/mounting/ShadowViewMutation.h>

@class RCTMountingManager;

NS_ASSUME_NONNULL_BEGIN

/**
 * One surface's completed native membership. Runtime ownership supplies the
 * current manager/coordinator/transaction and window eligibility; this module
 * binds created native instances to families and projects read-only cuts.
 */
@interface BottomSheetMountedPortalContextGraph : NSObject

- (instancetype)initWithMountingManager:(RCTMountingManager *)manager NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (void)publishRoot:(const std::shared_ptr<const facebook::react::RootShadowNode> &)root
          mutations:(const facebook::react::ShadowViewMutation::List &)mutations;

/** nil rejects stale identity or unsupported native ancestry; never broadens scope. */
- (nullable NSSet<UIView *> *)hiddenBranchesForRoot:
    (const std::shared_ptr<const facebook::react::RootShadowNode> &)root
                                    retainedPaths:
    (const std::vector<facebook::react::bottomsheet::PortalRetainedPaths> &)requests;

- (void)invalidate;

// A current consecutive mounting transaction may retire these exact instances
// before Delete. Any stale binding rejects the entire batch, without mutations.
- (nullable BottomSheetNativeViewDeletion *)nativeDeletionForMutations:
    (const facebook::react::ShadowViewMutation::List &)mutations;

@end

NS_ASSUME_NONNULL_END
