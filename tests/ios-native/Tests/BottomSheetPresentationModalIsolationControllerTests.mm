#import <UIKit/UIKit.h>
#import <XCTest/XCTest.h>

#import "../../../ios/BottomSheetPresentationOwnership.h"

@interface BottomSheetModalBoundaryRecordingView : UIView

- (instancetype)initWithName:(NSString *)name
                     writeLog:(NSMutableArray<NSString *> *)writeLog;

@property (nonatomic, copy) NSString *name;
@property (nonatomic, strong) NSMutableArray<NSString *> *writeLog;
@property (nonatomic, copy, nullable) void (^afterWrite)(BOOL modal);

@end

@implementation BottomSheetModalBoundaryRecordingView

- (instancetype)initWithName:(NSString *)name
                     writeLog:(NSMutableArray<NSString *> *)writeLog
{
  if (self = [super initWithFrame:CGRectZero]) {
    _name = [name copy];
    _writeLog = writeLog;
  }
  return self;
}

- (void)setAccessibilityViewIsModal:(BOOL)accessibilityViewIsModal
{
  [self.writeLog addObject:[NSString stringWithFormat:
                                       @"%@:%@",
                                       self.name,
                                       accessibilityViewIsModal ? @"true" : @"false"]];
  [super setAccessibilityViewIsModal:accessibilityViewIsModal];
  if (self.afterWrite != nil) {
    self.afterWrite(accessibilityViewIsModal);
  }
}

@end

static UIWindow *BottomSheetMakeModalIsolationTestWindow(void)
{
  UIWindow *window = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 390, 844)];
  window.rootViewController = [UIViewController new];
  window.hidden = NO;
  return window;
}

static BottomSheetPresentationController *BottomSheetActivateModalBoundary(
    UIView *boundary,
    BottomSheetPresentationMode mode)
{
  BottomSheetPresentationController *controller =
      [[BottomSheetPresentationController alloc] initWithAnchor:boundary];
  [controller updateModal:YES active:YES mode:mode];
  return controller;
}

static void BottomSheetTearDownModalIsolationTestWindow(UIWindow *window)
{
  window.hidden = YES;
  window.rootViewController = nil;
}

@interface BottomSheetPresentationModalIsolationControllerTests : XCTestCase
@end

@implementation BottomSheetPresentationModalIsolationControllerTests

- (void)testTopTransferEnablesNewBoundaryBeforeDisablingOldBoundary
{
  NSMutableArray<NSString *> *writeLog = [NSMutableArray new];
  UIWindow *window = BottomSheetMakeModalIsolationTestWindow();
  BottomSheetModalBoundaryRecordingView *lower =
      [[BottomSheetModalBoundaryRecordingView alloc] initWithName:@"lower" writeLog:writeLog];
  BottomSheetModalBoundaryRecordingView *upper =
      [[BottomSheetModalBoundaryRecordingView alloc] initWithName:@"upper" writeLog:writeLog];
  [window.rootViewController.view addSubview:lower];
  [window.rootViewController.view addSubview:upper];
  BottomSheetPresentationController *lowerController =
      BottomSheetActivateModalBoundary(lower, BottomSheetPresentationModePortal);
  [writeLog removeAllObjects];

  BottomSheetPresentationController *upperController =
      BottomSheetActivateModalBoundary(upper, BottomSheetPresentationModePortal);

  XCTAssertEqualObjects(writeLog, (@[ @"upper:true", @"lower:false" ]));
  XCTAssertFalse(lower.accessibilityViewIsModal);
  XCTAssertTrue(upper.accessibilityViewIsModal);

  [upperController invalidate];
  [lowerController invalidate];
  BottomSheetTearDownModalIsolationTestWindow(window);
}

- (void)testNestedDescendantIsTheOnlyModalBoundary
{
  NSMutableArray<NSString *> *writeLog = [NSMutableArray new];
  UIWindow *window = BottomSheetMakeModalIsolationTestWindow();
  BottomSheetModalBoundaryRecordingView *ancestor =
      [[BottomSheetModalBoundaryRecordingView alloc] initWithName:@"ancestor" writeLog:writeLog];
  BottomSheetModalBoundaryRecordingView *descendant =
      [[BottomSheetModalBoundaryRecordingView alloc] initWithName:@"descendant" writeLog:writeLog];
  [window.rootViewController.view addSubview:ancestor];
  [ancestor addSubview:descendant];
  BottomSheetPresentationController *ancestorController =
      BottomSheetActivateModalBoundary(ancestor, BottomSheetPresentationModePortal);
  BottomSheetPresentationController *descendantController =
      BottomSheetActivateModalBoundary(descendant, BottomSheetPresentationModePortal);

  XCTAssertFalse(ancestor.accessibilityViewIsModal);
  XCTAssertTrue(descendant.accessibilityViewIsModal);

  [descendantController invalidate];
  [ancestorController invalidate];
  BottomSheetTearDownModalIsolationTestWindow(window);
}

