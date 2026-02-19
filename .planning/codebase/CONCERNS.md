# Concerns — dd-sdk-ios

## Tech Debt

### RUMM-2904: Retain cycle in ActiveSpansPool
- **Location:** `DatadogTrace/Sources/Span/OTSpan.swift`, `ActiveSpansPool`
- **Issue:** `span.setActive()` may create a retain cycle when span references the pool and pool references the span.
- **Risk:** Memory leak for long-lived spans.
- **Recommendation:** Use weak references in the pool's span storage.

### RUMM-1462 / RUM-4072: Missing register state in crash reports
- **Location:** `DatadogCrashReporting/Sources/`
- **Issue:** Crash reports may not include full register state, limiting root-cause analysis.
- **Risk:** Harder crash debugging for customers.

### RUM-3840: Fatal app hangs not tracked without active view
- **Location:** `DatadogRUM/Sources/RUMMonitor/Scopes/RUMViewScope.swift`
- **Issue:** Fatal hangs (watchdog kills) are only tracked when there is an active RUM view. Hangs during transitions or background are missed.
- **Risk:** Under-reporting of hang metrics.

### RUM-9892: Fragile SwiftUI view name extraction via reflection
- **Location:** `DatadogRUM/Sources/Instrumentation/Views/SwiftUI/`
- **Issue:** SwiftUI view names are extracted using `Mirror` / `String(describing:)` reflection. This is fragile across Swift compiler versions and obfuscation.
- **Risk:** View names may change unexpectedly between Xcode versions, breaking RUM analytics continuity.

### RUM-9888: Manual/auto SwiftUI instrumentation conflicts
- **Location:** `DatadogRUM/Sources/Instrumentation/Views/SwiftUI/`
- **Issue:** When both manual (`trackRUMView`) and automatic SwiftUI view tracking are enabled, duplicate or conflicting view events may be generated.
- **Risk:** Inflated view counts or confusing RUM data.

### RUM-1650: Optional precondition in RUMSessionScope
- **Location:** `DatadogRUM/Sources/RUMMonitor/Scopes/RUMSessionScope.swift`
- **Issue:** Contains a conditional precondition that may silently pass in production but fail in debug builds, masking invalid state.
- **Risk:** Hard-to-diagnose state management bugs.

### RUMM-3347: Hardcoded protocol extension defaults
- **Location:** Various protocol definitions across modules
- **Issue:** Default implementations in protocol extensions create implicit behavior that is hard to override and test.
- **Risk:** Unexpected behavior when conforming types don't override defaults.

### RUMM-1616: User action commands ignored after 100ms
- **Location:** `DatadogRUM/Sources/RUMMonitor/Scopes/RUMUserActionScope.swift`
- **Issue:** Discrete user actions have a hardcoded 100ms window. Actions arriving after this window are dropped.
- **Risk:** Legitimate user actions may be lost on slow devices or under load.

---

## Known Bugs

### RUMM-2250: Incomplete Session Replay records
- **Location:** `DatadogSessionReplay/Sources/`
- **Issue:** Some Session Replay records may be incomplete under memory pressure or rapid view transitions.

### RUMM-2452: Limited font recognition in Session Replay
- **Location:** `DatadogSessionReplay/Sources/Recorder/`
- **Issue:** Custom fonts may not be properly recognized during Session Replay recording, falling back to system fonts.

### Deprecated screenChangeScheduling flag
- **Location:** `DatadogRUM/Sources/RUMConfiguration.swift`
- **Issue:** Legacy configuration flag still present but marked for removal.

---

## Security Considerations

### Method swizzling risks
- **Location:** `DatadogRUM/Sources/Instrumentation/`, `DatadogURLSessionTracking/Sources/`
- **Issue:** UIKit/Foundation method swizzling can conflict with other SDKs or customer code performing similar swizzling. Framework coupling is tight.
- **Mitigation:** Swizzling is opt-in and documented. Conflicts are logged via `DD.logger`.

