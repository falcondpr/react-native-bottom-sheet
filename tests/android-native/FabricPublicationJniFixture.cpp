// Compile the real JNI resource in this test-only translation unit. Its native
// factory stays private to production; no testing entry point is added there.
#include "../../common/cpp/react/renderer/components/ReactNativeBottomSheetSpec/PortalPublicationSourceAndroid.cpp"
#include <react/renderer/components/ReactNativeBottomSheetSpec/ComponentDescriptors.h>
#include <react/renderer/components/ReactNativeBottomSheetSpec/PortalContextGraph.h>
#include <react/renderer/components/view/ViewComponentDescriptor.h>

using namespace facebook;
using namespace facebook::react;
using Children = std::vector<std::shared_ptr<const ShadowNode>>;

namespace {
class FabricPublicationJniFixture final : public jni::HybridClass<FabricPublicationJniFixture> {
 public:
  static constexpr auto kJavaDescriptor =
      "Lcom/swmansion/reactnativebottomsheet/accessibility/FabricPublicationJniFixture;";

  FabricPublicationJniFixture() {
    auto tree = std::make_unique<ShadowTree>(1,
        LayoutConstraints{.minimumSize = {800, 600}, .maximumSize = {800, 600}},
        LayoutContext{}, *manager_, *context_);
    tree_ = tree.get();
    manager_->getShadowTreeRegistry().add(std::move(tree));
    host_ = make(13, "absolute", {make(14, "relative", {}, true)}, false, true);
    commit(11);
    tree_->getMountingCoordinator()->pullTransaction(true);
  }

  ~FabricPublicationJniFixture() override {
    manager_->getShadowTreeRegistry().remove(1);
  }

  static void registerNatives() {
    registerHybrid({
        makeNativeMethod("lease", FabricPublicationJniFixture::lease),
        makeNativeMethod("takeDeliveredState", FabricPublicationJniFixture::takeDeliveredState),
        makeNativeMethod("moveHost", FabricPublicationJniFixture::moveHost),
    });
  }

 private:
  std::shared_ptr<const ShadowNode> make(Tag tag, const char* position,
      Children children = {}, bool sheet = false, bool host = false) {
    const ComponentDescriptor& descriptor = sheet
        ? static_cast<const ComponentDescriptor&>(sheets_) : views_;
    folly::dynamic raw = folly::dynamic::object("position", position)("width", 300)("height", 560)
        ("collapsable", !sheet && !host);
    if (host) raw["nativeID"] = bottomsheet::PortalHostNativeID;
    auto props = descriptor.cloneProps(PropsParserContext(1, *context_), nullptr, RawProps(raw));
    auto family = descriptor.createFamily({.tag = tag, .surfaceId = 1, .instanceHandle = nullptr});
    return descriptor.createShadowNode({.props = props,
        .children = std::make_shared<const Children>(std::move(children)),
        .state = descriptor.createInitialState(props, family)}, family);
  }

  void commit(Tag context) {
    auto area = make(context, "relative", {host_});
    auto status = tree_->commit([&](const RootShadowNode& root) {
      return std::static_pointer_cast<RootShadowNode>(root.ShadowNode::clone(
          {.children = std::make_shared<const Children>(Children{area})}));
    }, {});
    if (status != ShadowTreeCommitStatus::Succeeded) {
      throw std::runtime_error("Fixture commit failed");
    }
  }

  jni::local_ref<bottomsheet::FabricPortalPublication::jhybridobject> lease() {
    return bottomsheet::FabricPortalPublication::newObjectCxxArgs(manager_);
  }

  jni::local_ref<StateWrapperImpl::jhybridobject> takeDeliveredState() {
    auto transaction = tree_->getMountingCoordinator()->pullTransaction(true);
    if (!transaction) return nullptr;
    for (const auto& mutation : transaction->getMutations()) {
      const auto& child = mutation.newChildShadowView;
      if (child.tag == 14 && child.state) {
        // Same SDK construction and State assignment as FabricMountingManager.
        auto wrapper = StateWrapperImpl::newObjectJavaArgs();
        wrapper->cthis()->setState(child.state);
        return wrapper;
      }
    }
    return nullptr;
  }

  void moveHost(jint context) {
    host_ = tree_->getCurrentRevision().rootShadowNode->getChildren().at(0)->getChildren().at(0);
    commit(context);
  }

  std::shared_ptr<ContextContainer> context_ = std::make_shared<ContextContainer>();
  std::shared_ptr<UIManager> manager_ = std::make_shared<UIManager>(RuntimeExecutor{}, context_);
  ViewComponentDescriptor views_{{.eventDispatcher = {}, .contextContainer = context_, .flavor = nullptr}};
  BottomSheetViewComponentDescriptor sheets_{{.eventDispatcher = {}, .contextContainer = context_, .flavor = nullptr}};
  ShadowTree* tree_ = nullptr;
  std::shared_ptr<const ShadowNode> host_;
};
} // namespace

extern "C" JNIEXPORT jobject JNICALL
Java_com_swmansion_reactnativebottomsheet_accessibility_FabricPublicationJniFixture_create(
    JNIEnv*, jclass) {
  try {
    FabricPublicationJniFixture::registerNatives();
    return FabricPublicationJniFixture::newObjectCxxArgs().release();
  } catch (...) {
    jni::translatePendingCppExceptionToJavaException();
    return nullptr;
  }
}
