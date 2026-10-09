#import <UIKit/UIKit.h>
#import <XCTest/XCTest.h>

#import "../../../ios/BottomSheetAccessibilityMaskLedger.h"

@interface BottomSheetMaskRecordingView : UIView
@property (nonatomic) NSUInteger hiddenWrites;
@property (nonatomic, copy, nullable) void (^afterWrite)(BOOL hidden);
@end

@implementation BottomSheetMaskRecordingView

- (void)setAccessibilityElementsHidden:(BOOL)hidden
{
  self.hiddenWrites++;
  [super setAccessibilityElementsHidden:hidden];
  if (self.afterWrite != nil) {
    self.afterWrite(hidden);
  }
}

@end

@interface BottomSheetAccessibilityMaskLedgerTests : XCTestCase
@end

@implementation BottomSheetAccessibilityMaskLedgerTests

- (void)testMasksTheSuppliedUnionAndLeavesOtherBranchesUntouched
{
  BottomSheetAccessibilityMaskLedger *ledger = [BottomSheetAccessibilityMaskLedger new];
  UIView *first = [UIView new];
  UIView *second = [UIView new];
  UIView *outside = [UIView new];

  [ledger reconcileHiddenBranches:[NSSet setWithObjects:first, second, nil]
         beforeRestoringBranches:^{
           XCTAssertTrue(first.accessibilityElementsHidden);
           XCTAssertTrue(second.accessibilityElementsHidden);
           XCTAssertFalse(outside.accessibilityElementsHidden);
         }];

  XCTAssertTrue(first.accessibilityElementsHidden);
  XCTAssertTrue(second.accessibilityElementsHidden);
  XCTAssertFalse(outside.accessibilityElementsHidden);
}

- (void)testReleasingOneBranchPreservesTheRemainingMask
{
  BottomSheetAccessibilityMaskLedger *ledger = [BottomSheetAccessibilityMaskLedger new];
  UIView *first = [UIView new];
  UIView *second = [UIView new];
  [ledger reconcileHiddenBranches:[NSSet setWithObjects:first, second, nil]
         beforeRestoringBranches:nil];

  [ledger reconcileHiddenBranches:[NSSet setWithObject:second]
         beforeRestoringBranches:^{
           XCTAssertTrue(first.accessibilityElementsHidden);
           XCTAssertTrue(second.accessibilityElementsHidden);
         }];

  XCTAssertFalse(first.accessibilityElementsHidden);
  XCTAssertTrue(second.accessibilityElementsHidden);
  [ledger reconcileHiddenBranches:[NSSet set] beforeRestoringBranches:nil];
  XCTAssertFalse(second.accessibilityElementsHidden);
}

- (void)testCleanupDoesNotRewriteAPreviouslyHiddenApplicationBranch
{
  BottomSheetAccessibilityMaskLedger *ledger = [BottomSheetAccessibilityMaskLedger new];
  BottomSheetMaskRecordingView *branch = [BottomSheetMaskRecordingView new];
  branch.accessibilityElementsHidden = YES;
  branch.hiddenWrites = 0;
  NSSet<UIView *> *hidden = [NSSet setWithObject:branch];

  [ledger reconcileHiddenBranches:hidden beforeRestoringBranches:nil];
  [ledger reconcileHiddenBranches:hidden beforeRestoringBranches:nil];
  [ledger reconcileHiddenBranches:[NSSet set] beforeRestoringBranches:nil];

  XCTAssertTrue(branch.accessibilityElementsHidden);
  XCTAssertEqual(branch.hiddenWrites, 0u);
}

- (void)testCleanupPreservesALaterVisibleWrite
{
  BottomSheetAccessibilityMaskLedger *ledger = [BottomSheetAccessibilityMaskLedger new];
  BottomSheetMaskRecordingView *branch = [BottomSheetMaskRecordingView new];
  [ledger reconcileHiddenBranches:[NSSet setWithObject:branch] beforeRestoringBranches:nil];
  branch.accessibilityElementsHidden = NO;
  branch.hiddenWrites = 0;

  [ledger reconcileHiddenBranches:[NSSet set] beforeRestoringBranches:nil];

  XCTAssertFalse(branch.accessibilityElementsHidden);
  XCTAssertEqual(branch.hiddenWrites, 0u);
}

- (void)testRemaskingPreservesTheOriginalHiddenBaseline
{
  BottomSheetAccessibilityMaskLedger *ledger = [BottomSheetAccessibilityMaskLedger new];
  UIView *branch = [UIView new];
  branch.accessibilityElementsHidden = YES;
  NSSet<UIView *> *hidden = [NSSet setWithObject:branch];
  [ledger reconcileHiddenBranches:hidden beforeRestoringBranches:nil];
  branch.accessibilityElementsHidden = NO;

  [ledger reconcileHiddenBranches:hidden beforeRestoringBranches:nil];
  XCTAssertTrue(branch.accessibilityElementsHidden);
  [ledger reconcileHiddenBranches:[NSSet set] beforeRestoringBranches:nil];

  // iOS preserves the initial baseline, not the latest value before remasking.
  XCTAssertTrue(branch.accessibilityElementsHidden);
}

- (void)testLedgerDoesNotRetainARemovedBranch
{
  BottomSheetAccessibilityMaskLedger *ledger = [BottomSheetAccessibilityMaskLedger new];
  __weak UIView *removed = nil;
  @autoreleasepool {
    UIView *branch = [UIView new];
    removed = branch;
    [ledger reconcileHiddenBranches:[NSSet setWithObject:branch] beforeRestoringBranches:nil];
  }

  XCTAssertNil(removed);
  [ledger reconcileHiddenBranches:[NSSet set] beforeRestoringBranches:nil];
}

- (void)testNewAndSharedMasksPrecedeBoundaryTransferAndOldMaskRestoration
{
  BottomSheetAccessibilityMaskLedger *ledger = [BottomSheetAccessibilityMaskLedger new];
  BottomSheetMaskRecordingView *oldBranch = [BottomSheetMaskRecordingView new];
  UIView *newBranch = [UIView new];
  UIView *shared = [UIView new];
  UIView *oldBoundary = [UIView new];
  UIView *newBoundary = [UIView new];
  oldBoundary.accessibilityViewIsModal = YES;
  [ledger reconcileHiddenBranches:[NSSet setWithObjects:oldBranch, shared, nil]
         beforeRestoringBranches:nil];
  __block BOOL observedRestoration = NO;
  oldBranch.afterWrite = ^(BOOL hidden) {
    if (!hidden) {
      observedRestoration = YES;
      XCTAssertTrue(newBranch.accessibilityElementsHidden);
      XCTAssertTrue(shared.accessibilityElementsHidden);
      XCTAssertTrue(newBoundary.accessibilityViewIsModal);
      XCTAssertFalse(oldBoundary.accessibilityViewIsModal);
    }
  };

  [ledger reconcileHiddenBranches:[NSSet setWithObjects:newBranch, shared, nil]
         beforeRestoringBranches:^{
           XCTAssertTrue(oldBranch.accessibilityElementsHidden);
           XCTAssertTrue(newBranch.accessibilityElementsHidden);
           XCTAssertTrue(shared.accessibilityElementsHidden);
           newBoundary.accessibilityViewIsModal = YES;
           oldBoundary.accessibilityViewIsModal = NO;
         }];

  XCTAssertTrue(observedRestoration);
  XCTAssertFalse(oldBranch.accessibilityElementsHidden);
}

@end
