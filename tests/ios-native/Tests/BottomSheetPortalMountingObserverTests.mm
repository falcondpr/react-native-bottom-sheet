#import <XCTest/XCTest.h>
#import <React/RCTComponentViewRegistry.h>
#import <React/RCTMountingManager.h>
#import <React/RCTViewComponentView.h>
#import "../../../ios/BottomSheetPortalMountingObserver.h"
#import "../../../ios/BottomSheetAccessibilityMaskLedger.h"
#import "../../../ios/BottomSheetPortalIsolation.h"
#include <react/renderer/components/view/ViewComponentDescriptor.h>
#include <react/renderer/mounting/Differentiator.h>

using namespace facebook::react;
using namespace facebook::react::bottomsheet;

namespace {
using Children = std::vector<std::shared_ptr<const ShadowNode>>;
struct RuntimeFixture {
  std::shared_ptr<const ContextContainer> context = std::make_shared<ContextContainer>();
  std::shared_ptr<UIManager> uiManager = std::make_shared<UIManager>(RuntimeExecutor{}, context);
  ViewComponentDescriptor descriptor{{.eventDispatcher = {}, .contextContainer = context,
                                      .flavor = nullptr}};
  ShadowTree *tree;
  RCTMountingManager *__strong mountingManager = [RCTMountingManager new];
  UIView *__strong viewport = [UIView new];

  RuntimeFixture() {
    auto ownedTree = std::make_unique<ShadowTree>(1,
        LayoutConstraints{.minimumSize = {800, 600}, .maximumSize = {800, 600}},
        LayoutContext{}, *uiManager, *context);
    tree = ownedTree.get();
    uiManager->getShadowTreeRegistry().add(std::move(ownedTree));
    [mountingManager.componentViewRegistry.componentViewFactory
        registerComponentViewClass:RCTViewComponentView.class];
    [mountingManager attachSurfaceToView:viewport surfaceId:1];
  }
  ~RuntimeFixture() {
    [mountingManager detachSurfaceFromView:viewport surfaceId:1];
    uiManager->getShadowTreeRegistry().remove(1);
  }

  std::shared_ptr<ViewShadowNode> node(Tag tag, Children children = {}, bool host = false) {
    folly::dynamic raw = folly::dynamic::object("collapsable", false)
        ("position", "absolute")("width", 300)("height", 210);
    if (host) raw["nativeID"] = PortalHostNativeID;
    auto props = descriptor.cloneProps(PropsParserContext(1, *context), nullptr,
                                       RawProps(std::move(raw)));
    auto family = descriptor.createFamily({.tag = tag, .surfaceId = 1, .instanceHandle = nullptr});
    return std::static_pointer_cast<ViewShadowNode>(descriptor.createShadowNode(
        {.props = props, .children = std::make_shared<const Children>(std::move(children))}, family));
  }
  RootShadowNode::Shared mount(Children children) {
    tree->commit([&](const RootShadowNode& current) {
      return std::static_pointer_cast<RootShadowNode>(current.ShadowNode::clone(
          {.children = std::make_shared<const Children>(std::move(children))}));
    }, {});
    [mountingManager scheduleTransaction:tree->getMountingCoordinator()];
    return tree->getMountingCoordinator()->getBaseRevision().rootShadowNode;
  }
  BottomSheetPortalMountingObserver *observer() {
    std::weak_ptr<UIManager> current = uiManager;
    return [[BottomSheetPortalMountingObserver alloc] initWithMountingManager:mountingManager
        uiManagerProvider:^{ return current.lock(); } beforeDeletingNativeSubtrees:nil];
  }
  UIView *view(Tag tag) {
    return [mountingManager.componentViewRegistry findComponentViewWithTag:tag];
  }
};
} // namespace

@interface BottomSheetPortalMountingObserverTests : XCTestCase
@end
@implementation BottomSheetPortalMountingObserverTests

