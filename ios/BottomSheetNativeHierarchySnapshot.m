#import "BottomSheetNativeHierarchySnapshot.h"
#import <objc/runtime.h>
#include <dlfcn.h>

static NSMapTable *BottomSheetNativeFactTable(void)
{
  return [[NSMapTable alloc]
      initWithKeyOptions:NSPointerFunctionsStrongMemory | NSPointerFunctionsObjectPointerPersonality
            valueOptions:NSPointerFunctionsStrongMemory capacity:0];
}

@implementation BottomSheetNativeHierarchySnapshot {
  IMP _parentGetter;
  IMP _childrenGetter;
  IMP _tagGetter;
  NSMapTable<UIView *, id> *_parents;
  NSMapTable<UIView *, NSArray<UIView *> *> *_children;
  NSMapTable<UIView *, NSNumber *> *_tags;
  BOOL _valid;
}

- (instancetype)init
{
  NSCAssert(NSThread.isMainThread, @"Native hierarchy must be read on main");
  if (self = [super init]) {
    _parents = BottomSheetNativeFactTable();
    _children = BottomSheetNativeFactTable();
    _tags = BottomSheetNativeFactTable();
    Class base = objc_getClass("UIView");
    _parentGetter = method_getImplementation(class_getInstanceMethod(base, @selector(superview)));
    _childrenGetter = method_getImplementation(class_getInstanceMethod(base, @selector(subviews)));
    _tagGetter = method_getImplementation(class_getInstanceMethod(base, @selector(tag)));
    Dl_info classImage = {0};
    _valid = dladdr((__bridge const void *)base, &classImage) && classImage.dli_fbase;
    // A global replacement must not become the supposedly standard getter.
    for (NSValue *value in @[[NSValue valueWithPointer:(const void *)_parentGetter],
                            [NSValue valueWithPointer:(const void *)_childrenGetter],
                            [NSValue valueWithPointer:(const void *)_tagGetter]]) {
      Dl_info info = {0};
      if (!dladdr(value.pointerValue, &info) || info.dli_fbase != classImage.dli_fbase) _valid = NO;
    }
  }
  return self;
}

- (BOOL)isValid { return _valid; }

- (BOOL)canRead:(SEL)selector fromView:(UIView *)view implementation:(IMP)expected
{
  NSCAssert(NSThread.isMainThread, @"Native hierarchy must be read on main");
  if (!_valid) return NO;
  Method actual = class_getInstanceMethod(object_getClass(view), selector);
  Method base = class_getInstanceMethod(objc_getClass("UIView"), selector);
  if (!actual || !base || method_getImplementation(actual) != expected ||
      method_getImplementation(base) != expected) {
    _valid = NO;
    return NO;
  }
  return YES;
}

- (UIView *)parentOfView:(UIView *)view
{
  if (!view) return nil;
  if (![self canRead:@selector(superview) fromView:view implementation:_parentGetter]) return nil;
  id cached = [_parents objectForKey:view];
  if (!cached) {
    cached = view.superview ?: NSNull.null;
    [_parents setObject:cached forKey:view];
  }
  return cached == NSNull.null ? nil : cached;
}

- (NSInteger)tagOfView:(UIView *)view
{
  if (!view) return 0;
  if (![self canRead:@selector(tag) fromView:view implementation:_tagGetter]) return 0;
  NSNumber *cached = [_tags objectForKey:view];
  if (!cached) {
    cached = @(view.tag);
    [_tags setObject:cached forKey:view];
  }
  return cached.integerValue;
}

- (NSArray<UIView *> *)childrenOfView:(UIView *)view
{
  if (![self canRead:@selector(subviews) fromView:view implementation:_childrenGetter]) return nil;
  NSArray<UIView *> *cached = [_children objectForKey:view];
  if (!cached) {
    cached = [view.subviews copy];
    [_children setObject:cached forKey:view];
  }
  return cached;
}

- (BOOL)validate
{
  NSCAssert(NSThread.isMainThread, @"Native hierarchy must be read on main");
  for (UIView *view in _parents) {
    if (![self canRead:@selector(superview) fromView:view implementation:_parentGetter] ||
        (view.superview ?: NSNull.null) != [_parents objectForKey:view]) return NO;
  }
  for (UIView *view in _tags) {
    if (![self canRead:@selector(tag) fromView:view implementation:_tagGetter] ||
        view.tag != [_tags objectForKey:view].integerValue) return NO;
  }
  for (UIView *view in _children) {
    if (![self canRead:@selector(subviews) fromView:view implementation:_childrenGetter]) return NO;
    NSArray<UIView *> *current = view.subviews;
    NSArray<UIView *> *captured = [_children objectForKey:view];
    if (current.count != captured.count) return NO;
    for (NSUInteger index = 0; index < current.count; index++) {
      UIView *child = current[index];
      if (child != captured[index] ||
          ![self canRead:@selector(superview) fromView:child implementation:_parentGetter] ||
          child.superview != view) return NO;
    }
  }
  return _valid;
}
@end
