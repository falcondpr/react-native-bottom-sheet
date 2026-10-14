#include <react/renderer/components/ReactNativeBottomSheetSpec/ComponentDescriptors.h>
#include <react/renderer/components/ReactNativeBottomSheetSpec/PortalPublicationSource.h>
#include <react/renderer/components/ReactNativeBottomSheetSpec/PortalContextGraph.h>
#include <react/renderer/components/view/ViewComponentDescriptor.h>
#include <iostream>

using namespace facebook::react;
using namespace facebook::react::bottomsheet;
using Children = std::vector<std::shared_ptr<const ShadowNode>>;

namespace {
struct Fixture {
  std::shared_ptr<ContextContainer> context = std::make_shared<ContextContainer>();
  std::shared_ptr<UIManager> manager = std::make_shared<UIManager>(RuntimeExecutor{}, context);
  ViewComponentDescriptor views{{.eventDispatcher = {}, .contextContainer = context, .flavor = nullptr}};
  BottomSheetViewComponentDescriptor sheets{{.eventDispatcher = {}, .contextContainer = context, .flavor = nullptr}};
  std::unique_ptr<PortalPublicationSource> source = std::make_unique<PortalPublicationSource>(manager);
  std::vector<SurfaceId> surfaces;

  std::shared_ptr<const ShadowNode> make(Tag tag, bool concrete, const char* position,
                         Children children = {}, bool sheet = false, bool host = false,
                         SurfaceId surface = 1) {
    const ComponentDescriptor& descriptor = sheet ? static_cast<const ComponentDescriptor&>(sheets) : views;
    folly::dynamic raw = folly::dynamic::object("collapsable", !concrete)
        ("position", position)("width", 300)("height", 560);
    if (host) raw["nativeID"] = PortalHostNativeID;
    auto props = descriptor.cloneProps(PropsParserContext(surface, *context), nullptr, RawProps(raw));
    auto family = descriptor.createFamily({.tag = tag, .surfaceId = surface, .instanceHandle = nullptr});
    auto state = descriptor.createInitialState(props, family);
    if (sheet) {
      auto geometry = std::make_shared<BottomSheetViewState>();
      geometry->contentOffsetY = 39;
      geometry->frameSize = {300, 560};
      geometry->contentRegionInset = 24;
      state = std::make_shared<const BottomSheetViewShadowNode::ConcreteState>(geometry, *state);
    }
    return descriptor.createShadowNode({.props = props,
        .children = std::make_shared<const Children>(std::move(children)), .state = state}, family);
  }

  ShadowTree& tree(SurfaceId surface = 1) {
    auto owned = std::make_unique<ShadowTree>(surface,
        LayoutConstraints{.minimumSize = {800, 600}, .maximumSize = {800, 600}},
        LayoutContext{}, *manager, *context);
    auto& result = *owned;
    manager->getShadowTreeRegistry().add(std::move(owned));
    surfaces.push_back(surface);
    return result;
  }

  MountingTransaction commit(ShadowTree& tree, Children children) {
    auto status = tree.commit([&](const RootShadowNode& root) {
      return std::static_pointer_cast<RootShadowNode>(root.ShadowNode::clone(
          {.children = std::make_shared<const Children>(std::move(children))}));
    }, {});
    if (status != ShadowTreeCommitStatus::Succeeded) std::abort();
    auto transaction = tree.getMountingCoordinator()->pullTransaction(true);
    if (!transaction) std::abort();
    return std::move(*transaction);
  }