- (void)testFirstOwnCompletedMountBootstrapsTheCurrentAppliedRoot
{
  RuntimeFixture fixture;
  auto sheet = fixture.node(14);
  auto host = fixture.node(13, {sheet}, true);
  auto root = fixture.mount({fixture.node(2), fixture.node(11, {fixture.node(12), host})});
  auto observer = fixture.observer();
  // The first own component can be created after willMount notifications.
  MountingTransaction first(1, 1, {}, {});
  [observer didMount:first owner:fixture.view(14)];
  std::vector<PortalRetainedPaths> paths{{&host->getFamily(), {&sheet->getFamily()}}};

  XCTAssertTrue([observer currentRootForSurface:1] == root);
  XCTAssertEqualObjects([observer hiddenBranchesForSurface:1 retainedPaths:paths],
                       ([NSSet setWithObject:fixture.view(12)]));
}

- (void)testDuplicateObserverCannotExposeAnInFlightMountAndCompletionAddsNewBackground
{
  RuntimeFixture fixture;
  auto sheet = fixture.node(14);
  auto host = fixture.node(13, {sheet}, true);
  auto background = fixture.node(12);
  auto area = fixture.node(11, {background, host});
  auto firstRoot = fixture.mount({area});
  auto observer = fixture.observer();
  MountingTransaction first(1, 1, {}, {});
  [observer didMount:first owner:fixture.view(14)];
  MountingTransaction beginNext(1, 2, {}, {});

  [observer willMount:beginNext];
  [observer didMount:first owner:fixture.view(14)];
  XCTAssertFalse(bool([observer currentRootForSurface:1]));

  auto changedArea = area->clone({.children = std::make_shared<const Children>(
      Children{background, host, fixture.node(16)})});
  auto nextRoot = fixture.mount({changedArea});
  auto mutations = calculateShadowViewMutations(*firstRoot, *nextRoot);
  MountingTransaction next(1, 2, std::move(mutations), {});
  [observer didMount:next owner:fixture.view(14)];
  std::vector<PortalRetainedPaths> paths{{&host->getFamily(), {&sheet->getFamily()}}};

  XCTAssertTrue([observer currentRootForSurface:1] == nextRoot);
  XCTAssertEqualObjects([observer hiddenBranchesForSurface:1 retainedPaths:paths],
                       ([NSSet setWithObjects:fixture.view(12), fixture.view(16), nil]));
}

- (void)testCurrentSourceOwnerResolvesOnlyItsOwnCompletedPublication
{
  RuntimeFixture fixture;
  auto root = fixture.mount({fixture.node(12), fixture.node(14)});
  auto observer = fixture.observer();
  UIView *owner = fixture.view(14);
  MountingTransaction first(1, 1, {}, {});
  [observer didMount:first owner:owner];
  UIView *foreignInstance = [UIView new];
  foreignInstance.tag = owner.tag;

  XCTAssertTrue([observer currentRootForOwner:owner] == root);
  XCTAssertFalse(bool([observer currentRootForOwner:fixture.view(12)]));
  XCTAssertFalse(bool([observer currentRootForOwner:foreignInstance]));

  MountingTransaction next(1, 2, {}, {});
  [observer willMount:next];
  XCTAssertFalse(bool([observer currentRootForOwner:owner]));
  [observer withdrawOwner:owner];
  XCTAssertFalse(bool([observer currentRootForOwner:owner]));
}

- (void)testIndependentPortalContextsRetainTheirOwnTopAndOnlyTheirLocalBackground
{
  RuntimeFixture fixture;
  auto sheetA = fixture.node(14);
  auto sheetB = fixture.node(24);
  fixture.mount({fixture.node(2),
      fixture.node(11, {fixture.node(12), fixture.node(13, {sheetA}, true)}),
      fixture.node(21, {fixture.node(22), fixture.node(23, {sheetB}, true)})});
  auto observer = fixture.observer();
  MountingTransaction first(1, 1, {}, {});
  [observer didMount:first owner:fixture.view(14)];
  [observer didMount:first owner:fixture.view(24)];
  auto identityA = [BottomSheetPresentationIdentity new];
  auto identityB = [BottomSheetPresentationIdentity new];
  NSArray *presentations = @[
    [[BottomSheetPortalPresentation alloc] initWithIdentity:identityA owner:fixture.view(14)
        observer:observer active:YES eligible:YES],
    [[BottomSheetPortalPresentation alloc] initWithIdentity:identityB owner:fixture.view(24)
        observer:observer active:YES eligible:YES]];

  auto isolation = [BottomSheetPortalIsolation projectionFromPresentations:presentations
      orderProvider:^BottomSheetPresentationOrder(BottomSheetPresentationIdentity *a,
                                                  BottomSheetPresentationIdentity *b) {
        return a == identityB ? BottomSheetPresentationOrderAbove : BottomSheetPresentationOrderBelow;
      }];

  XCTAssertNotNil(isolation);
  XCTAssertEqualObjects(isolation.hiddenBranches,
      ([NSSet setWithObjects:fixture.view(12), fixture.view(22), nil]));
  XCTAssertEqualObjects(isolation.topPresentationIdentities,
      ([NSSet setWithObjects:identityA, identityB, nil]));
  XCTAssertFalse(fixture.view(12).accessibilityElementsHidden);
}

