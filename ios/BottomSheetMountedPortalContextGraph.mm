#import "BottomSheetMountedPortalContextGraph.h"
#import <React/RCTComponentViewRegistry.h>
#import <React/RCTMountingManager.h>
#import <React/RCTViewComponentView.h>

using namespace facebook::react;
using namespace facebook::react::bottomsheet;

namespace {
struct MountedIdentity {
  __weak UIView<RCTComponentViewProtocol> *view;
  ShadowNodeFamily::Weak family;
};

template <typename Mutation>
Tag parentTag(const Mutation& mutation) {
  if constexpr (requires { mutation.parentTag; }) return mutation.parentTag;
  else return mutation.parentShadowView.tag; // RN 0.76 mounting representation.
}
} // namespace

@implementation BottomSheetMountedPortalContextGraph {
  __weak RCTMountingManager *_manager;
  std::shared_ptr<const RootShadowNode> _root;
  MountedIdentity _rootIdentity;
  PortalNativeMembers _members;
  std::map<Tag, MountedIdentity> _identities;
}

- (instancetype)initWithMountingManager:(RCTMountingManager *)manager
{
  if (self = [super init]) _manager = manager;
  return self;
}

- (void)publishRoot:(const std::shared_ptr<const facebook::react::RootShadowNode> &)root
          mutations:(const facebook::react::ShadowViewMutation::List &)mutations
{
  NSCAssert(NSThread.isMainThread, @"Native portal membership is main-thread only");
  if (!root || !_manager) {
    [self invalidate];
    return;
  }
  auto nodes = indexPortalShadowNodes(*root);
  if (!nodes) {
    [self invalidate];
    return;
  }
  if (_root && _root->getFamilyShared() != root->getFamilyShared()) [self invalidate];
  if (!_root) {
    _rootIdentity = {[_manager.componentViewRegistry findComponentViewWithTag:root->getTag()],
                     root->getFamilyShared()};
  }
  for (const auto& mutation : mutations) {
    switch (mutation.type) {
      case ShadowViewMutation::Create: {
        Tag tag = mutation.newChildShadowView.tag;
        _members.alive.insert(tag);
        auto node = nodes->find(tag);
        if (node != nodes->end()) {
          _identities[tag] = {
              [_manager.componentViewRegistry findComponentViewWithTag:tag],
              node->second->getFamilyShared()};
        }
        break;
      }
      case ShadowViewMutation::Delete: {
        Tag tag = mutation.oldChildShadowView.tag;
        _members.alive.erase(tag);
        _members.parents.erase(tag);
        _identities.erase(tag);
        break;
      }
      case ShadowViewMutation::Insert:
        _members.parents[mutation.newChildShadowView.tag] = parentTag(mutation);
        break;
      case ShadowViewMutation::Remove:
        _members.parents.erase(mutation.oldChildShadowView.tag);
        break;
      case ShadowViewMutation::Update:
        break;
    }
  }
  _root = root;
}

- (UIView<RCTComponentViewProtocol> *)mounted:(Tag)tag
{
  return [_manager.componentViewRegistry findComponentViewWithTag:tag];
}

- (Tag)registeredParentOf:(UIView *)view
{
  for (UIView *parent = view.superview; parent; parent = parent.superview) {
    Tag tag = static_cast<Tag>(parent.tag);
    if ([self mounted:tag] == parent) return tag;
    if ([parent conformsToProtocol:@protocol(RCTComponentViewProtocol)]) return 0;
  }
  return 0;
}

- (BOOL)validateBranch:(const ShadowNode &)node
{
  Tag tag = node.getTag();
  UIView *view = [self mounted:tag];
  if (&node == _root.get()) {
    if (!view || _rootIdentity.view != view ||
        _rootIdentity.family.lock() != node.getFamilyShared()) return NO;
  } else if (_members.alive.contains(tag)) {
    auto identity = _identities.find(tag);
    if (!view || identity == _identities.end() || identity->second.view != view ||
        identity->second.family.lock() != node.getFamilyShared()) return NO;
    auto parent = _members.parents.find(tag);
    if (parent == _members.parents.end() ||
        parent->second != [self registeredParentOf:view]) return NO;
  } else if (view) {
    return NO;
  }
  for (const auto& child : node.getChildren()) {
    if (![self validateBranch:*child]) return NO;
  }
  return YES;
}

