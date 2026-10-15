#include "PortalPublicationSource.h"

#ifdef ANDROID
#include "PortalContextGraph.h"
#include "ShadowNodes.h"
#include <algorithm>
#include <atomic>
#include <stdexcept>

namespace facebook::react::bottomsheet {
namespace {
std::atomic<uint64_t> nextSource{0};
}

PortalPublicationSource::PortalPublicationSource(
    const std::shared_ptr<UIManager>& manager)
    : manager_(manager), prefix_(std::to_string(++nextSource) + ":") {
  if (!manager) throw std::invalid_argument("Missing Fabric UIManager");
  manager->registerCommitHook(*this);
}

PortalPublicationSource::~PortalPublicationSource() {
  if (auto manager = manager_.lock()) manager->unregisterCommitHook(*this);
}

void PortalPublicationSource::bootstrap() {
  auto manager = manager_.lock();
  if (!manager) return;
  std::vector<SurfaceId> surfaces;
  manager->getShadowTreeRegistry().enumerate([&](const ShadowTree& tree, bool&) {
    surfaces.push_back(tree.getSurfaceId());
  });
  for (auto surface : surfaces) {
    manager->getShadowTreeRegistry().visit(surface, [](const ShadowTree& tree) {
      tree.commit([](const RootShadowNode& root) {
        return std::static_pointer_cast<RootShadowNode>(root.ShadowNode::clone({}));
      }, {});
    });
  }
}

void PortalPublicationSource::rememberFinalRoot(const RootShadowNode::Shared& root) const {
  auto index = indexPortalShadowNodes(*root);
  if (!index) return;
  std::lock_guard lock(mutex_);
  std::erase_if(finalRoots_, [](const auto& entry) { return entry.first.expired(); });
  for (const auto& [tag, node] : *index) {
    auto state = node->getState();
    auto concrete = dynamic_cast<const BottomSheetViewShadowNode::ConcreteState*>(state.get());
    if (!concrete || !concrete->getData().portalPublicationId.starts_with(prefix_)) continue;
    auto [entry, inserted] = finalRoots_.try_emplace(std::weak_ptr<const State>{state}, FinalRoot{root});
    if (!inserted && (entry->second.root.owner_before(root) || root.owner_before(entry->second.root))) {
      entry->second.ambiguous = true;
    }
  }
}

RootShadowNode::Unshared PortalPublicationSource::shadowTreeWillCommit(
    const ShadowTree&,
    const RootShadowNode::Shared& oldRoot,
    const RootShadowNode::Unshared& proposal) noexcept {
  auto index = indexPortalShadowNodes(*proposal);
  if (!index) return proposal;
  rememberFinalRoot(oldRoot);
  std::string id;
  {
    std::lock_guard lock(mutex_);
    // oldRoot is final, including changes from hooks registered after this one.
    // Never retain this hook's proposal as a committed source.
    if (std::find(history_.begin(), history_.end(), oldRoot) == history_.end()) {
      history_.push_back(oldRoot);
      // Bound retained tree memory even when Java delivery is indefinitely late.
      // An evicted receipt is unavailable, never replaced with another root.
      if (history_.size() > 32) history_.pop_front();
    }
    id = prefix_ + std::to_string(++next_);
  }
  auto result = proposal;
  for (const auto& [tag, node] : *index) {
    auto sheet = dynamic_cast<const BottomSheetViewShadowNode*>(node);
    if (!sheet) continue;
    const auto& previous = static_cast<const BottomSheetViewShadowNode::ConcreteState&>(*sheet->getState());
    auto stamped = std::make_shared<BottomSheetViewState>(previous.getData());
    stamped->portalPublicationId = id;
    auto state = std::make_shared<const BottomSheetViewShadowNode::ConcreteState>(stamped, previous);
    result = std::static_pointer_cast<RootShadowNode>(result->cloneTree(
        sheet->getFamily(), [&](const ShadowNode& current) { return current.clone({.state = state}); }));
  }
  return result;
}

RootShadowNode::Shared PortalPublicationSource::rootForState(
    SurfaceId surface, Tag tag, const State::Shared& state) const {
  auto concrete = dynamic_cast<const BottomSheetViewShadowNode::ConcreteState*>(state.get());
  if (!concrete || !concrete->getData().portalPublicationId.starts_with(prefix_)) return nullptr;
  auto manager = manager_.lock();
  if (!manager) return nullptr;
  std::vector<RootShadowNode::Shared> candidates;
  RootShadowNode::Shared liveRoot;
  manager->getShadowTreeRegistry().visit(surface, [&](const ShadowTree& tree) {
    liveRoot = tree.getCurrentRevision().rootShadowNode;
    candidates = {liveRoot,
                  tree.getMountingCoordinator()->getBaseRevision().rootShadowNode};
  });
  if (!liveRoot) return nullptr;
  {
    std::lock_guard lock(mutex_);
    candidates.insert(candidates.end(), history_.begin(), history_.end());
  }
  RootShadowNode::Shared result;
  for (const auto& root : candidates) {
    if (root->getSurfaceId() != surface ||
        root->getFamilyShared() != liveRoot->getFamilyShared()) continue;
    auto index = indexPortalShadowNodes(*root);
    if (index && index->contains(tag) && index->at(tag)->getState() == state) {
      rememberFinalRoot(root);
      {
        std::lock_guard lock(mutex_);
        const auto& final = finalRoots_.at(std::weak_ptr<const State>{state});
        if (final.ambiguous || final.root.lock() != root) return nullptr;
      }
      if (result && result != root) return nullptr;
      result = root;
    }
  }
  return result;
}

std::optional<std::vector<Tag>> PortalPublicationSource::sheetTagsForState(
    SurfaceId surface, Tag tag, const State::Shared& state) const {
  auto root = rootForState(surface, tag, state);
  if (!root) return std::nullopt;
  auto nodes = indexPortalShadowNodes(*root);
  if (!nodes) return std::nullopt;
  std::vector<Tag> tags;
  for (const auto& [nodeTag, node] : *nodes) {
    if (dynamic_cast<const BottomSheetViewShadowNode*>(node)) tags.push_back(nodeTag);
  }
  return tags;
}

RootShadowNode::Shared PortalPublicationSource::rootForStates(
    SurfaceId surface, const std::map<Tag, State::Shared>& states) const {
  RootShadowNode::Shared result;
  for (const auto& [tag, state] : states) {
    auto root = rootForState(surface, tag, state);
    if (!root || (result && result != root)) return nullptr;
    result = std::move(root);
  }
  if (!result) return nullptr;
  auto nodes = indexPortalShadowNodes(*result);
  if (!nodes) return nullptr;
  size_t sheetCount = 0;
  for (const auto& [tag, node] : *nodes) {
    if (!dynamic_cast<const BottomSheetViewShadowNode*>(node)) continue;
    if (!states.contains(tag)) return nullptr;
    ++sheetCount;
  }
  return sheetCount == states.size() ? result : nullptr;
}

std::optional<PortalSourceReceipt> PortalPublicationSource::receiptForState(
    SurfaceId surface, Tag tag, const State::Shared& state) const {
  auto root = rootForState(surface, tag, state);
  if (!root) return std::nullopt;
  auto graph = discoverPortalContexts(*root);
  if (!graph) return std::nullopt;
  const auto& node = *graph->nodes.at(tag);
  auto host = graph->hostForPresentation(node.getFamily(), *root);
  if (!host) return std::nullopt;
  const auto& concrete = static_cast<const BottomSheetViewShadowNode::ConcreteState&>(*state);
  return PortalSourceReceipt{
      concrete.getData().portalPublicationId, *host,
      graph->contextPathForNode(
          *graph->contexts.at(graph->hostContexts.at(*host)).boundary, *root)};
}

} // namespace facebook::react::bottomsheet
#endif