- (void)testNoTopClearsEveryRegisteredBoundary
{
  NSMutableArray<NSString *> *writeLog = [NSMutableArray new];
  UIWindow *window = BottomSheetMakeModalIsolationTestWindow();
  BottomSheetModalBoundaryRecordingView *boundary =
      [[BottomSheetModalBoundaryRecordingView alloc] initWithName:@"boundary" writeLog:writeLog];
  [window.rootViewController.view addSubview:boundary];
  BottomSheetPresentationController *controller =
      BottomSheetActivateModalBoundary(boundary, BottomSheetPresentationModePortal);

  [controller updateModal:YES active:NO mode:BottomSheetPresentationModePortal];

  XCTAssertFalse(boundary.accessibilityViewIsModal);

  [controller invalidate];
  BottomSheetTearDownModalIsolationTestWindow(window);
}

- (void)testDifferentWindowsReconcileModalBoundariesIndependently
{
  NSMutableArray<NSString *> *writeLog = [NSMutableArray new];
  UIWindow *firstWindow = BottomSheetMakeModalIsolationTestWindow();
  UIWindow *secondWindow = BottomSheetMakeModalIsolationTestWindow();
  BottomSheetModalBoundaryRecordingView *firstBoundary =
      [[BottomSheetModalBoundaryRecordingView alloc] initWithName:@"first" writeLog:writeLog];
  BottomSheetModalBoundaryRecordingView *secondBoundary =
      [[BottomSheetModalBoundaryRecordingView alloc] initWithName:@"second" writeLog:writeLog];
  [firstWindow.rootViewController.view addSubview:firstBoundary];
  [secondWindow.rootViewController.view addSubview:secondBoundary];
  BottomSheetPresentationController *firstController =
      BottomSheetActivateModalBoundary(firstBoundary, BottomSheetPresentationModePortal);
  BottomSheetPresentationController *secondController =
      BottomSheetActivateModalBoundary(secondBoundary, BottomSheetPresentationModeNativeOverlay);

  [firstController updateModal:YES active:NO mode:BottomSheetPresentationModePortal];

  XCTAssertFalse(firstBoundary.accessibilityViewIsModal);
  XCTAssertTrue(secondBoundary.accessibilityViewIsModal);

  [secondController invalidate];
  [firstController invalidate];
  BottomSheetTearDownModalIsolationTestWindow(secondWindow);
  BottomSheetTearDownModalIsolationTestWindow(firstWindow);
}

- (void)testRemovingLowerBoundaryDoesNotReleaseCurrentTopBoundary
{
  NSMutableArray<NSString *> *writeLog = [NSMutableArray new];
  UIWindow *window = BottomSheetMakeModalIsolationTestWindow();
  BottomSheetModalBoundaryRecordingView *lower =
      [[BottomSheetModalBoundaryRecordingView alloc] initWithName:@"lower" writeLog:writeLog];
  BottomSheetModalBoundaryRecordingView *upper =
      [[BottomSheetModalBoundaryRecordingView alloc] initWithName:@"upper" writeLog:writeLog];
  [window.rootViewController.view addSubview:lower];
  [window.rootViewController.view addSubview:upper];
  BottomSheetPresentationController *lowerController =
      BottomSheetActivateModalBoundary(lower, BottomSheetPresentationModePortal);
  BottomSheetPresentationController *upperController =
      BottomSheetActivateModalBoundary(upper, BottomSheetPresentationModePortal);
  [writeLog removeAllObjects];

  [lowerController invalidate];

  XCTAssertEqualObjects(writeLog, (@[]));
  XCTAssertFalse(lower.accessibilityViewIsModal);
  XCTAssertTrue(upper.accessibilityViewIsModal);

  [upperController invalidate];
  BottomSheetTearDownModalIsolationTestWindow(window);
}