- (void)testPortalProjectionRejectsACompletedRootChangedDuringNativeOrderResolution
{
  RuntimeFixture fixture;
  auto sheetA = fixture.node(14);
  auto sheetB = fixture.node(15);
  auto host = fixture.node(13, {sheetA, sheetB}, true);
  auto background = fixture.node(12);
  auto area = fixture.node(11, {background, host});
  auto root = fixture.mount({area});
  auto observer = fixture.observer();
  MountingTransaction first(1, 1, {}, {});
  [observer didMount:first owner:fixture.view(14)];
  [observer didMount:first owner:fixture.view(15)];
  auto identityA = [BottomSheetPresentationIdentity new];
  auto identityB = [BottomSheetPresentationIdentity new];
  NSArray *presentations = @[
    [[BottomSheetPortalPresentation alloc] initWithIdentity:identityA owner:fixture.view(14)
        observer:observer active:YES eligible:YES],
    [[BottomSheetPortalPresentation alloc] initWithIdentity:identityB owner:fixture.view(15)
        observer:observer active:YES eligible:YES]];
  RuntimeFixture *runtime = &fixture;
  __block BOOL changed = NO;

  auto isolation = [BottomSheetPortalIsolation projectionFromPresentations:presentations
      orderProvider:^BottomSheetPresentationOrder(BottomSheetPresentationIdentity *a,
                                                  BottomSheetPresentationIdentity *b) {
        if (!changed) {
          changed = YES;
          MountingTransaction begin(1, 2, {}, {});
          [observer willMount:begin];
          auto nextArea = area->clone({.children = std::make_shared<const Children>(
              Children{background, host, runtime->node(16)})});
          auto nextRoot = runtime->mount({nextArea});
          auto mutations = calculateShadowViewMutations(*root, *nextRoot);
          MountingTransaction next(1, 2, std::move(mutations), {});
          [observer didMount:next owner:runtime->view(14)];
          [observer didMount:next owner:runtime->view(15)];
        }
        return a == identityB ? BottomSheetPresentationOrderAbove : BottomSheetPresentationOrderBelow;
      }];

  XCTAssertTrue(changed);
  XCTAssertNil(isolation);
}

- (void)testSharedContainingBlockMergesHostsAndUnknownTopRetainsBothNativePaths
{
  RuntimeFixture fixture;
  fixture.mount({fixture.node(11, {fixture.node(12),
      fixture.node(13, {fixture.node(14)}, true),
      fixture.node(17, {fixture.node(18)}, true)})});
  auto observer = fixture.observer();
  MountingTransaction first(1, 1, {}, {});
  [observer didMount:first owner:fixture.view(14)];
  [observer didMount:first owner:fixture.view(18)];
  auto identityA = [BottomSheetPresentationIdentity new];
  auto identityB = [BottomSheetPresentationIdentity new];
  NSArray *presentations = @[
    [[BottomSheetPortalPresentation alloc] initWithIdentity:identityA owner:fixture.view(14)
        observer:observer active:YES eligible:YES],
    [[BottomSheetPortalPresentation alloc] initWithIdentity:identityB owner:fixture.view(18)
        observer:observer active:YES eligible:YES]];

  auto known = [BottomSheetPortalIsolation projectionFromPresentations:presentations
      orderProvider:^BottomSheetPresentationOrder(BottomSheetPresentationIdentity *a,
                                                  BottomSheetPresentationIdentity *b) {
        return a == identityB ? BottomSheetPresentationOrderAbove : BottomSheetPresentationOrderBelow;
      }];
  XCTAssertEqualObjects(known.hiddenBranches,
      ([NSSet setWithObjects:fixture.view(12), fixture.view(13), nil]));
  XCTAssertEqualObjects(known.topPresentationIdentities, [NSSet setWithObject:identityB]);

  auto unknown = [BottomSheetPortalIsolation projectionFromPresentations:presentations
      orderProvider:^BottomSheetPresentationOrder(BottomSheetPresentationIdentity *a,
                                                  BottomSheetPresentationIdentity *b) {
        return BottomSheetPresentationOrderUnknown;
      }];
  XCTAssertEqualObjects(unknown.hiddenBranches, [NSSet setWithObject:fixture.view(12)]);
  XCTAssertEqual(unknown.topPresentationIdentities.count, 0);
}

