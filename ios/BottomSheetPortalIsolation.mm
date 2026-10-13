#import "BottomSheetPortalIsolation.h"
#import "BottomSheetPortalMountingObserver.h"
#import "BottomSheetPortalNativeContainer.h"

using namespace facebook::react;
using namespace facebook::react::bottomsheet;

namespace {
struct AppliedPortalRoot {
  RootShadowNode::Shared root;
  PortalContextGraph graph;
  BottomSheetPortalMountingObserver *__strong observer;
  std::map<Tag, std::vector<const ShadowNodeFamily *>> retainedByHost;
};
struct ContextPresentation {
  BottomSheetPortalPresentation *__strong presentation;
  const ShadowNode *node;
  Tag host;
};
using ContextKey = std::pair<const RootShadowNode *, Tag>;

NSSet<UIView *> *nativeCut(const AppliedPortalRoot& publication, BottomSheetNativeHierarchySnapshot *hierarchy) {
  std::vector<PortalRetainedPaths> requests;
  for (const auto& [host, retained] : publication.retainedByHost) {
    requests.push_back({&publication.graph.nodes.at(host)->getFamily(), retained});
  }
  return [publication.observer hiddenBranchesForRoot:publication.root retainedPaths:requests hierarchy:hierarchy];
}

NSSet<UIView *> *composeNativeCuts(NSSet<UIView *> *branches, NSSet<UIView *> *retainedOwners,
                                  BottomSheetNativeHierarchySnapshot *hierarchy) {
  NSMutableSet<UIView *> *result = [NSMutableSet new];
  for (UIView *branch in branches) {
    NSMutableSet<UIView *> *retainedPath = [NSMutableSet new];
    for (UIView *owner in retainedOwners) {
      NSMutableArray<UIView *> *path = [NSMutableArray new];
      UIView *current = owner;
      while (current && current != branch) {
        [path addObject:current];
        current = [hierarchy parentOfView:current];
      }
      if (current == branch) {
        [retainedPath addObjectsFromArray:path];
        [retainedPath addObject:branch];
      }
    }
    NSMutableArray<UIView *> *pending = [NSMutableArray arrayWithObject:branch];
    while (pending.count) {
      UIView *view = pending.lastObject;
      [pending removeLastObject];
      if (![retainedPath containsObject:view]) {
        [result addObject:view];
      } else if (![retainedOwners containsObject:view]) {
        [pending addObjectsFromArray:[hierarchy childrenOfView:view] ?: @[]];
      }
    }
  }
  return hierarchy.isValid ? result : nil;
}
} // namespace

@implementation BottomSheetPortalPresentation
+ (instancetype)presentationForIdentity:(BottomSheetPresentationIdentity *)identity
                                anchor:(UIView *)anchor active:(BOOL)active eligible:(BOOL)eligible
{
  UIView *owner = [anchor conformsToProtocol:@protocol(BottomSheetPortalNativeContainer)]
      ? ((UIView<BottomSheetPortalNativeContainer> *)anchor).portalNativeOwner : anchor;
  if (!owner || owner.window != anchor.window) return nil;
  auto hierarchy = [BottomSheetNativeHierarchySnapshot new];
  [hierarchy tagOfView:owner];
  if (!hierarchy.isValid) return nil;
  auto observer = BottomSheetPortalObserverForView(owner);
  if (!observer || ![hierarchy validate]) return nil;
  return [[self alloc] initWithIdentity:identity owner:owner observer:observer
                               active:active eligible:eligible];
}

- (instancetype)initWithIdentity:(BottomSheetPresentationIdentity *)identity
                           owner:(UIView *)owner
                        observer:(BottomSheetPortalMountingObserver *)observer
                          active:(BOOL)active
                        eligible:(BOOL)eligible
{
  if (self = [super init]) {
    _identity = identity;
    _owner = owner;
    _observer = observer;
    _active = active;
    _eligible = eligible;
  }
  return self;
}
@end

@interface BottomSheetPortalIsolation ()
- (instancetype)initWithHiddenBranches:(NSSet<UIView *> *)hiddenBranches
                                   tops:(NSSet<BottomSheetPresentationIdentity *> *)tops;
@end

