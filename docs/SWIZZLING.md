/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

# Swizzling in dd-sdk-ios

This document captures the mandatory patterns, known pitfalls, and real production incidents related to Objective-C method swizzling in the Datadog iOS SDK. **Read this before writing or modifying any swizzle.**

---

## The fundamental assumption

> **Every method you swizzle is already swizzled by someone else.**

The SDK installs into thousands of apps alongside frameworks like RxSwift, RxCocoa, Firebase, Alamofire, and custom in-house libraries. Any of these may swizzle the same method — before or after the SDK, using any technique. Your swizzle must be correct in all orderings and compositions.

---

## How the SDK swizzles

All swizzles use `MethodSwizzler<Signature, Override>` in `DatadogInternal/Sources/Swizzling/MethodSwizzler.swift`. This class:

- Captures the IMP that is current at install time as `previousImplementation`
- Sets a new IMP that calls the override closure, which receives `previousImplementation`
- Maintains a linked list so multiple independent swizzles on the same method compose correctly
- Provides `unswizzle()` to remove a specific layer without disturbing others

**Always use `MethodSwizzler`. Never call `method_exchangeImplementations` or `method_setImplementation` directly in production code.**

---

## Two categories of swizzle

Before applying any pattern, identify which category your swizzle falls into:

| Category | Description | Examples in this SDK |
|---|---|---|
| **Pure method intercept** | Observe a method call and delegate to `previousImplementation`. No value is stored, no proxy is created. | `UIViewController.viewDidAppear`, `UIApplication.sendEvent`, `URLSessionTask.resume`, `CALayer.display` |
| **Proxy-setter swizzle** | Intercept a *stored property setter* to replace the stored value with an internal proxy. Requires mirroring the getter too. | `UIScrollView.delegate` |

**Pure method intercepts** only need to call `previousImplementation` in the correct position. The three-guard pattern below does **not** apply.

**Proxy-setter swizzles** require all mandatory patterns below. `UIScrollViewSwizzler` is the only current example.

---

## Mandatory patterns

### 1. Complete setter pattern: nil guard + type guard + re-entrancy guard

When swizzling a property setter that installs an internal proxy (e.g., `UIScrollView.delegate`), three guards must be combined. Omitting any one creates a crash or visibility bug.

**Why three guards?**

| Guard | What it stops |
|---|---|
| nil check | Stale proxy leaked when property is cleared |
| type check (`value is OurProxy`) | Re-wrapping when our own proxy is passed back directly |
| re-entrancy guard (`objectsBeingSet`) | Infinite recursion when a third-party swizzle wraps our proxy in its own and re-calls the setter via ObjC dispatch with a *different* delegate type |

The type check alone is **not sufficient** to prevent re-entrancy. It only fires when our proxy comes back verbatim. If a third-party framework stores our proxy as its forward target and re-calls the setter with *its* proxy, the type check passes but the re-entrancy guard catches it.

**Complete pattern:**

```swift
private static var proxyKey: Void?
private static var objectsBeingSet: Set<ObjectIdentifier> = []

// Inside swizzle closure:

// 1. Nil guard — clean up associated proxy, forward nil
if value == nil {
    objc_setAssociatedObject(object, &Self.proxyKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    previousImplementation(object, selector, nil)
    return
}

// 2. Type guard — don't re-wrap when our proxy comes back directly
if value is OurProxy {
    previousImplementation(object, selector, value)
    return
}

// 3. Re-entrancy guard — break cycles from third-party swizzle re-entry
let objectID = ObjectIdentifier(object)
guard !Self.objectsBeingSet.contains(objectID) else {
    previousImplementation(object, selector, value)
    return
}
Self.objectsBeingSet.insert(objectID)
defer { Self.objectsBeingSet.remove(objectID) }

// 4. Normal path — create or reuse proxy, then forward
previousImplementation(object, selector, wrappedValue)
```

**Note:** Because UIKit setter calls happen on the main thread, a plain `Set` is safe. If the setter can be called off the main thread, protect the set with a lock.

### 2. Transparent getter swizzle when the setter installs a wrapper

If your setter swizzle wraps the stored value in an internal proxy (e.g., `UIScrollViewDelegateProxy`), the getter must be swizzled to unwrap it. User code that reads the property must see the original value, not the SDK's internal wrapper.

Failing to swizzle the getter causes:
- `collectionView.delegate as? CustomDelegate` returning `nil`
- Type-checking assertions crashing
- Any code comparing delegate identity failing

**Pattern:**

```swift
// Getter swizzle — mirror every setter swizzle that installs a proxy
swizzle(getterMethod) { previousImplementation -> Signature in
    return { object in
        let value = previousImplementation(object, Self.selector)
        if let proxy = value as? InternalProxy {
            return proxy.originalValue
        }
        return value
    }
}
```

Always install getter and setter swizzles together, and always remove them together.

### 3. Re-entrancy guard in proxy forwarding methods

When a proxy object is used to intercept delegate calls, it forwards unknown selectors to an `originalDelegate`. If another framework's proxy stores your proxy as *its* forward-to delegate while your proxy stores the other framework's proxy as `originalDelegate`, a circular chain forms:

```
proxy.responds(to:) → otherProxy.responds(to:) → proxy.responds(to:) → …
```

Guard `responds(to:)` against this:

```swift
private var isRespondingToSelector = false

override func responds(to aSelector: Selector!) -> Bool {
    if super.responds(to: aSelector) { return true }
    guard !isRespondingToSelector else { return false }
    isRespondingToSelector = true
    defer { isRespondingToSelector = false }
    return originalDelegate?.responds(to: aSelector) ?? false
}
```

