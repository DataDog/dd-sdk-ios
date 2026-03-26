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
| nil check | Proxy reuse with wrong state when the property is later re-assigned |
| type check (`value is OurProxy`) | Re-wrapping when our own proxy is passed back directly |
| re-entrancy guard (`objectsBeingSet`) | Infinite recursion when a third-party swizzle wraps our proxy in its own and re-calls the setter via ObjC dispatch with a *different* delegate type |

The type check alone is **not sufficient** to prevent re-entrancy. It only fires when our proxy comes back verbatim. If a third-party framework stores our proxy as its forward target and re-calls the setter with *its* proxy, the type check passes but the re-entrancy guard catches it.

**Complete pattern:**

```swift
private static var proxyKey: Void?
private static var objectsBeingSet: Set<ObjectIdentifier> = []

// Inside swizzle closure:

// 1. Nil guard — just forward nil; the proxy will be released automatically
//    when the previous value is eventually deallocated (see Pattern 4).
guard let value = value else {
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

// 4. Normal path — create or reuse proxy keyed on value (see Pattern 4 below)
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

### 4. Proxy lifetime: attach the proxy to the value, not the receiver

When the swizzled setter installs a proxy keyed to the **value** being set (e.g. the delegate object), store the associated object on that value — not on the receiver (e.g. the scroll view).

**Why this matters:** The receiver typically holds the value through a `weak` reference. If the proxy is associated with the receiver, it stays alive as long as the receiver is alive — which is longer than the value. When the value is deallocated and the weak reference becomes `nil`, UIKit may have already cached `responds(to:) == true` for selectors the proxy advertised. On the next event UIKit dispatches the selector directly to the still-alive proxy, whose `originalDelegate` is now `nil`, causing an "unrecognized selector" crash.

By associating the proxy with the value itself, the proxy's lifetime equals the value's lifetime. When the value is released, the proxy is released with it, the receiver's weak reference naturally becomes `nil`, and UIKit stops dispatching to that proxy.

```swift
// WRONG — proxy outlives the delegate when delegate is released
objc_setAssociatedObject(scrollView, &Self.proxyKey, proxy, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

// CORRECT — proxy lifetime = delegate lifetime
objc_setAssociatedObject(delegate, &Self.proxyKey, proxy, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
```

**Corollary:** when reusing an existing proxy (found via `objc_getAssociatedObject(value, ...)`), always update mutable state that could be stale — specifically, the handler reference in case the SDK was stopped and re-initialized:

```swift
if let existingProxy = objc_getAssociatedObject(value, &Self.proxyKey) as? OurProxy {
    existingProxy.handler = handler  // update in case RUM was restarted with a new handler
    previousImplementation(object, selector, existingProxy)
}
```

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

### Pitfall: attaching the proxy to the receiver instead of the value

When the swizzled property holds a `weak` reference to the value (e.g. `UIScrollView.delegate` is `weak`), attaching the proxy to the receiver (e.g. the scroll view) means the proxy outlives the value it wraps. When the value is deallocated, the proxy is still alive and `originalDelegate` is `nil`. UIKit may dispatch cached selectors to the proxy — "unrecognized selector" crash.

**Fix:** attach the proxy to the value being set (Pattern 4 above). The proxy is then released with the value, and the receiver's weak property naturally becomes `nil`.

This also means you do **not** need to explicitly remove the associated object when the property is set to `nil`. Just forward `nil` and let ARC do the cleanup:

```swift
// Correct nil handling when proxy is on the value:
guard let value = value else {
    previousImplementation(object, selector, nil)
    return
}
// No manual objc_setAssociatedObject cleanup needed.
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

### RUM 3.8.3 — Crash after delegate deallocation in SwiftUI UICollectionView (#2776)

**Symptom:** Apps using SwiftUI's `List` or `ScrollView` (which internally use `UICollectionView`) crashed with "unrecognized selector sent to instance" after a view was dismissed and later interacted with again.

**Root cause:** `UIScrollViewSwizzler` stored the `UIScrollViewDelegateProxy` as an associated object on the **scroll view**. This tied the proxy's lifetime to the scroll view, not the delegate. When SwiftUI's internal delegate was deallocated (view dismissed), the proxy's `originalDelegate` became `nil`. However, UIKit had previously called `responds(to:)` on the proxy and cached the result (`true`) for scroll-related selectors. On the next scroll event UIKit dispatched the selector directly to the proxy — which forwarded to `forwardingTarget(for:)` — which returned `nil` (since `originalDelegate` was gone) — crash.

**Fix applied:** Changed `objc_setAssociatedObject` to key on the **delegate** instead of the scroll view (PR #2776). The proxy's lifetime now equals the delegate's lifetime. When the delegate is released, the proxy is released with it, `scrollView.delegate` (a `weak` reference) naturally becomes `nil`, and UIKit stops dispatching.

Additionally, when reusing an existing proxy on a delegate, the handler is now updated (`existingProxy.handler = handler`) in case RUM was stopped and re-initialized with a new handler instance.

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
- [ ] Proxy is associated with the **value** (not the receiver) so its lifetime matches the value's
- [ ] When reusing an existing proxy, mutable state (e.g. `handler`) is updated
- [ ] `unswizzle()` removes both setter and getter swizzles together
- [ ] Unit test for the proxy `responds(to:)` re-entrancy guard (circular proxy chain does not stack-overflow)
- [ ] Unit test for the setter re-entrancy guard (simulating a third-party swizzle that re-calls the setter with its own proxy type)
- [ ] Unit test confirming getter returns original value, not internal wrapper