- (void)testInactiveSourcesReleaseTheCutAndWithdrawnActiveSourcesRejectIt
{
  RuntimeFixture fixture;
  fixture.mount({fixture.node(11, {fixture.node(12),
      fixture.node(13, {fixture.node(14)}, true)})});
  auto observer = fixture.observer();
  MountingTransaction first(1, 1, {}, {});
  UIView *owner = fixture.view(14);
  [observer didMount:first owner:owner];
  [observer withdrawOwner:owner];
  auto identity = [BottomSheetPresentationIdentity new];
  BottomSheetPresentationOrderProvider order = ^BottomSheetPresentationOrder(
      BottomSheetPresentationIdentity *a, BottomSheetPresentationIdentity *b) {
    return BottomSheetPresentationOrderUnknown;
  };
  auto inactive = [[BottomSheetPortalPresentation alloc] initWithIdentity:identity owner:owner
      observer:observer active:NO eligible:YES];
  auto released = [BottomSheetPortalIsolation projectionFromPresentations:@[inactive] orderProvider:order];
  XCTAssertNotNil(released);
  XCTAssertEqual(released.hiddenBranches.count, 0);
  XCTAssertEqual(released.topPresentationIdentities.count, 0);

  auto active = [[BottomSheetPortalPresentation alloc] initWithIdentity:identity owner:owner
      observer:observer active:YES eligible:YES];
  XCTAssertNil([BottomSheetPortalIsolation projectionFromPresentations:@[active] orderProvider:order]);
}

- (void)testPortalProjectionRejectsASourceWithdrawnDuringNativeOrderResolution
{
  RuntimeFixture fixture;
  fixture.mount({fixture.node(11, {fixture.node(12),
      fixture.node(13, {fixture.node(14), fixture.node(15)}, true)})});
  auto observer = fixture.observer();
  MountingTransaction first(1, 1, {}, {});
  UIView *ownerA = fixture.view(14);
  UIView *ownerB = fixture.view(15);
  [observer didMount:first owner:ownerA];
  [observer didMount:first owner:ownerB];
  auto identityA = [BottomSheetPresentationIdentity new];
  auto identityB = [BottomSheetPresentationIdentity new];
  NSArray *presentations = @[
    [[BottomSheetPortalPresentation alloc] initWithIdentity:identityA owner:ownerA
        observer:observer active:YES eligible:YES],
    [[BottomSheetPortalPresentation alloc] initWithIdentity:identityB owner:ownerB
        observer:observer active:YES eligible:YES]];

  auto isolation = [BottomSheetPortalIsolation projectionFromPresentations:presentations
      orderProvider:^BottomSheetPresentationOrder(BottomSheetPresentationIdentity *a,
                                                  BottomSheetPresentationIdentity *b) {
        [observer withdrawOwner:ownerB];
        return a == identityB ? BottomSheetPresentationOrderAbove : BottomSheetPresentationOrderBelow;
      }];

  XCTAssertNil(isolation);
}