@implementation BottomSheetPortalIsolation
- (instancetype)initWithHiddenBranches:(NSSet<UIView *> *)hiddenBranches
                                   tops:(NSSet<BottomSheetPresentationIdentity *> *)tops
{
  if (self = [super init]) {
    _hiddenBranches = [hiddenBranches copy];
    _topPresentationIdentities = [tops copy];
  }
  return self;
}

+ (instancetype)projectionFromPresentations:(NSArray<BottomSheetPortalPresentation *> *)presentations
                              orderProvider:(BottomSheetPresentationOrderProvider)orderProvider
{
  NSCAssert(NSThread.isMainThread, @"Portal isolation must run on main");
  auto hierarchy = [BottomSheetNativeHierarchySnapshot new];
  if (!hierarchy.isValid) return nil;
  std::map<const RootShadowNode *, AppliedPortalRoot> roots;
  std::map<ContextKey, std::vector<ContextPresentation>> groups;
  NSMutableSet<BottomSheetPresentationIdentity *> *identities = [NSMutableSet new];
  NSMutableSet<UIView *> *owners = [NSMutableSet new];
  for (BottomSheetPortalPresentation *presentation in presentations) {
    if (!presentation.isActive || !presentation.isEligible) continue;
    if ([identities containsObject:presentation.identity] ||
        [owners containsObject:presentation.owner]) return nil;
    [identities addObject:presentation.identity];
    [owners addObject:presentation.owner];
    Tag ownerTag = static_cast<Tag>([hierarchy tagOfView:presentation.owner]);
    if (!hierarchy.isValid) return nil;
    auto root = [presentation.observer currentRootForOwner:presentation.owner];
    if (!root) return nil;
    auto found = roots.find(root.get());
    if (found == roots.end()) {
      auto graph = discoverPortalContexts(*root);
      if (!graph) return nil;
      found = roots.emplace(root.get(), AppliedPortalRoot{
          root, std::move(*graph), presentation.observer, {}}).first;
    } else if (found->second.observer != presentation.observer) {
      return nil;
    }
    auto& graph = found->second.graph;
    auto node = graph.nodes.find(ownerTag);
    if (node == graph.nodes.end()) return nil;
    auto host = graph.hostForPresentation(node->second->getFamily(), *root);
    if (!host) return nil;
    groups[{root.get(), graph.hostContexts.at(*host)}].push_back(
        {presentation, node->second, *host});
  }

  NSMutableSet<BottomSheetPresentationIdentity *> *tops = [NSMutableSet new];
  NSMutableSet<UIView *> *retainedOwners = [NSMutableSet new];
  for (const auto& [context, members] : groups) {
    NSMutableArray<BottomSheetPresentationCandidate *> *candidates = [NSMutableArray new];
    for (const auto& member : members) {
      [candidates addObject:[[BottomSheetPresentationCandidate alloc]
          initWithIdentity:member.presentation.identity active:YES eligible:YES]];
    }
    auto decision = [BottomSheetPresentationResolver ownershipFromCandidates:candidates
                                                             orderProvider:orderProvider];
    if (decision.topPresentationIdentity) [tops addObject:decision.topPresentationIdentity];
    auto& retained = roots.at(context.first).retainedByHost;
    for (const auto& member : members) {
      if ([decision.retainedPresentationIdentities containsObject:member.presentation.identity]) {
        retained[member.host].push_back(&member.node->getFamily());
        [retainedOwners addObject:member.presentation.owner];
      }
    }
  }

  // An order provider can reenter native lifecycle. Every source, including a
  // covered presentation, must still belong to this exact completed root.
  auto sourcesAreCurrent = [&] {
    for (const auto& [context, members] : groups) {
      for (const auto& member : members) {
        if ([member.presentation.observer currentRootForOwner:member.presentation.owner] !=
            roots.at(context.first).root) return false;
      }
    }
    return true;
  };
  if (!sourcesAreCurrent()) return nil;
  NSMutableSet<UIView *> *hiddenBranches = [NSMutableSet new];
  for (const auto& [key, publication] : roots) {
    auto branches = nativeCut(publication, hierarchy);
    if (!branches) return nil;
    [hiddenBranches unionSet:branches];
  }
  auto composed = composeNativeCuts(hiddenBranches, retainedOwners, hierarchy);
  if (!composed || !sourcesAreCurrent()) return nil;
  auto result = [[self alloc] initWithHiddenBranches:composed tops:tops];
  return [hierarchy validate] ? result : nil;
}
@end
