#ifdef ANDROID
#include "PortalPublicationSource.h"
#include <fbjni/fbjni.h>
#include <react/fabric/Binding.h>
#include <react/fabric/JFabricUIManager.h>
#include <react/renderer/scheduler/Scheduler.h>

namespace facebook::react::bottomsheet {
namespace {
#if __has_include(<react/fabric/FabricUIManagerBinding.h>)
using NativeBinding = FabricUIManagerBinding;
#else
using NativeBinding = Binding;
#endif

class FabricPortalPublication final : public jni::HybridClass<FabricPortalPublication> {
 public:
  static constexpr auto kJavaDescriptor =
      "Lcom/swmansion/reactnativebottomsheet/accessibility/FabricPortalPublication;";

  explicit FabricPortalPublication(const std::shared_ptr<UIManager>& manager)
      : source_(manager) {}

  static void registerNatives() {
    registerHybrid({
        makeNativeMethod("initHybrid", FabricPortalPublication::initHybrid),
        makeNativeMethod("bootstrapNative", FabricPortalPublication::bootstrapNative),
    });
  }

 private:
  static jni::local_ref<jhybriddata> initHybrid(
      jni::alias_ref<jclass>, jni::alias_ref<JFabricUIManager::javaobject> manager) {
    // JFabricUIManager::getBinding dereferences mBinding without a null guard.
    // Keep the actual binding object alive while reading its scheduler.
    static const auto field = JFabricUIManager::javaClassStatic()->getField<NativeBinding::javaobject>("mBinding");
    auto binding = manager->getFieldValue(field);
    if (!binding) return nullptr;
    auto scheduler = binding->cthis()->getScheduler();
    return scheduler ? makeCxxInstance(scheduler->getUIManager()) : nullptr;
  }

  void bootstrapNative() {
    source_.bootstrap();
  }

  PortalPublicationSource source_;
};
} // namespace
} // namespace facebook::react::bottomsheet

JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM* vm, void*) {
  return facebook::jni::initialize(vm, [] {
    facebook::react::bottomsheet::FabricPortalPublication::registerNatives();
  });
}
#endif