- (void)testLastOwnObserverWithdrawalReleasesThePublicationAndCanBootstrapAgain
{
  RuntimeFixture fixture;
  auto sheetA = fixture.node(14);
  auto sheetB = fixture.node(15);
  auto host = fixture.node(13, {sheetA, sheetB}, true);
  auto root = fixture.mount({fixture.node(11, {fixture.node(12), host})});
  auto observer = fixture.observer();
  MountingTransaction first(1, 1, {}, {});
  [observer didMount:first owner:fixture.view(14)];
  [observer didMount:first owner:fixture.view(15)];

  [observer withdrawOwner:fixture.view(14)];
  XCTAssertTrue([observer currentRootForSurface:1] == root);
  [observer withdrawOwner:fixture.view(15)];
  XCTAssertFalse(bool([observer currentRootForSurface:1]));

  [observer didMount:first owner:fixture.view(15)];
  std::vector<PortalRetainedPaths> paths{{&host->getFamily(), {&sheetB->getFamily()}}};
  XCTAssertEqualObjects([observer hiddenBranchesForSurface:1 retainedPaths:paths],
                       ([NSSet setWithObjects:fixture.view(12), fixture.view(14), nil]));
}

- (void)testChangingTheCurrentUIManagerRevokesTheOldPublication
{
  RuntimeFixture fixture;
  auto root = fixture.mount({fixture.node(14)});
  __block std::weak_ptr<UIManager> current = fixture.uiManager;
  auto observer = [[BottomSheetPortalMountingObserver alloc]
      initWithMountingManager:fixture.mountingManager
      uiManagerProvider:^{ return current.lock(); } beforeDeletingNativeSubtrees:nil];
  MountingTransaction first(1, 1, {}, {});
  [observer didMount:first owner:fixture.view(14)];
  XCTAssertTrue([observer currentRootForSurface:1] == root);
  auto replacement = std::make_shared<UIManager>(RuntimeExecutor{}, fixture.context);

  current = replacement;

  XCTAssertFalse(bool([observer currentRootForSurface:1]));
  [observer didMount:first owner:fixture.view(14)];
  XCTAssertFalse(bool([observer currentRootForSurface:1]));
  [observer invalidate];
  current = fixture.uiManager;
  [observer didMount:first owner:fixture.view(14)];
  XCTAssertFalse(bool([observer currentRootForSurface:1]));
}

- (void)testReplacementCoordinatorCanRestartNumberingWithoutReusingOldFamilies
{
  RuntimeFixture fixture;
  auto oldSheet = fixture.node(14);
  auto oldHost = fixture.node(13, {oldSheet}, true);
  auto oldRoot = fixture.mount({fixture.node(11, {fixture.node(12), oldHost})});
  auto observer = fixture.observer();
  MountingTransaction first(1, 1, {}, {});
  [observer didMount:first owner:fixture.view(14)];
  fixture.mount({});
  fixture.uiManager->getShadowTreeRegistry().remove(1);
  auto tree = std::make_unique<ShadowTree>(1,
      LayoutConstraints{.minimumSize = {800, 600}, .maximumSize = {800, 600}},
      LayoutContext{}, *fixture.uiManager, *fixture.context);
  fixture.tree = tree.get();
  fixture.uiManager->getShadowTreeRegistry().add(std::move(tree));
  auto sheet = fixture.node(14);
  auto host = fixture.node(13, {sheet}, true);
  auto root = fixture.mount({fixture.node(11, {fixture.node(12), host})});
  XCTAssertFalse(bool([observer currentRootForSurface:1]));

  [observer didMount:first owner:fixture.view(14)];
  std::vector<PortalRetainedPaths> oldPaths{{&oldHost->getFamily(), {&oldSheet->getFamily()}}};
  std::vector<PortalRetainedPaths> paths{{&host->getFamily(), {&sheet->getFamily()}}};

  XCTAssertTrue([observer currentRootForSurface:1] == root);
  XCTAssertTrue(root != oldRoot);
  XCTAssertNil([observer hiddenBranchesForSurface:1 retainedPaths:oldPaths]);
  XCTAssertEqualObjects([observer hiddenBranchesForSurface:1 retainedPaths:paths],
                       ([NSSet setWithObject:fixture.view(12)]));
}

