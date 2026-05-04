/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

// Reproduction tests for RUMS-5870:
// iOS SDK URLSession swizzle corrupts file-backed upload task body via unconditional KVC write.
//
// Root cause: NetworkInstrumentationFeature.bind(configuration:) installs a resume swizzle that
// calls task.dd.override(currentRequest:) unconditionally for every intercepted URLSessionTask,
// including __NSCFLocalUploadTask instances created by uploadTask(with:fromFile:).
// The KVC setValue(request, forKey: "currentRequest") replaces the task's internal _currentRequest
// ivar, severing the private file-body state binding. The task then has no body to upload, stalls,
// and eventually times out with NSURLErrorDomain -1001.
//
// These tests are intentionally FAILING before the fix is applied (except Test 1 which documents
// the guard gap that makes the bug reachable).

import XCTest
import TestUtilities
@_spi(Internal)
@testable import DatadogInternal

// MARK: - RUMS5870Tests

class RUMS5870Tests: XCTestCase {
    // swiftlint:disable implicitly_unwrapped_optional
    private var core: SingleFeatureCoreMock<NetworkInstrumentationFeature>!
    private var handler: URLSessionHandlerMock!
    // swiftlint:enable implicitly_unwrapped_optional

    override func setUpWithError() throws {
        try super.setUpWithError()
        core = SingleFeatureCoreMock()
        handler = URLSessionHandlerMock()
        try core.register(urlSessionHandler: handler)
    }

    override func tearDown() {
        core?.get(feature: NetworkInstrumentationFeature.self)?.flush()
        core = nil
        handler = nil
        super.tearDown()
    }

    // MARK: - Test 1 (unit): isSupportedForInstrumentation guard gap

    /// Documents that isSupportedForInstrumentation returns true for file-backed upload tasks,
    /// confirming the guard does NOT protect uploadTask(with:fromFile:) from the KVC write.
    ///
    /// This test documents the current (buggy) state: upload tasks created via fromFile: pass the
    /// instrumentation guard, so override(currentRequest:) is reachable for them. This test itself
    /// passes both before and after the fix — it documents a necessary invariant that must remain
    /// true (we can't simply skip all upload tasks from instrumentation).
    func testRUMS5870_isSupportedForInstrumentation_returnsTrueForFileBackedUploadTask() throws {
        // Given: a file-backed upload task
        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("rums5870-guard-\(UUID().uuidString).dat")
        try Data("hello-rums-5870".utf8).write(to: tempFile)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let session = URLSession(configuration: .ephemeral)
        let task = session.uploadTask(with: URLRequest(url: URL(string: "https://httpbin.org/post")!), fromFile: tempFile)
        defer { task.cancel() }

        // isSupportedForInstrumentation returns true — the guard does NOT protect upload tasks.
        // This means the swizzle closure proceeds to override(currentRequest:) for file-backed tasks.
        XCTAssertTrue(
            task.isSupportedForInstrumentation,
            "RUMS-5870: uploadTask(with:fromFile:) is not excluded by isSupportedForInstrumentation — " +
            "the guard does not protect it from the destructive KVC write"
        )

        XCTAssertTrue(task is URLSessionUploadTask)
    }

    // MARK: - Test 2 (unit): override(currentRequest:) called unconditionally — even with no trace injection