### Unsafe memory operations (C interop)
- **Location:** `DatadogCrashReporting/Sources/`, KSCrash integration
- **Issue:** C interop for crash reporting involves unsafe pointer operations.
- **Mitigation:** Operations are isolated to crash reporting module with defensive bounds checking.

### JSON serialization safety
- **Location:** `DatadogInternal/Sources/MessageBus/`, event encoding throughout
- **Issue:** Malformed or excessively large JSON payloads could cause issues.
- **Mitigation:** Well-mitigated with `Codable` and size limits on event storage.

---

## Performance Bottlenecks

### Reflection-based view name extraction
- **Location:** `DatadogRUM/Sources/Instrumentation/Views/SwiftUI/`
- **Impact:** `Mirror` reflection on every SwiftUI view appearance adds overhead, particularly for complex view hierarchies.

### O(n) span pool removal
- **Location:** `DatadogTrace/Sources/Span/ActiveSpansPool.swift`
- **Impact:** Linear scan to remove spans from the active pool. Acceptable for typical span counts (<100) but could degrade with heavy tracing.

### Full backtrace collection for logs
- **Location:** `DatadogLogs/Sources/`
- **Impact:** Collecting backtraces for log events adds measurable overhead. Should remain opt-in.

### View scope hierarchy iteration
- **Location:** `DatadogRUM/Sources/RUMMonitor/Scopes/`
- **Impact:** Every RUM command traverses the full scope hierarchy (Application → Session → View). Deep hierarchies or rapid event bursts could add latency.

---

## Fragile Areas

### UIKit method swizzling
- **Location:** `DatadogRUM/Sources/Instrumentation/`
- **Why fragile:** Depends on UIKit internal method signatures. iOS version changes could break swizzled methods silently.

### SwiftUI reflection dependencies
- **Location:** `DatadogRUM/Sources/Instrumentation/Views/SwiftUI/`
- **Why fragile:** `String(describing:)` output format is not a stable API. Compiler or runtime changes can alter output.

### KSCrash report parsing
- **Location:** `DatadogCrashReporting/Sources/`
- **Why fragile:** Parsing C-level crash reports depends on KSCrash's output format, which may change across versions.

### Optional precondition state management
- **Location:** `DatadogRUM/Sources/RUMMonitor/Scopes/RUMSessionScope.swift`
- **Why fragile:** Silent state corruption in production vs. hard crash in debug creates inconsistent behavior.

---

## Scaling Limits

### 500 concurrent feature operations
- **Location:** `DatadogRUM/Sources/RUMMonitor/Scopes/RUMFeatureOperationManager.swift`
- **Limit:** Active operations capped at 500 with `Set<String>` tracking. Exceeded operations are logged and dropped.

### View scope hierarchy depth
- **Location:** `DatadogRUM/Sources/RUMMonitor/Scopes/`
- **Limit:** No explicit depth limit on nested scopes. Deeply nested navigation could grow memory usage.

### Message bus queue unbounded
- **Location:** `DatadogCore/Sources/Core/MessageBus/`
- **Limit:** Inter-module message bus does not enforce queue depth limits. Burst messaging could cause memory pressure.

---

## Dependencies at Risk

### KSCrash (external C library)
- **Used by:** `DatadogCrashReporting`
- **Risk:** C library with complex memory management. Updates may change crash report format. Limited Swift-native alternatives.

### PLCrashReporter
- **Used by:** `DatadogCrashReporting` (alternative crash reporter)
- **Risk:** Microsoft-maintained. Release cadence may not match Datadog's needs.

### OpenTelemetry Swift Packages
- **Used by:** `DatadogTrace`
- **Risk:** Two compilation modes (lightweight mirror vs full OTEL SDK). Full SDK mode requires iOS 13+ and adds significant dependency tree.

### zlib (compression)
- **Used by:** Event upload compression
- **Risk:** Low risk — system library. But compression failures could silently drop events if not handled.