- (void)testConsecutiveWillMountRetiresTheOldMaskBeforeNativeDeletion
{
  RuntimeFixture fixture;
  auto background = fixture.node(12);
  auto sheet = fixture.node(14);
  auto host = fixture.node(13, {sheet}, true);
  auto area = fixture.node(11, {background, host});
  auto root = fixture.mount({area});
  BottomSheetAccessibilityMaskLedger *ledger = [BottomSheetAccessibilityMaskLedger new];
  UIView *otherContext = [UIView new];
  UIView *deletedView = fixture.view(12);
  [ledger reconcileHiddenBranches:[NSSet setWithObjects:deletedView, otherContext, nil]
         beforeRestoringBranches:nil];
  std::weak_ptr<UIManager> current = fixture.uiManager;
  auto observer = [[BottomSheetPortalMountingObserver alloc]
      initWithMountingManager:fixture.mountingManager
      uiManagerProvider:^{ return current.lock(); }
      beforeDeletingNativeSubtrees:^(BottomSheetNativeViewDeletion *deletion) {
        [ledger retireHiddenBranchesForDeletion:deletion];
      }];
  MountingTransaction first(1, 1, {}, {});
  [observer didMount:first owner:fixture.view(14)];
  auto nextArea = area->clone({.children = std::make_shared<const Children>(Children{host})});
  auto nextRoot = root->ShadowNode::clone({.children =
      std::make_shared<const Children>(Children{nextArea})});
  auto mutations = calculateShadowViewMutations(*root, *nextRoot);
  MountingTransaction next(1, 2, std::move(mutations), {});

  [observer willMount:next];

  XCTAssertFalse(deletedView.accessibilityElementsHidden);
  XCTAssertTrue(otherContext.accessibilityElementsHidden);
  XCTAssertFalse(bool([observer currentRootForSurface:1]));
  fixture.mount({nextArea});
  deletedView.accessibilityElementsHidden = YES;
  [ledger reconcileHiddenBranches:[NSSet set] beforeRestoringBranches:nil];
  XCTAssertTrue(deletedView.accessibilityElementsHidden);
}

- (void)testAMissedPublicationCannotRetireNativeLeasesUsingOldBindings
{
  RuntimeFixture fixture;
  auto background = fixture.node(12);
  auto sheet = fixture.node(14);
  auto host = fixture.node(13, {sheet}, true);
  auto area = fixture.node(11, {background, host});
  fixture.mount({area});
  BottomSheetAccessibilityMaskLedger *ledger = [BottomSheetAccessibilityMaskLedger new];
  UIView *backgroundView = fixture.view(12);
  [ledger reconcileHiddenBranches:[NSSet setWithObject:backgroundView]
         beforeRestoringBranches:nil];
  std::weak_ptr<UIManager> current = fixture.uiManager;
  auto observer = [[BottomSheetPortalMountingObserver alloc]
      initWithMountingManager:fixture.mountingManager
      uiManagerProvider:^{ return current.lock(); }
      beforeDeletingNativeSubtrees:^(BottomSheetNativeViewDeletion *deletion) {
        [ledger retireHiddenBranchesForDeletion:deletion];
      }];
  MountingTransaction first(1, 1, {}, {});
  [observer didMount:first owner:fixture.view(14)];
  // A real completed mount was missed. Its registry may now contain recycled
  // instances, so pre-delete retirement must not infer current leases from tags.
  auto second = fixture.mount({area, fixture.node(2)});
  auto nextArea = area->clone({.children = std::make_shared<const Children>(Children{host})});
  auto nextRoot = second->ShadowNode::clone({.children =
      std::make_shared<const Children>(Children{nextArea})});
  auto mutations = calculateShadowViewMutations(*second, *nextRoot);
  MountingTransaction gap(1, 3, std::move(mutations), {});

  [observer willMount:gap];

  XCTAssertTrue(backgroundView.accessibilityElementsHidden);
  XCTAssertFalse(bool([observer currentRootForSurface:1]));
}

