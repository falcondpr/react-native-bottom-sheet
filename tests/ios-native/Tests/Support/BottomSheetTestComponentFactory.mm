#import "BottomSheetTestComponentFactory.h"

#import <React/RCTComponentViewFactory.h>
#import <React/RCTComponentViewProtocol.h>
#import <React/RCTFabricComponentsPlugins.h>
#import <ReactCodegen/RCTThirdPartyComponentsProvider.h>
#import <react/renderer/components/ReactNativeBottomSheetSpec/ShadowNodes.h>

using namespace facebook::react;

@implementation BottomSheetTestComponentFactory

+ (UIView *)makeProductionComponentWithNativeOverlay:(BOOL)nativeOverlay
{
  Class<RCTComponentViewProtocol> componentClass = RCTFabricComponentsProvider("BottomSheetView");
  if (componentClass == Nil) {
    componentClass = [RCTThirdPartyComponentsProvider thirdPartyFabricComponents][@"BottomSheetView"];
  }
  NSCAssert(componentClass != Nil, @"BottomSheetView must be registered with the Fabric provider");

  RCTComponentViewFactory *factory = [RCTComponentViewFactory new];
  [factory registerComponentViewClass:componentClass];
  auto descriptor = [factory createComponentViewWithComponentHandle:BottomSheetViewShadowNode::Handle()];
  UIView<RCTComponentViewProtocol> *component = descriptor.view;

  auto props = std::make_shared<BottomSheetViewProps>();
  props->detents = {
      BottomSheetViewDetentsStruct{0, "points", false},
      BottomSheetViewDetentsStruct{320, "points", false},
  };
  props->index = 1;
  props->animateIn = false;
  props->modal = true;
  props->nativeOverlay = nativeOverlay;
  props->scrimOpacities = {0, 1};
  Props::Shared sharedProps = props;
  [component updateProps:sharedProps oldProps:component.props];
  return component;
}

+ (void)prepareForRecycle:(UIView *)component
{
  [(UIView<RCTComponentViewProtocol> *)component prepareForRecycle];
}

@end