- (NSSet<UIView *> *)hiddenBranchesForRoot:
    (const std::shared_ptr<const facebook::react::RootShadowNode> &)root
                                    retainedPaths:
    (const std::vector<facebook::react::bottomsheet::PortalRetainedPaths> &)requests
{
  NSCAssert(NSThread.isMainThread, @"Native portal projection is main-thread only");
  if (!root || root != _root || !_manager) return nil;
  auto graph = discoverPortalContexts(*root);
  if (!graph) return nil;
  std::set<Tag> scopes;
  for (const auto& request : requests) {
    if (!request.host) return nil;
    auto host = graph->hostContexts.find(request.host->getTag());
    if (host == graph->hostContexts.end()) return nil;
    auto view = [self mounted:host->first];
    if (![view isKindOfClass:RCTViewComponentView.class] ||
        ![((RCTViewComponentView *)view).nativeId
            isEqualToString:[NSString stringWithUTF8String:PortalHostNativeID]]) return nil;
    scopes.insert(host->second);
  }
  for (Tag scope : scopes) {
    if (![self validateBranch:*graph->contexts.at(scope).boundary]) {
      return nil;
    }
  }
  auto projection = projectPortalIsolation(*graph, _members, requests);
  if (!projection) return nil;
  NSMutableSet<UIView *> *branches = [NSMutableSet new];
  for (Tag tag : projection->hiddenBranches) {
    UIView *view = [self mounted:tag];
    if (!view) return nil;
    [branches addObject:view];
  }
  for (const auto& [parent, retained] : projection->retainedChildren) {
    UIView *view = [self mounted:parent];
    if (!view) continue; // A flattened logical parent has no native-only children.
    for (UIView *child in view.subviews) {
      Tag tag = static_cast<Tag>(child.tag);
      if (graph->nodes.contains(tag) && [self mounted:tag] == child) continue;
      NSMutableArray<UIView *> *pending = [NSMutableArray arrayWithObject:child];
      while (pending.count) {
        UIView *next = pending.lastObject;
        [pending removeLastObject];
        Tag nextTag = static_cast<Tag>(next.tag);
        if ([self mounted:nextTag] == next) {
          return nil; // Opaque native ownership must be adapted explicitly.
        }
        [pending addObjectsFromArray:next.subviews];
      }
      [branches addObject:child];
    }
  }
  return branches;
}

- (void)invalidate
{
  NSCAssert(NSThread.isMainThread, @"Native portal membership is main-thread only");
  _root.reset();
  _rootIdentity = {};
  _members = {};
  _identities.clear();
}

- (BottomSheetNativeViewDeletion *)nativeDeletionForMutations:(const ShadowViewMutation::List &)mutations
{
  NSCAssert(NSThread.isMainThread, @"Native portal retirement is main-thread only");
  if (!_root || !_manager) return nil;
  auto nodes = indexPortalShadowNodes(*_root);
  if (!nodes) return nil;
  NSMutableSet<UIView *> *deleted = [NSMutableSet new];
  for (const auto& mutation : mutations) {
    if (mutation.type != ShadowViewMutation::Delete) continue;
    Tag tag = mutation.oldChildShadowView.tag;
    auto identity = _identities.find(tag);
    auto node = nodes->find(tag);
    UIView *view = [self mounted:tag];
    if (!view || !_members.alive.contains(tag) || identity == _identities.end() ||
        identity->second.view != view || node == nodes->end() ||
        identity->second.family.lock() != node->second->getFamilyShared()) return nil;
    [deleted addObject:view];
  }
  NSMutableSet<UIView *> *survivors = [NSMutableSet new];
  NSMutableArray<UIView *> *pending = [NSMutableArray arrayWithArray:deleted.allObjects];
  while (pending.count) {
    UIView *view = pending.lastObject;
    [pending removeLastObject];
    if (![deleted containsObject:view] &&
        ([self mounted:static_cast<Tag>(view.tag)] == view ||
         [view conformsToProtocol:@protocol(RCTComponentViewProtocol)])) {
      [survivors addObject:view];
      continue; // A surviving registered subtree keeps all of its native children.
    }
    [pending addObjectsFromArray:view.subviews];
  }
  return [[BottomSheetNativeViewDeletion alloc] initWithDeletedViews:deleted
      survivingRegisteredViews:survivors];
}

@end
