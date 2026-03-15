# DatadogWebViewTracking — Architecture Review

Performance and memory observations for the `DatadogWebViewTracking` module.
These are findings from reviewing the current architecture, not breaking issues.

---

## Current data flow

```
Browser SDK (JS)
  │
  │  window.DatadogEventBridge.send(jsonString)
  ▼
WKScriptMessage.body: Any  (String passed from JS)
  │
  ▼
DDScriptMessageHandler.userContentController(_:didReceive:)     [@MainActor]
  │
  │  cast body to String
  ▼
MessageEmitter.send(body:slotId:)                               [@MainActor]
  │
  │  String → Data (UTF-8 copy)
  │  JSONDecoder() → WebViewMessage (via AnyDecodable)
  ▼
core.send(message: .webview(message))                           [message bus]
```

---

## 1. JSONDecoder allocated on every message

A new `JSONDecoder()` is created on every call to `MessageEmitter.send()`.
`JSONDecoder` is a class — each instantiation allocates on the heap.

```swift
// Current: allocates on every call
let decoder = JSONDecoder()
let message = try decoder.decode(WebViewMessage.self, from: data)
```

**Suggestion:** Store the decoder as a property on `MessageEmitter`. It has
no custom configuration, so a single instance can be reused safely:

```swift
private let decoder = JSONDecoder()
```

**Impact:** Eliminates one heap allocation per incoming message. Small but
on the hot path — high-frequency WebView events (scroll, tap, resource
loading) may fire many messages per second.

---

## 2. JSONDecoder + AnyDecodable is slower than JSONSerialization

The current decoding path does:

1. Cast `body` from `Any` to `String`
2. Copy the string's bytes into a new `Data` allocation (`.data(using: .utf8)`)
3. Feed `Data` into `JSONDecoder`
4. `JSONDecoder` invokes `AnyDecodable.init(from:)`, which tries to decode
   as `Bool`, `Int`, `Int64`, `UInt`, `UInt64`, `Double`, `String`, `Array`,
   `Dictionary` — **up to 8 `try?` attempts per JSON value**
5. The result is `[String: Any]` (the `WebViewMessage.Event` typealias)

`JSONSerialization.jsonObject(with:)` produces the same `[String: Any]`
output directly, without the `AnyDecodable` trial-and-error overhead:

```swift
let jsonObject = try JSONSerialization.jsonObject(with: data)
guard let dict = jsonObject as? [String: Any] else { ... }
```

**Trade-off:** This would bypass the `Decodable` conformance on
`WebViewMessage`, requiring manual extraction of `eventType` and routing.
The current `Decodable` approach is cleaner to read. Worth considering only
if profiling shows decoding as a bottleneck.

**Alternative (smaller change):** Keep `Decodable` for `eventType` routing
but avoid `AnyDecodable` for the event payload. Decode only the `eventType`
and `view` fields via `Codable`, then use `JSONSerialization` for the raw
`event` dictionary. This is a hybrid approach that keeps the clean routing
while avoiding the expensive `AnyDecodable` recursion on the payload.

---

## 3. String → Data copy on every message

```swift
guard let data = body.data(using: .utf8) else { ... }
```

This allocates a new `Data` buffer and copies the string's UTF-8 bytes.
For large RUM view events (the test fixture is ~1.2 KB of JSON), this is
a non-trivial copy on the main thread.

If switching to `JSONSerialization` (section 2), `jsonObject(with:)` accepts
`Data`. The copy is unavoidable with the current approach.

If keeping `JSONDecoder`, the copy is also required since `JSONDecoder.decode`
takes `Data`.

**Mitigation:** This becomes less relevant if the JSON parsing itself is moved
off the main thread (see section 5).

---

## 4. AbstractMessageEmitter class hierarchy

`MessageEmitter` inherits from `InternalExtension<WebViewTracking>.AbstractMessageEmitter`,
which inherits from `NSObject` (implicitly, via the class chain):

```
NSObject
  └── AbstractMessageEmitter       (public, in extension on InternalExtension)
        └── MessageEmitter         (internal, final class)
```

This exists to provide a cross-platform API — Flutter, React Native, and
KMP SDKs create `MessageEmitter` instances via the
`WebViewTracking._dd.messageEmitter(in:)` factory.

**Observations:**
- `AbstractMessageEmitter` is a class with an empty `send()` method acting
  as a virtual method. A protocol with a default extension would be lighter
  (no vtable, no class metadata, no heap allocation for the protocol witness),
  but this is a **public API** change and would affect cross-platform SDKs.