- (void)testFlatteningAParentPreservesMasksOnSurvivingRegisteredAndNativeOnlyChildren
{
  RuntimeFixture fixture;
  auto background = fixture.node(12);
  auto sheet = fixture.node(14);
  auto host = fixture.node(13, {sheet}, true);
  auto area = fixture.node(11, {background, host});
  auto root = fixture.mount({area});
  UIView *backgroundView = fixture.view(12);
  UIView *nativeChild = [UIView new];
  [backgroundView addSubview:nativeChild];
  auto ledger = [BottomSheetAccessibilityMaskLedger new];
  [ledger reconcileHiddenBranches:[NSSet setWithObjects:backgroundView, nativeChild, nil]
         beforeRestoringBranches:nil];
  std::weak_ptr<UIManager> current = fixture.uiManager;
  auto observer = [[BottomSheetPortalMountingObserver alloc]
      initWithMountingManager:fixture.mountingManager
      uiManagerProvider:^{ return current.lock(); }
      beforeDeletingNativeSubtrees:^(BottomSheetNativeViewDeletion *deletion) {
        [ledger retireHiddenBranchesForDeletion:deletion];
      }];
  MountingTransaction first(1, 1, {}, {});
  [observer didMount:first owner:fixture.view(14)];
  auto props = fixture.descriptor.cloneProps(PropsParserContext(1, *fixture.context),
      area->getProps(), RawProps(folly::dynamic::object("collapsable", true)));
  auto flattened = area->clone({.props = props});
  auto nextRoot = root->ShadowNode::clone({.children =
      std::make_shared<const Children>(Children{flattened})});
  auto mutations = calculateShadowViewMutations(*root, *nextRoot);
  MountingTransaction next(1, 2, std::move(mutations), {});

  [observer willMount:next];

  XCTAssertTrue(backgroundView.accessibilityElementsHidden);
  XCTAssertTrue(nativeChild.accessibilityElementsHidden);
  fixture.mount({flattened});
  XCTAssertNil(fixture.view(11));
  XCTAssertEqual(fixture.view(12), backgroundView);
  XCTAssertTrue(backgroundView.accessibilityElementsHidden);
  XCTAssertTrue(nativeChild.accessibilityElementsHidden);
  [ledger reconcileHiddenBranches:[NSSet set] beforeRestoringBranches:nil];
  XCTAssertFalse(backgroundView.accessibilityElementsHidden);
  XCTAssertFalse(nativeChild.accessibilityElementsHidden);
}

- (void)testFlattenedBackgroundParentTransfersItsMaskToTheSurvivingNativeFrontier
{
  RuntimeFixture fixture;
  auto backgroundControl = fixture.node(16);
  auto background = fixture.node(12, {backgroundControl});
  auto sheet = fixture.node(14);
  auto host = fixture.node(13, {sheet}, true);
  auto area = fixture.node(11, {background, host});
  auto root = fixture.mount({area});
  UIView *deletedParent = fixture.view(12);
  UIView *survivingControl = fixture.view(16);
  auto ledger = [BottomSheetAccessibilityMaskLedger new];
  [ledger reconcileHiddenBranches:[NSSet setWithObject:deletedParent]
         beforeRestoringBranches:nil];
  std::weak_ptr<UIManager> current = fixture.uiManager;
  auto observer = [[BottomSheetPortalMountingObserver alloc]
      initWithMountingManager:fixture.mountingManager
      uiManagerProvider:^{ return current.lock(); }
      beforeDeletingNativeSubtrees:^(BottomSheetNativeViewDeletion *deletion) {
        [ledger retireHiddenBranchesForDeletion:deletion];
      }];
  MountingTransaction first(1, 1, {}, {});
  [observer didMount:first owner:fixture.view(14)];
  auto props = fixture.descriptor.cloneProps(PropsParserContext(1, *fixture.context),
      background->getProps(), RawProps(folly::dynamic::object("collapsable", true)));
  auto flattenedBackground = background->clone({.props = props});
  auto nextArea = area->clone({.children =
      std::make_shared<const Children>(Children{flattenedBackground, host})});
  auto nextRoot = root->ShadowNode::clone({.children =
      std::make_shared<const Children>(Children{nextArea})});
  auto mutations = calculateShadowViewMutations(*root, *nextRoot);
  MountingTransaction next(1, 2, std::move(mutations), {});

  [observer willMount:next];

  XCTAssertFalse(deletedParent.accessibilityElementsHidden);
  XCTAssertTrue(survivingControl.accessibilityElementsHidden);
  fixture.mount({nextArea});
  XCTAssertNil(fixture.view(12));
  XCTAssertEqual(fixture.view(16), survivingControl);
  XCTAssertTrue(survivingControl.accessibilityElementsHidden);
  [ledger reconcileHiddenBranches:[NSSet set] beforeRestoringBranches:nil];
  XCTAssertFalse(survivingControl.accessibilityElementsHidden);
}

@end