  ~Fixture() {
    source.reset();
    if (manager) {
      for (auto surface : surfaces) manager->getShadowTreeRegistry().remove(surface);
    }
  }
};

State::Shared delivered(const MountingTransaction& transaction, Tag tag) {
  State::Shared result;
  for (const auto& mutation : transaction.getMutations()) {
    if (mutation.newChildShadowView.tag == tag && mutation.newChildShadowView.state) {
      result = mutation.newChildShadowView.state;
    }
  }
  return result;
}

const BottomSheetViewState& data(const State::Shared& state) {
  return std::static_pointer_cast<const BottomSheetViewShadowNode::ConcreteState>(state)->getData();
}

class LaterLayoutHook final : public UIManagerCommitHook {
 public:
  bool relative = false;
  State::Shared restoredState;
  const ViewComponentDescriptor& descriptor;
  const ContextContainer& context;
  LaterLayoutHook(const ViewComponentDescriptor& descriptor, const ContextContainer& context)
      : descriptor(descriptor), context(context) {}
  void commitHookWasRegistered(const UIManager&) noexcept override {}
  void commitHookWasUnregistered(const UIManager&) noexcept override {}
  RootShadowNode::Unshared shadowTreeWillCommit(const ShadowTree&,
      const RootShadowNode::Shared&, const RootShadowNode::Unshared& root) noexcept override {
    if (!relative) return root;
    const auto& wrapper = *indexPortalShadowNodes(*root)->at(31);
    auto props = descriptor.cloneProps(PropsParserContext(1, context), wrapper.getProps(),
        RawProps(folly::dynamic::object("position", "relative")));
    auto result = std::static_pointer_cast<RootShadowNode>(root->cloneTree(wrapper.getFamily(),
        [&](const ShadowNode& node) { return node.clone({.props = props}); }));
    if (restoredState) {
      const auto& sheet = *indexPortalShadowNodes(*result)->at(14);
      result = std::static_pointer_cast<RootShadowNode>(result->cloneTree(sheet.getFamily(),
          [&](const ShadowNode& node) { return node.clone({.state = restoredState}); }));
    }
    return result;
  }
};
} // namespace

