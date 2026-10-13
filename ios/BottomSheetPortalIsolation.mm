#import "BottomSheetPortalIsolation.h"
#import "BottomSheetPortalMountingObserver.h"

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
} // namespace

@implementation BottomSheetPortalPresentation
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
    auto node = graph.nodes.find(static_cast<Tag>(presentation.owner.tag));
    if (node == graph.nodes.end()) return nil;
    auto host = graph.hostForPresentation(node->second->getFamily(), *root);
    if (!host) return nil;
    groups[{root.get(), graph.hostContexts.at(*host)}].push_back(
        {presentation, node->second, *host});
  }

  NSMutableSet<BottomSheetPresentationIdentity *> *tops = [NSMutableSet new];
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
      }
    }
  }

  // An order provider can reenter native lifecycle. Every source, including a
  // covered presentation, must still belong to this exact completed root.
  for (const auto& [context, members] : groups) {
    for (const auto& member : members) {
      if ([member.presentation.observer currentRootForOwner:member.presentation.owner] !=
          roots.at(context.first).root) return nil;
    }
  }
  NSMutableSet<UIView *> *hiddenBranches = [NSMutableSet new];
  for (const auto& [key, publication] : roots) {
    std::vector<PortalRetainedPaths> requests;
    for (const auto& [host, retained] : publication.retainedByHost) {
      requests.push_back({&publication.graph.nodes.at(host)->getFamily(), retained});
    }
    auto branches = [publication.observer hiddenBranchesForRoot:publication.root
                                                retainedPaths:requests];
    if (!branches) return nil;
    [hiddenBranches unionSet:branches];
  }
  return [[self alloc] initWithHiddenBranches:hiddenBranches tops:tops];
}
@end
