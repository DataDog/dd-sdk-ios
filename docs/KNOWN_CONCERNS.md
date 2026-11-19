# Known Concerns & Fragile Areas

These areas require extra caution when modifying. Changes here have caused production incidents or are inherently fragile.

| Area | Location | Risk |
|------|----------|------|
| **SwiftUI view name extraction** | `DatadogRUM/Sources/Instrumentation/Views/SwiftUI/` | Uses `Mirror`/`String(describing:)` reflection — fragile across Swift compiler versions. Do not change without extensive testing. |
| **UIKit method swizzling** | `DatadogRUM/Sources/Instrumentation/` | Depends on UIKit internal method signatures — iOS version changes could break silently. See `docs/SWIZZLING.md`. |
| **Async/await URLSession data capture** | `DatadogInternal/Sources/NetworkInstrumentation/URLSession/URLSessionSwizzler.swift` | Hooks private `-[NSURLSession _dataTaskWithRequest:delegate:completionHandler:]` / `_dataTaskWithURL:delegate:completionHandler:` (used by async `data(for:)` / `data(from:)`). Looked up at runtime with a type-encoding check; if Apple renames them, the hook is skipped and async data falls back to `nil`. |
| **KSCrash report parsing** | `DatadogCrashReporting/Sources/` | Parsing C-level crash reports depends on KSCrash output format |
| **Optional precondition in RUMSessionScope** | `RUMMonitor/Scopes/RUMSessionScope.swift` | Silent in production, crashes in debug — masks invalid state |
| **500 concurrent feature operations** | `RUMFeatureOperationManager.swift` | Active operations capped at 500 with `Set<String>` tracking |
| **Message bus queue unbounded** | `DatadogCore/Sources/Core/MessageBus.swift` | No queue depth limit — burst messaging could cause memory pressure |
| **User action 100ms window** | `RUMUserActionScope` | Discrete user actions have a hardcoded 100ms window — actions arriving after are dropped |