int main() {
  int tests = 0;
  int failures = 0;
  auto expect = [&](const char* name, bool valid) {
    ++tests;
    failures += !valid;
    std::cout << (valid ? "PASS " : "FAIL ") << name << '\n';
  };

  {
    Fixture f;
    auto& tree = f.tree();
    auto sheet = f.make(14, true, "relative", {}, true);
    auto host = f.make(13, true, "absolute", {sheet}, false, true);
    auto area = f.make(11, false, "relative", {f.make(12, true, "relative"), host});
    auto mutation = f.commit(tree, {area});
    auto native = delivered(mutation, 14);
    auto root = f.source->rootForState(1, 14, native);
    expect("a delivered BottomSheet state identifies its exact source and preserves native geometry",
           native && !data(native).portalPublicationId.empty() &&
           data(native).contentOffsetY == 39 && data(native).frameSize == facebook::react::Size{300, 560} &&
           data(native).contentRegionInset == 24 &&
           root == tree.getCurrentRevision().rootShadowNode && root &&
           discoverPortalContexts(*root)->hostContexts.at(13) == 11);
  }

  {
    Fixture f;
    auto& tree = f.tree();
    auto sheet = f.make(14, true, "relative", {}, true);
    auto host = f.make(13, true, "absolute", {sheet}, false, true);
    auto wrapper = f.make(31, false, "static", {host});
    auto area = f.make(11, false, "relative", {wrapper});
    LaterLayoutHook later(f.views, *f.context);
    f.manager->registerCommitHook(later);
    auto first = delivered(f.commit(tree, {area}), 14);
    auto firstRoot = tree.getCurrentRevision().rootShadowNode;
    later.relative = true;
    auto second = delivered(f.commit(tree, {area}), 14);
    auto secondRoot = tree.getCurrentRevision().rootShadowNode;
    auto third = delivered(f.commit(tree, tree.getCurrentRevision().rootShadowNode->getChildren()), 14);
    auto old = f.source->rootForState(1, 14, first);
    auto delayed = f.source->rootForState(1, 14, second);
    expect("delayed states recover final containing blocks after later hooks and a newer commit",
           third && second && first && first != second && second != third &&
           old == firstRoot && delayed == secondRoot && old && delayed &&
           discoverPortalContexts(*old)->hostContexts.at(13) == 11 &&
           discoverPortalContexts(*delayed)->hostContexts.at(13) == 31 &&
           indexPortalShadowNodes(*old)->at(14)->getProps() ==
               indexPortalShadowNodes(*delayed)->at(14)->getProps());
    f.manager->unregisterCommitHook(later);
  }

  {
    Fixture f;
    auto& tree = f.tree();
    auto host = f.make(13, true, "absolute", {f.make(14, true, "relative", {}, true)}, false, true);
    auto first = delivered(f.commit(tree, {f.make(11, false, "relative", {host})}), 14);
    std::weak_ptr<const RootShadowNode> retired = tree.getCurrentRevision().rootShadowNode;
    State::Shared previous;
    State::Shared latest;
    for (int i = 0; i < 40; ++i) {
      previous = latest;
      latest = delivered(f.commit(tree, tree.getCurrentRevision().rootShadowNode->getChildren()), 14);
    }
    expect("finite source history releases old roots and rejects evicted states while recent states remain available",
           retired.expired() && !f.source->rootForState(1, 14, first) &&
           f.source->rootForState(1, 14, previous) &&
           f.source->rootForState(1, 14, latest) == tree.getCurrentRevision().rootShadowNode);
  }

  {
    Fixture f;
    auto& tree = f.tree();
    auto host = f.make(13, true, "absolute", {f.make(14, true, "relative", {}, true)}, false, true);
    auto area = f.make(11, false, "relative", {f.make(31, false, "static", {host})});
    LaterLayoutHook later(f.views, *f.context);
    f.manager->registerCommitHook(later);
    auto first = delivered(f.commit(tree, {area}), 14);
    later.relative = true;
    later.restoredState = first;
    f.commit(tree, {area});
    expect("a later hook reusing one state in distinct final roots makes that source ambiguous",
           !f.source->rootForState(1, 14, first));
    f.manager->unregisterCommitHook(later);
  }

  {
    Fixture f;
    auto& firstTree = f.tree();
    auto areaA = f.make(11, false, "relative", {
        f.make(13, true, "absolute", {f.make(14, true, "relative", {}, true)}, false, true)});
    auto areaB = f.make(21, false, "relative", {
        f.make(23, true, "absolute", {f.make(24, true, "relative", {}, true)}, false, true)});
    auto firstMount = f.commit(firstTree, {areaA, areaB});
    auto a = delivered(firstMount, 14);
    auto b = delivered(firstMount, 24);
    auto firstRoot = firstTree.getCurrentRevision().rootShadowNode;
    auto& secondTree = f.tree(2);
    auto secondArea = f.make(111, false, "relative", {
        f.make(113, true, "absolute", {f.make(114, true, "relative", {}, true, false, 2)}, false, true, 2)}, false, false, 2);
    auto other = delivered(f.commit(secondTree, {secondArea}), 114);
    auto copiedData = std::make_shared<BottomSheetViewState>(data(a));
    auto forged = std::make_shared<const BottomSheetViewShadowNode::ConcreteState>(copiedData, *a);
    auto graph = discoverPortalContexts(*firstRoot);
    expect("all owners share one source per root while surfaces and exact state identities remain separate",
           a && b && other && data(a).portalPublicationId == data(b).portalPublicationId &&
           data(a).portalPublicationId != data(other).portalPublicationId &&
           f.source->rootForState(1, 14, a) == firstRoot &&
           f.source->rootForState(1, 24, b) == firstRoot &&
           f.source->rootForState(2, 114, other) == secondTree.getCurrentRevision().rootShadowNode &&
           !f.source->rootForState(2, 14, a) && !f.source->rootForState(1, 14, b) &&
           !f.source->rootForState(1, 14, forged) && !f.source->rootForState(1, 14, nullptr) &&
           graph->hostContexts.at(13) == 11 && graph->hostContexts.at(23) == 21);
    f.manager->getShadowTreeRegistry().remove(1);
    f.surfaces.erase(f.surfaces.begin());
    expect("stopping one surface rejects its old source while the other surface remains available",
           !f.source->rootForState(1, 14, a) &&
           f.source->rootForState(2, 114, other) == secondTree.getCurrentRevision().rootShadowNode);
  }

  {
    Fixture f;
    auto& tree = f.tree();
    auto oldSheet = f.make(14, true, "relative", {}, true);
    auto first = delivered(f.commit(tree, {oldSheet}), 14);
    auto firstFamily = indexPortalShadowNodes(*tree.getCurrentRevision().rootShadowNode)->at(14)->getFamilyShared();
    f.commit(tree, {});
    auto second = delivered(f.commit(tree, {f.make(14, true, "relative", {}, true)}), 14);
    auto secondRoot = f.source->rootForState(1, 14, second);
    expect("a recycled tag belongs to its new family and cannot identify the earlier state as current",
           secondRoot == tree.getCurrentRevision().rootShadowNode &&
           indexPortalShadowNodes(*secondRoot)->at(14)->getFamilyShared() != firstFamily &&
           f.source->rootForState(1, 14, first) != secondRoot && first != second);
    f.source.reset();
    auto before = tree.getCurrentRevision().rootShadowNode;
    auto children = before->getChildren();
    children.push_back(f.make(99, true, "relative"));
    f.commit(tree, children);
    expect("destroying the source unregisters its hook before another commit",
           indexPortalShadowNodes(*tree.getCurrentRevision().rootShadowNode)->at(14)->getState() == second);
    f.source = std::make_unique<PortalPublicationSource>(f.manager);
    expect("a fresh source rejects the prior source namespace",
           !f.source->rootForState(1, 14, second));
    auto fresh = delivered(f.commit(tree, tree.getCurrentRevision().rootShadowNode->getChildren()), 14);
    expect("the fresh source supplies a distinct identity for the same live family",
           fresh && data(fresh).portalPublicationId != data(second).portalPublicationId &&
           f.source->rootForState(1, 14, fresh) == tree.getCurrentRevision().rootShadowNode);
    std::weak_ptr<UIManager> runtime = f.manager;
    f.manager->getShadowTreeRegistry().remove(1);
    f.surfaces.clear();
    f.manager.reset();
    expect("the source does not retain its runtime and rejects reads after runtime destruction",
           runtime.expired() && !f.source->rootForState(1, 14, fresh));
  }

  {
    Fixture f;
    auto& tree = f.tree();
    auto host = f.make(13, true, "absolute", {f.make(14, true, "relative", {}, true)}, false, true);
    auto area = f.make(11, false, "relative", {f.make(31, false, "static", {host})});
    LaterLayoutHook later(f.views, *f.context);
    f.manager->registerCommitHook(later);
    auto first = delivered(f.commit(tree, {area}), 14);
    std::weak_ptr<const RootShadowNode> original = tree.getCurrentRevision().rootShadowNode;
    for (int i = 0; i < 40; ++i) {
      f.commit(tree, tree.getCurrentRevision().rootShadowNode->getChildren());
    }
    later.relative = true;
    later.restoredState = first;
    f.commit(tree, {area});
    expect("restoring an old state after history eviction cannot assign it to a different final root",
           original.expired() && !f.source->rootForState(1, 14, first));
    f.manager->unregisterCommitHook(later);
  }

  {
    Fixture f;
    f.source.reset();
    auto& tree = f.tree();
    auto sheet = f.make(14, true, "relative", {}, true);
    auto first = delivered(f.commit(tree, {sheet}), 14);
    f.source = std::make_unique<PortalPublicationSource>(f.manager);
    f.source->bootstrap();
    auto transaction = tree.getMountingCoordinator()->pullTransaction(true);
    auto stamped = transaction ? delivered(*transaction, 14) : nullptr;
    expect("source installation bootstraps an already mounted sheet through a new native state mutation",
           data(first).portalPublicationId.empty() && stamped && stamped != first &&
           !data(stamped).portalPublicationId.empty() && data(stamped).contentOffsetY == 39 &&
           data(stamped).frameSize == facebook::react::Size{300, 560} && data(stamped).contentRegionInset == 24 &&
           f.source->rootForState(1, 14, stamped) == tree.getCurrentRevision().rootShadowNode);
  }

  std::cout << "STATE RESULT tests=" << tests << " failures=" << failures << '\n';
  return failures ? 1 : 0;
}