- (void)testReentrantBoundaryWriteRerunsReconciliationBeforeReturning
{
  NSMutableArray<NSString *> *writeLog = [NSMutableArray new];
  UIWindow *window = BottomSheetMakeModalIsolationTestWindow();
  BottomSheetModalBoundaryRecordingView *lower =
      [[BottomSheetModalBoundaryRecordingView alloc] initWithName:@"lower" writeLog:writeLog];
  BottomSheetModalBoundaryRecordingView *upper =
      [[BottomSheetModalBoundaryRecordingView alloc] initWithName:@"upper" writeLog:writeLog];
  [window.rootViewController.view addSubview:lower];
  [window.rootViewController.view addSubview:upper];
  BottomSheetPresentationController *lowerController =
      BottomSheetActivateModalBoundary(lower, BottomSheetPresentationModePortal);
  [writeLog removeAllObjects];
  __block BOOL didReenter = NO;
  upper.afterWrite = ^(BOOL modal) {
    if (modal && !didReenter) {
      didReenter = YES;
      [lowerController reconcilePresentationOrder];
    }
  };

  BottomSheetPresentationController *upperController =
      BottomSheetActivateModalBoundary(upper, BottomSheetPresentationModePortal);

  XCTAssertTrue(didReenter);
  XCTAssertEqualObjects(writeLog, (@[ @"upper:true", @"lower:false" ]));
  XCTAssertFalse(lower.accessibilityViewIsModal);
  XCTAssertTrue(upper.accessibilityViewIsModal);

  upper.afterWrite = nil;
  [upperController invalidate];
  [lowerController invalidate];
  BottomSheetTearDownModalIsolationTestWindow(window);
}

- (void)testReentrantNewTopRemovalRestoresSuccessorBeforeClearingReleasedBoundary
{
  NSMutableArray<NSString *> *writeLog = [NSMutableArray new];
  UIWindow *window = BottomSheetMakeModalIsolationTestWindow();
  BottomSheetModalBoundaryRecordingView *lower =
      [[BottomSheetModalBoundaryRecordingView alloc] initWithName:@"lower" writeLog:writeLog];
  BottomSheetModalBoundaryRecordingView *upper =
      [[BottomSheetModalBoundaryRecordingView alloc] initWithName:@"upper" writeLog:writeLog];
  [window.rootViewController.view addSubview:lower];
  [window.rootViewController.view addSubview:upper];
  BottomSheetPresentationController *lowerController =
      BottomSheetActivateModalBoundary(lower, BottomSheetPresentationModePortal);
  BottomSheetPresentationController *upperController =
      [[BottomSheetPresentationController alloc] initWithAnchor:upper];
  __block BOOL didRemoveNewTop = NO;
  upper.afterWrite = ^(BOOL modal) {
    if (modal && !didRemoveNewTop) {
      didRemoveNewTop = YES;
      [upperController invalidate];
    }
  };
  [writeLog removeAllObjects];

  [upperController updateModal:YES active:YES mode:BottomSheetPresentationModePortal];

  XCTAssertTrue(didRemoveNewTop);
  XCTAssertEqualObjects(
      writeLog,
      (@[ @"upper:true", @"lower:false", @"lower:true", @"upper:false" ]));
  XCTAssertTrue(lower.accessibilityViewIsModal);
  XCTAssertFalse(upper.accessibilityViewIsModal);

  upper.afterWrite = nil;
  [lowerController invalidate];
  BottomSheetTearDownModalIsolationTestWindow(window);
}

- (void)testIdempotentReconciliationRepairsOnlyDriftedPrivateBoundary
{
  NSMutableArray<NSString *> *writeLog = [NSMutableArray new];
  UIWindow *window = BottomSheetMakeModalIsolationTestWindow();
  BottomSheetModalBoundaryRecordingView *lower =
      [[BottomSheetModalBoundaryRecordingView alloc] initWithName:@"lower" writeLog:writeLog];
  BottomSheetModalBoundaryRecordingView *upper =
      [[BottomSheetModalBoundaryRecordingView alloc] initWithName:@"upper" writeLog:writeLog];
  [window.rootViewController.view addSubview:lower];
  [window.rootViewController.view addSubview:upper];
  BottomSheetPresentationController *lowerController =
      BottomSheetActivateModalBoundary(lower, BottomSheetPresentationModePortal);
  BottomSheetPresentationController *upperController =
      BottomSheetActivateModalBoundary(upper, BottomSheetPresentationModePortal);
  lower.accessibilityViewIsModal = YES;
  [writeLog removeAllObjects];

  [upperController reconcilePresentationOrder];

  XCTAssertEqualObjects(writeLog, (@[ @"lower:false" ]));
  XCTAssertFalse(lower.accessibilityViewIsModal);
  XCTAssertTrue(upper.accessibilityViewIsModal);

  [upperController invalidate];
  [lowerController invalidate];
  BottomSheetTearDownModalIsolationTestWindow(window);
}

@end
