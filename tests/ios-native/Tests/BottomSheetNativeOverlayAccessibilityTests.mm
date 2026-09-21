#import <UIKit/UIKit.h>
#import <XCTest/XCTest.h>

#import <React/RCTComponentViewFactory.h>
#import <React/RCTFabricComponentsPlugins.h>
#import <ReactCodegen/RCTThirdPartyComponentsProvider.h>
#import "ReactNativeBottomSheet-Swift.h"
#import <react/renderer/components/ReactNativeBottomSheetSpec/ShadowNodes.h>

using namespace facebook::react;

// Forward every callback to the real adapter before observing its UIKit output.
@interface BottomSheetOverlayBoundaryRecorder : NSObject <BottomSheetHostingViewDelegate>
@property (nonatomic, weak) id<BottomSheetHostingViewDelegate> adapter;
@property (nonatomic, weak) UIView *overlay;
@property (nonatomic, strong) XCTestExpectation *settle;
@property (nonatomic) NSUInteger positionCount;
@property (nonatomic) BOOL boundaryStayedActive;
@property (nonatomic) BOOL terminalPositionWasNonModal;
@end

@implementation BottomSheetOverlayBoundaryRecorder
- (void)bottomSheetHostingView:(BottomSheetHostingView *)view didChangeIndex:(NSInteger)index
{
  [self.adapter bottomSheetHostingView:view didChangeIndex:index];
}

- (void)bottomSheetHostingView:(BottomSheetHostingView *)view didSettle:(NSInteger)index
{
  [self.adapter bottomSheetHostingView:view didSettle:index];
  XCTAssertEqual(index, 0);
  XCTAssertFalse(self.overlay.accessibilityViewIsModal);
  [self.settle fulfill];
}

- (void)bottomSheetHostingView:(BottomSheetHostingView *)view
            didChangePosition:(CGFloat)position
                        index:(CGFloat)index
{
  [self.adapter bottomSheetHostingView:view didChangePosition:position index:index];
  self.positionCount += 1;
  if (position > 0) {
    self.boundaryStayedActive &= self.overlay.accessibilityViewIsModal;
  } else {
    self.terminalPositionWasNonModal = !self.overlay.accessibilityViewIsModal;
  }
}

- (void)bottomSheetHostingView:(BottomSheetHostingView *)view didReportError:(NSString *)message
{
  [self.adapter bottomSheetHostingView:view didReportError:message];
  XCTFail(@"Production host reported an error: %@", message);
}

- (void)bottomSheetHostingViewDidLayout:(BottomSheetHostingView *)view
{
  [self.adapter bottomSheetHostingViewDidLayout:view];
}
@end

static BottomSheetHostingView *BottomSheetFindHost(UIView *view)
{
  if ([view isKindOfClass:BottomSheetHostingView.class]) {
    return (BottomSheetHostingView *)view;
  }
  for (UIView *child in view.subviews) {
    BottomSheetHostingView *host = BottomSheetFindHost(child);
    if (host != nil) {
      return host;
    }
  }
  return nil;
}

@interface BottomSheetNativeOverlayAccessibilityTests : XCTestCase
@end

@implementation BottomSheetNativeOverlayAccessibilityTests
- (void)testNativeOverlayBoundaryRemainsModalUntilRealCloseSettles
{
  XCTAssertTrue(NSThread.isMainThread);
  UIWindow *window = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 390, 844)];
  window.rootViewController = [UIViewController new];

  // Mirror RN factory lookup order: built-in provider, then Codegen's third-party map.
  Class<RCTComponentViewProtocol> componentClass =
      RCTFabricComponentsProvider("BottomSheetView");
  if (componentClass == Nil) {
    componentClass = [RCTThirdPartyComponentsProvider thirdPartyFabricComponents][@"BottomSheetView"];
  }
  XCTAssertNotNil(componentClass);
  if (componentClass == Nil) {
    return;
  }
  RCTComponentViewFactory *factory = [RCTComponentViewFactory new];
  [factory registerComponentViewClass:componentClass];
  auto descriptor = [factory createComponentViewWithComponentHandle:BottomSheetViewShadowNode::Handle()];
  UIView<RCTComponentViewProtocol> *component = descriptor.view;
  auto openProps = std::make_shared<BottomSheetViewProps>();
  openProps->detents = {
      BottomSheetViewDetentsStruct{0, "points", false},
      BottomSheetViewDetentsStruct{320, "points", false},
  };
  openProps->index = 1;
  openProps->animateIn = false;
  openProps->modal = true;
  openProps->nativeOverlay = true;
  openProps->scrimOpacities = {0, 1};
  Props::Shared sharedOpenProps = openProps;
  [component updateProps:sharedOpenProps oldProps:component.props];
  component.frame = window.bounds;
  [window.rootViewController.view addSubview:component];
  [window makeKeyAndVisible];

  @try {
    BottomSheetHostingView *host = BottomSheetFindHost(window);
    XCTAssertNotNil(host);
    if (host == nil) {
      return;
    }
    [host setNeedsLayout];
    [host layoutIfNeeded];
    UIView *overlay = host;
    while (overlay.superview != nil && overlay.superview != window) {
      overlay = overlay.superview;
    }
    XCTAssertEqual(overlay.superview, window);
    XCTAssertNotEqual(overlay, window.rootViewController.view);
    XCTAssertTrue(overlay.accessibilityViewIsModal);

    BottomSheetOverlayBoundaryRecorder *recorder = [BottomSheetOverlayBoundaryRecorder new];
    recorder.adapter = host.eventDelegate;
    XCTAssertNotNil(recorder.adapter);
    recorder.overlay = overlay;
    recorder.boundaryStayedActive = YES;
    recorder.settle = [self expectationWithDescription:@"native overlay closes through the real spring"];
    recorder.settle.assertForOverFulfill = YES;
    host.eventDelegate = recorder;

    [host setDetentIndex:0];

    XCTAssertNotNil([host.sheetContainer.layer animationForKey:@"bottomSheetSettle"]);
    XCTAssertTrue(overlay.accessibilityViewIsModal);

    [self waitForExpectations:@[recorder.settle] timeout:2];

    XCTAssertGreaterThan(recorder.positionCount, 1u);
    XCTAssertTrue(recorder.boundaryStayedActive);
    XCTAssertTrue(recorder.terminalPositionWasNonModal);
    XCTAssertFalse(overlay.accessibilityViewIsModal);
    host.eventDelegate = recorder.adapter;
  } @finally {
    [component prepareForRecycle];
    [component removeFromSuperview];
    window.hidden = YES;
    window.rootViewController = nil;
  }
}
@end
