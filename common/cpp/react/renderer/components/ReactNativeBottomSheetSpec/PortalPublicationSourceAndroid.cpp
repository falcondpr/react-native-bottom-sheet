#ifdef ANDROID
#include "PortalPublicationSource.h"
#include <fbjni/fbjni.h>
#include <react/fabric/Binding.h>
#include <react/fabric/JFabricUIManager.h>
#include <react/fabric/StateWrapperImpl.h>
#include <react/renderer/scheduler/Scheduler.h>

namespace facebook::react::bottomsheet {
namespace {
#if __has_include(<react/fabric/FabricUIManagerBinding.h>)
using NativeBinding = FabricUIManagerBinding;
#else
using NativeBinding = Binding;
#endif

struct JFabricPortalReceipt : jni::JavaClass<JFabricPortalReceipt> {
  static constexpr auto kJavaDescriptor =
      "Lcom/swmansion/reactnativebottomsheet/accessibility/FabricPortalReceipt;";

  static jni::local_ref<JFabricPortalReceipt> create(const PortalSourceReceipt& receipt) {
    auto contexts = jni::JArrayInt::newArray(receipt.contexts.size());
    contexts->setRegion(0, receipt.contexts.size(), receipt.contexts.data());
    return newInstance(
        jni::make_jstring(receipt.publicationId), static_cast<jint>(receipt.host), contexts);
  }
};

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
        makeNativeMethod("receiptNative", FabricPortalPublication::receiptNative),
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

  jni::local_ref<JFabricPortalReceipt> receiptNative(
      jint surface, jint tag, jni::alias_ref<StateWrapper::javaobject> object) {
    if (!object || !object->isInstanceOf(StateWrapperImpl::javaClassStatic())) return nullptr;
    StateWrapperImpl* wrapper;
    try {
      wrapper = jni::static_ref_cast<StateWrapperImpl::jhybridobject>(object)->cthis();
    } catch (const jni::JniException& exception) {
      // fbjni reports a reset hybrid pointer as NPE. Other JNI failures surface.
      if (!exception.getThrowable()->isInstanceOf(jni::findClassLocal("java/lang/NullPointerException"))) throw;
      return nullptr;
    }
    // The delivered State must not be replaced by the family's newest State.
    auto receipt = source_.receiptForState(surface, tag, wrapper->getState());
    if (!receipt) return nullptr;
    return JFabricPortalReceipt::create(*receipt);
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
