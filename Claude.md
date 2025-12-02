# Claude Code Assistant Guide for dd-sdk-ios

> Specific instructions for Claude when working with the Datadog iOS SDK.

## Context

You are working on **dd-sdk-ios**, the official Datadog SDK for iOS and tvOS. This SDK runs inside customer applications on end-user devices. Every change must prioritize:

1. **Stability** - Zero crashes from SDK code
2. **Performance** - Minimal CPU, memory, and battery impact
3. **Compatibility** - Swift & Objective-C, iOS 12.0+

## Before Making Changes

### 1. Understand the Module Structure

```
DatadogInternal ← shared types, protocols
       ↑
DatadogCore ← initialization, pipeline, upload
       ↑
Feature modules (Logs, Trace, RUM, SessionReplay, etc.)
```

### 2. Check Cross-Module Impact

**⚠️ CRITICAL**: When changing code in any module, search for usages in:
- `DatadogCore/Sources/` - Core may call or register your changed code
- `DatadogInternal/Sources/` - Shared types may need updates
- Other feature modules that might depend on your changes

Use grep or codebase search to find all references before considering work complete.

### 3. Verify You Don't Need an RFC

Major changes require internal RFC approval. Flag to the engineer if your change:
- Modifies public API significantly
- Changes data collection behavior  
- Affects initialization or SDK lifecycle
- Needs cross-platform alignment (Android, Browser)

## Commit & PR Format

```
[RUM-XXXX] Brief description

Longer description if needed.
```

- **Prefix is mandatory**: `[RUM-XXXX]` with actual JIRA ticket number
- **Commits must be signed**: Unsigned commits will be rejected

## Code Style

### Swift Conventions

```swift
/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Documentation for public types is expected.
/// Use descriptive names that explain intent.
public struct ExampleType {
    /// Property documentation.
    public let property: String
    
    /// Initializer documentation.
    public init(property: String) {
        self.property = property
    }
}
```

### Key Style Rules

- Use `// TODO: RUM-XXX` format for TODOs (with JIRA ticket)
- Avoid `UIApplication.shared` → use `UIApplication.managedShared`
- Avoid `URLRequest.allHTTPHeaderFields` → use `URLRequest.value(forHTTPHeaderField:)`
- Explicit access control on all top-level declarations
- No force unwrapping in production code (`!`, `try!`, `as!`)

## Testing Patterns

### Follow Existing Conventions

Look at existing tests in the same module for patterns. Common patterns:

```swift
import XCTest
import TestUtilities
@testable import DatadogFeature

class FeatureTests: XCTestCase {
    func testBehavior() {
        // Given
        let mock = SomeMock.mockAny()
        
        // When
        let result = feature.doSomething(with: mock)
        
        // Then
        XCTAssertEqual(result, expected)
    }
}
```

### Mock Naming Convention

```swift
extension SomeType {
    static func mockAny() -> SomeType { /* any valid value */ }
    static func mockWith(specificParam: Value) -> SomeType { /* configured */ }
}
```

### Using DatadogCoreProxy

For testing features with the full SDK context:

```swift
let core = DatadogCoreProxy(context: .mockWith(service: "test"))
defer { core.flushAndTearDown() }

core.register(feature: MyFeature.mockAny())
// ... test interactions
let events = core.waitAndReturnEvents(of: MyFeature.self, ofType: MyEvent.self)
```

## Common Tasks

### Adding a New File

1. Include license header
2. Place in correct module's `Sources/` directory
3. Update module's public exports if public API
4. Add corresponding test file in `Tests/`

### Modifying DatadogInternal Types

These are shared across all modules. Changes here impact everything:

1. Search for all usages across the codebase
2. Update all call sites
3. Consider backwards compatibility
4. Run full test suite: `make test-ios-all`

### Modifying Public API

1. Consider if this needs RFC approval
2. Ensure Objective-C compatibility if applicable  
3. Run API surface verification: `make api-surface-verify`
4. Update documentation

### Working with Network Instrumentation

Network instrumentation code (like `BaggageHeaderMerger`) is sensitive:

- Must handle all edge cases gracefully (no crashes)
- Must be performant (runs on every request)
- Must follow W3C or relevant specifications precisely
- Test with malformed input

## Running Checks Locally

```bash
# Lint (run before committing)
./tools/lint/run-linter.sh

# Specific module tests
make test-ios SCHEME="DatadogInternal iOS"
make test-ios SCHEME="DatadogCore iOS"
make test-ios SCHEME="DatadogRUM iOS"

# Full test suite
make test-ios-all

# API surface check
make api-surface-verify
```

## What NOT to Do

❌ **Don't use force unwrapping** in production code  
❌ **Don't add dependencies** without strong justification  
❌ **Don't change public API** without considering RFC  
❌ **Don't forget call sites** in DatadogCore when modifying features  
❌ **Don't use unsafe APIs** like `UIApplication.shared`  
❌ **Don't skip tests** - all code must be tested  
❌ **Don't use TODO without JIRA** - use `TODO: RUM-XXX` format  

## Quick Debugging

### Find Module Dependencies
```bash
# Check what imports a module
grep -r "import DatadogInternal" --include="*.swift"
```

### Find Feature Registration
```bash
# How features are registered in Core
grep -r "register(feature:" DatadogCore/Sources/
```

### Check API Surface
```bash
# Current public API
cat api-surface-swift
cat api-surface-objc
```

## Getting Help

If uncertain about:
- **Architecture decisions** → Check `ZEN.md` for philosophy
- **Module structure** → Check `Package.swift`
- **Test patterns** → Look at existing tests in `Tests/` directories
- **Build issues** → Check `Makefile` for available commands

When in doubt, ask the engineer rather than making assumptions about SDK-wide impacts.

