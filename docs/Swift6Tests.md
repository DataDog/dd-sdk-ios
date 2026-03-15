# Testing Approach for Swift 6 Concurrency

This document outlines the testing conventions adopted as part of the Swift 6 migration, particularly around structured concurrency, async/await, and mock design.

## Async Tests

With Swift 6's strict concurrency model, many operations that were previously synchronous (e.g., writing events via `Writer`) are now `async`. Tests should reflect this naturally:

- **Prefer `async throws` test methods** when the code under test performs asynchronous work (e.g., `Task.detached` writes, actor-isolated calls). This avoids blocking the main thread and makes intent explicit.
- **Use polling helpers** like `waitForEvents(count:timeout:)` or `waitForWrittenEvents(count:timeout:)` on mocks to await asynchronous side effects instead of relying on synchronous assertions that may race.
- **Do not convert synchronous tests to async unnecessarily.** If the code under test is synchronous and has no concurrency concerns, a plain `throws` test is fine.

```swift
// Good: async test awaiting asynchronous writes
func testSpanIsWritten() async throws {
    let core = PassthroughCoreMock()
    let tracer: DatadogTracer = .mockWith(core: core)
    let span = tracer.startSpan(operationName: "op")

    span.finish()
    await core.writer.waitForEvents(count: 1)

    let events: [SpanEventsEnvelope] = core.events()
    XCTAssertEqual(events.count, 1)
}
```

## Framework-Agnostic Mocks

Mocks in `TestUtilities` must not depend on any specific testing framework. This allows them to be used with both XCTest and Swift Testing (`@Test`).

- **Do not `import XCTest`** in mock files.
- **Do not call `XCTFail`, `XCTAssert*`, or use `XCTestExpectation`** inside mocks.
- Mocks should expose observable state (e.g., `events`, `receivedCommands`) and async wait helpers. Assertions belong exclusively in the test methods themselves.

```swift
// Good: framework-agnostic mock with async polling
public class FileWriterMock: Writer {
    @ReadWriteLock
    private var _events: [Encodable] = []

    public var events: [Encodable] { _events }

    public func waitForEvents(count: Int, timeout: TimeInterval = 1.0) async {
        let deadline = Date().addingTimeInterval(timeout)
        while events.count < count && Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    public func write<T: Encodable, M: Encodable>(value: T, metadata: M?) async {
        __events.mutate { $0.append(value) }
    }
}
```

## Removing Expectations

`XCTestExpectation` and `waitForExpectations(timeout:)` introduce boilerplate and force test classes onto `@MainActor` (since `waitForExpectations` is main-actor-isolated in Swift 6). Prefer async/await alternatives:

| Instead of | Use |
|---|---|
| `expectation(description:)` + `fulfill()` + `waitForExpectations(timeout:)` | `await mock.waitForEvents(count:)` |
| `onWrite` / `onEventWritten` callbacks wired to expectations | Direct `await` on the mock's async polling helper |
| `@MainActor` on test class (only needed for `waitForExpectations`) | Remove `@MainActor` and use `async` test methods |

Expectations are still appropriate when:
- Waiting for delegate callbacks or notification-driven events with no async equivalent.
- Coordinating multiple independent asynchronous signals where polling would be awkward.

## Thread Safety in Mocks

Mocks that receive writes from `Task.detached` or other concurrent contexts must protect their internal state:

- Use `@ReadWriteLock` (from `DatadogInternal`) on mutable storage arrays.
- Mutate through the projected `__property.mutate { }` API to ensure atomic appends.

```swift
@ReadWriteLock
private var _events: [Encodable] = []

public func write<T: Encodable, M: Encodable>(value: T, metadata: M?) async {
    __events.mutate { $0.append(value) }
}
```

Without this, concurrent writes can silently drop events, causing flaky test timeouts.