    /// KEY UNIT TEST: proves that the current code calls override(currentRequest:) unconditionally on
    /// ALL intercepted tasks, including file-backed upload tasks, even when no first-party hosts match
    /// and therefore NO trace headers are injected.
    ///
    /// The fix should guard the override call: only call it when traceContexts is non-empty
    /// (i.e., headers were actually injected). Until fixed, this test FAILS by demonstrating that
    /// override IS called even when it should be a no-op.
    ///
    /// Test strategy: spy on KVC writes to "currentRequest" by observing the object identity
    /// change on the task. Before the KVC write, currentRequest == originalRequest (same identity).
    /// After the KVC write (override call), currentRequest is a fresh URLRequest copy — different
    /// object, but with the same URL. For file-backed tasks, this replacement severs the body.
    func testRUMS5870_overrideCurrentRequest_calledUnconditionally_withNoTraceInjection() throws {
        // Given: automatic instrumentation with NO first-party hosts.
        // No first-party hosts → intercept(request:additionalFirstPartyHosts:) returns (original, []).
        // The fix: only call override when traceContexts is non-empty.
        try URLSessionInstrumentation.enableOrThrow(with: nil, in: core)

        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("rums5870-unit-\(UUID().uuidString).dat")
        let filePayload = Data("RUMS-5870-unit-payload".utf8)
        try filePayload.write(to: tempFile)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        // Use a real URLSession with no URLProtocol mock so we can observe the raw task state.
        // Point at TEST-NET-1 (192.0.2.1) — reserved address that never responds; task will
        // be cancelled before it times out.
        let session = URLSession(configuration: .ephemeral)
        var request = URLRequest(url: URL(string: "https://192.0.2.1/upload")!)
        request.httpMethod = "POST"
        let task = session.uploadTask(with: request, fromFile: tempFile)

        // Capture the object pointer of the original NSMutableURLRequest backing currentRequest.
        // After resume() fires the swizzle, override(currentRequest:) calls KVC setValue which
        // replaces the internal _currentRequest ivar with a new Swift URLRequest bridge object.
        let originalRequestPointer = task.currentRequest.map { ObjectIdentifier($0 as AnyObject) }

        // When: resume triggers the swizzle intercept closure which calls override(currentRequest:)
        task.resume()
        task.cancel()

        // Flush ensures the feature's queue has processed the intercept
        core.get(feature: NetworkInstrumentationFeature.self)?.flush()

        let postResumeRequestPointer = task.currentRequest.map { ObjectIdentifier($0 as AnyObject) }

        // BEFORE the fix: override(currentRequest:) is called unconditionally, so the KVC write
        // replaces _currentRequest. The pointer changes (new object). For file-backed tasks, this
        // severs the body.
        //
        // AFTER the fix: override is only called when trace headers were injected (traceContexts
        // non-empty). Since no first-party hosts are configured, no headers are injected, and
        // override should NOT be called. The pointer should remain unchanged.
        //
        // This assertion FAILS before the fix (pointer changes) and PASSES after (pointer stable).
        XCTAssertEqual(
            originalRequestPointer,
            postResumeRequestPointer,
            "RUMS-5870: override(currentRequest:) must NOT be called when no trace headers were " +
            "injected (no first-party hosts match). The KVC write replaces _currentRequest on " +
            "__NSCFLocalUploadTask, severing the file-body binding and causing NSURLErrorDomain -1001 timeouts."
        )
    }

    // MARK: - Test 3 (integration): modify(request:headerTypes:networkContext:) not called
    //         but override(currentRequest:) IS called — proves the guard gap in the call chain

    /// INTEGRATION TEST: proves that in the current (buggy) code, `override(currentRequest:)` is
    /// called on a file-backed upload task even when the handler's `modify(request:headerTypes:)` is
    /// NOT called (because no first-party hosts match, so no trace headers are injected).
    ///
    /// This is the exact guard gap. The fix should condition the override call on whether
    /// `modify` was actually invoked (i.e., traceContexts is non-empty).
    ///
    /// Proof: track whether `modify` was called (handler spy), AND track whether currentRequest
    /// changed (KVC write observable via pointer change). Pre-fix: modify NOT called, but
    /// currentRequest DOES change — override was called unconditionally. Post-fix: modify NOT
    /// called, currentRequest does NOT change — override is guarded.
    ///
    /// This assertion FAILS pre-fix because: modifyCalled == false AND requestChanged == true.
    func testRUMS5870_overrideCalledWithoutTraceInjection_forFileBackedUploadTask() throws {
        // Given: automatic instrumentation, NO first-party hosts → modify will NOT be called.
        try URLSessionInstrumentation.enableOrThrow(with: nil, in: core)

        var modifyCalled = false
        handler.onRequestMutation = { _, _, _ in modifyCalled = true }

        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("rums5870-guard2-\(UUID().uuidString).dat")
        try Data("RUMS-5870-guard-test".utf8).write(to: tempFile)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let session = URLSession(configuration: .ephemeral)
        var request = URLRequest(url: URL(string: "https://192.0.2.1/upload")!)
        request.httpMethod = "POST"
        let task = session.uploadTask(with: request, fromFile: tempFile)

        // Capture the currentRequest object pointer before the swizzle fires.
        let ptrBefore = task.currentRequest.map { ObjectIdentifier($0 as AnyObject) }

        // When: resume triggers the swizzle intercept closure.
        task.resume()
        task.cancel()
        core.get(feature: NetworkInstrumentationFeature.self)?.flush()

        let ptrAfter = task.currentRequest.map { ObjectIdentifier($0 as AnyObject) }
        let requestObjectChanged = (ptrBefore != ptrAfter)

        // Step 1: Confirm modify was NOT called (no first-party hosts → no trace injection).
        // This is expected and will pass both before and after the fix.
        XCTAssertFalse(
            modifyCalled,
            "modify(request:headerTypes:networkContext:) must not be called when no first-party hosts match"
        )

        // Step 2: Assert that since modify was not called (no trace headers injected),
        // override(currentRequest:) must NOT have been called either.
        // BEFORE fix: requestObjectChanged == true (override was called) → assertion FAILS.
        // AFTER fix: requestObjectChanged == false (override skipped) → assertion PASSES.
        XCTAssertFalse(
            requestObjectChanged,
            "RUMS-5870: override(currentRequest:) was called on a file-backed upload task even though " +
            "no trace headers were injected (modify was not called). This unconditional KVC write " +
            "severs the __NSCFLocalUploadTask file-body binding, causing NSURLErrorDomain -1001 timeouts. " +
            "The fix must guard the override call: skip it when traceContexts is empty."
        )
    }
}