- The `send(body: Any, ...)` signature uses `Any`, preventing the compiler
  from optimising the call site. This is inherent to the cross-platform
  bridge design where JS messages arrive as untyped values.

**Verdict:** Not worth changing — the cross-platform API contract matters
more than the marginal overhead of one class in the hierarchy.

---

## 5. All work runs on the main thread

After the Swift 6 migration, the entire pipeline — from receiving the
`WKScriptMessage` to JSON decoding to dispatching on the message bus — runs
synchronously on `@MainActor`.

For typical WebView messages (small JSON, fast routing), this is fine. But
if a page generates a burst of messages (e.g. rapid scroll events, many
resource loads), the JSON decoding accumulates on the main thread.

**Current cost per message on main thread:**
- 1 `String` cast
- 1 `Data` allocation + UTF-8 copy
- 1 `JSONDecoder` allocation (fixable — see section 1)
- Full JSON parse via `AnyDecodable` (recursive trial-and-error)
- 1 message bus dispatch

**Potential optimisation (future):**
Move the JSON decoding to a background context. The `DDScriptMessageHandler`
would capture the string body on the main thread and dispatch decoding
elsewhere. This was essentially what the removed `DispatchQueue` did.

However, this reintroduces the `Sendable` complexity that was removed during
the Swift 6 migration. Only justified if profiling shows main-thread pressure
from WebView message decoding.

**Verdict:** Keep current design unless profiling indicates a problem. The
simplicity of synchronous `@MainActor` outweighs the theoretical risk.

---

## 6. WKUserContentController retains the message handler

`WKUserContentController.add(_:name:)` retains the `WKScriptMessageHandler`
strongly. This creates a retention chain:

```
WKWebView
  └── .configuration.userContentController
        └── DDScriptMessageHandler  (strong)
              └── MessageEmitter    (strong)
                    └── core        (weak ✓)
```

The `weak var core` in `MessageEmitter` prevents a retain cycle back to the
SDK core. However, `DDScriptMessageHandler` itself is retained for the
lifetime of the `WKUserContentController`.

**Important:** `disable(webView:)` **must** be called before the WebView is
deallocated. If not called, the handler (and its emitter) leak for the
lifetime of the content controller. The doc comment already states this
requirement.

**Potential improvement:** Consider using `WKScriptMessageHandlerWithReply`
(iOS 14+) or a weak-wrapping proxy pattern to break the strong reference.
The weak proxy approach is common in WebKit:

```swift
class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var delegate: WKScriptMessageHandler?
    func userContentController(..., didReceive message: WKScriptMessage) {
        delegate?.userContentController(..., didReceive: message)
    }
}
```

This would make `disable()` optional for cleanup (the handler auto-nils
when the real handler is deallocated). However, this changes behaviour —
the current design intentionally keeps the handler alive until explicit
disable, which is correct for tracking semantics.

**Verdict:** Current design is correct. Document the `disable()` requirement
prominently.

---

## 7. Duplicate-tracking check scans all user scripts

```swift
let isTracking = controller.userScripts.contains {
    $0.source.starts(with: Self.jsCodePrefix)
}
```

This iterates all user scripts on the controller and checks each script's
source string prefix. If the app or third-party libraries add many user
scripts, this linear scan runs on every `enable()` call.

**Impact:** Negligible — `enable()` is called once per WebView, not on the
hot path. The number of user scripts is typically small (< 10).

---

## Summary

| Finding | Impact | Action |
|---------|--------|--------|
| JSONDecoder allocated per message | Low–Medium | Store as property on `MessageEmitter` |
| AnyDecodable slower than JSONSerialization | Medium | Consider hybrid approach if profiling shows bottleneck |
| String → Data copy per message | Low | Unavoidable with current API |
| Class hierarchy for cross-platform | Low | Keep — public API contract |
| All work on main thread | Low (currently) | Monitor; re-evaluate if message bursts cause frame drops |
| Handler retained by WKUserContentController | Known | Document `disable()` requirement; weak proxy is optional |
| User script scan in `enable()` | Negligible | No action needed |

### Quick win

Storing the `JSONDecoder` as a property is a one-line change with zero risk:

```swift
internal final class MessageEmitter: ... {
    private let decoder = JSONDecoder()
    ...
    override func send(body: Any, slotId: String? = nil) {
        ...
        let message = try decoder.decode(WebViewMessage.self, from: data)
        ...
    }
}
```
