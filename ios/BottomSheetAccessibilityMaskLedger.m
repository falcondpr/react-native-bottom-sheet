#import "BottomSheetAccessibilityMaskLedger.h"

@interface BottomSheetAccessibilityHiddenMutation : NSObject
@property (nonatomic) BOOL baseline;
@end

@implementation BottomSheetAccessibilityHiddenMutation
@end

@interface BottomSheetAccessibilityMaskLedger ()
@property (nonatomic, strong)
    NSMapTable<UIView *, BottomSheetAccessibilityHiddenMutation *> *mutations;
@end

@implementation BottomSheetAccessibilityMaskLedger

- (instancetype)init
{
  if (self = [super init]) {
    _mutations = [NSMapTable weakToStrongObjectsMapTable];
  }
  return self;
}

- (void)reconcileHiddenBranches:(NSSet<UIView *> *)hiddenBranches
       beforeRestoringBranches:(void (NS_NOESCAPE ^)(void))transferBoundaries
{
  NSCAssert(NSThread.isMainThread, @"Accessibility masks must be accessed on the main thread");
  for (UIView *branch in hiddenBranches) {
    BottomSheetAccessibilityHiddenMutation *mutation = [self.mutations objectForKey:branch];
    if (mutation == nil) {
      mutation = [BottomSheetAccessibilityHiddenMutation new];
      mutation.baseline = branch.accessibilityElementsHidden;
      [self.mutations setObject:mutation forKey:branch];
    }
    if (!branch.accessibilityElementsHidden) {
      branch.accessibilityElementsHidden = YES;
    }
  }
  if (transferBoundaries != nil) {
    transferBoundaries();
  }

  NSArray<UIView *> *previouslyHiddenBranches = self.mutations.keyEnumerator.allObjects;
  for (UIView *branch in previouslyHiddenBranches) {
    if ([hiddenBranches containsObject:branch]) {
      continue;
    }
    BottomSheetAccessibilityHiddenMutation *mutation = [self.mutations objectForKey:branch];
    // Preserve a later visible write and a baseline that was already hidden.
    // Remasking does not update the baseline; same-value writes are indistinguishable.
    if (mutation != nil && branch.accessibilityElementsHidden && !mutation.baseline) {
      branch.accessibilityElementsHidden = NO;
    }
    [self.mutations removeObjectForKey:branch];
  }
}

@end