---

## Known pitfalls

### Pitfall: assuming `previousImplementation` is the original Apple IMP

`previousImplementation` is whatever IMP was current when your swizzle was installed. It may be another framework's swizzle. That framework's swizzle may call the full setter via ObjC dispatch (going back through the top of the chain) instead of calling its own stored previous IMP. This is what creates re-entrant cycles.

Do not assume anything about what `previousImplementation` does beyond "it is the next step in the chain".

### Pitfall: swizzling only the setter without swizzling the getter

Whenever you replace the stored value of a property with an internal wrapper object, reading that property returns the wrapper. This is invisible from within the SDK but immediately visible to customer code.

Rule: **setter wraps → getter unwraps. Always.**

### Pitfall: relying on the proxy type check alone to prevent re-entrancy

`if value is OurProxy { pass through }` only handles the case where your own proxy comes back verbatim. It does **not** prevent infinite recursion when a third-party framework wraps your proxy in its own proxy and re-calls the setter with a new value of a different type. You need the `objectsBeingSet` re-entrancy guard in addition to the type check.

### Pitfall: using a single global re-entrancy flag

A global `static var isSwizzling = false` flag breaks when two different objects have their property set concurrently, or when the setter is legitimately called on different objects during setup. Always key the re-entrancy guard on the **object identity** (`ObjectIdentifier(object)`).

### Pitfall: proxy `responds(to:)` creating circular chains

Any proxy pattern involving `responds(to:)` + `forwardingTarget(for:)` that delegates to an `originalDelegate` is vulnerable to circular chains. Third-party delegate proxies (RxSwift, Firebase Analytics, etc.) use the same pattern and may install themselves in your chain. Always guard `responds(to:)`.

### Pitfall: not cleaning up associated objects on nil assignment

When a setter swizzle stores an associated object (e.g., a proxy keyed to the object under swizzle), it must explicitly remove that associated object when the property is set to `nil`. Failing to do so leaks the proxy and can cause stale state on object reuse.

```swift
if value == nil {
    objc_setAssociatedObject(object, &Self.proxyKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    previousImplementation(object, selector, nil)
    return
}
```

---

## Real incidents

### RUM 3.8.0 — RxSwift `rx.contentOffset` crash (stack overflow)

**Symptom:** Apps using RxSwift's `rx.contentOffset` on `UICollectionView` crashed with a stack overflow after upgrading to 3.8.0.

**Root cause:** `UIScrollViewSwizzler` swizzled `UIScrollView.delegate` setter. RxSwift's `DelegateProxy` also swizzles this setter. Due to swizzle installation order, Datadog's `previousImplementation` pointed to RxSwift's stored IMP. When Datadog called `previousImplementation(scrollView, DDProxy)`, RxSwift saw a non-RxSwift proxy and re-called the setter with its own proxy via full ObjC dispatch, re-entering Datadog's swizzle. Each re-entry created a new `DDProxy` and called `previousImplementation` again — infinite recursion.

The crash manifested in `responds(to:)` due to the circular delegation chain created by this loop: `DDProxy.originalDelegate = rxProxy` and `rxProxy.forwardTo = DDProxy`.

**Fixes applied:**
1. Re-entrancy guard in `UIScrollViewSwizzler.SetDelegate` using `scrollViewsBeingSet: Set<ObjectIdentifier>` — breaks cycles where a third-party swizzle re-calls the setter with its own proxy type
2. Proxy type guard in `SetDelegate` (`delegate is UIScrollViewDelegateProxy`) — prevents re-wrapping when our proxy comes back directly
3. Proxy reuse via associated objects in `SetDelegate` — avoids creating a new proxy on each setter call for the same scroll view
4. Re-entrancy guard in `UIScrollViewDelegateProxy.responds(to:)` using `isRespondingToSelector: Bool` — breaks circular `responds(to:)` chains when two proxies mutually reference each other

### RUM 3.8.0 — `collectionView.delegate as? CustomDelegate` returns nil (#2760)

**Symptom:** After upgrading to 3.8.0, customer code that cast `collectionView.delegate` to a custom type always returned `nil`. Type checks like `collectionView.delegate is MyDelegate` also failed.

**Root cause:** The setter swizzle wrapped the delegate in `UIScrollViewDelegateProxy`, but no getter swizzle was installed. Reading `collectionView.delegate` returned the proxy, not the original delegate. Any `as?` cast to the original type failed.

**Fix applied:** Added `UIScrollViewSwizzler.GetDelegate` swizzle that unwraps `UIScrollViewDelegateProxy` and returns `proxy.originalDelegate` transparently.

---

## Checklist for new swizzles

Before submitting a swizzle:

- [ ] Uses `MethodSwizzler` — no direct `method_setImplementation` calls
- [ ] Setter wrapping a value → getter swizzle installed that unwraps it
- [ ] Setter calls `previousImplementation` → re-entrancy guard keyed on object identity
- [ ] Proxy with `responds(to:)` / `forwardingTarget(for:)` → `isRespondingToSelector` guard
- [ ] `nil` assignment removes associated objects
- [ ] `unswizzle()` removes both setter and getter swizzles together
- [ ] Unit test for the proxy `responds(to:)` re-entrancy guard (circular proxy chain does not stack-overflow)
- [ ] Unit test for the setter re-entrancy guard (simulating a third-party swizzle that re-calls the setter with its own proxy type)
- [ ] Unit test confirming getter returns original value, not internal wrapper
