/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
@_spi(Internal)
@testable import DatadogInternal
@_spi(Internal)
@testable import DatadogCore
@testable import DatadogRUM

private struct FeatureMock: DatadogRemoteFeature {
    static let name: String = "mock"

    struct Event: Encodable {
        let event: String
    }

    var requestBuilder: FeatureRequestBuilder = FeatureRequestBuilderMock()
    var messageReceiver: FeatureMessageReceiver = FeatureMessageReceiverMock()
    var performanceOverride: PerformancePresetOverride? = nil
}

private final class PendingHTTPClientMock: HTTPClient {
    private typealias Completion = (Result<(HTTPURLResponse, Data?), any Error>) -> Void

    private let queue = DispatchQueue(label: "com.datadoghq.PendingHTTPClientMock-\(UUID().uuidString)")
    private var requests: [URLRequest] = []
    private var completions: [Completion] = []

    func send(
        request: URLRequest,
        delegate: URLSessionTaskDelegate?,
        completion: @escaping (Result<(HTTPURLResponse, Data?), any Error>) -> Void
    ) {
        queue.sync {
            requests.append(request)
            completions.append(completion)
        }
    }

    func requestsSent() -> [URLRequest] {
        queue.sync {
            requests
        }
    }
}

class DatadogCoreTests: XCTestCase {
    override func setUp() {
        super.setUp()
        temporaryCoreDirectory.create()
    }

    override func tearDown() {
        temporaryCoreDirectory.delete()
        super.tearDown()
    }

    func testCoreAndFeatureScopeHaveNoHandoffOwnerBeforeActivation() {
        let core = DatadogCore(
            directory: temporaryCoreDirectory,
            dateProvider: SystemDateProvider(),
            initialConsent: .notGranted,
            performance: .mockAny(),
            httpClient: HTTPClientMock(),
            encryption: nil,
            contextProvider: .mockAny(),
            applicationVersion: .mockAny(),
            maxBatchesPerUpload: 1,
            backgroundTasksEnabled: false
        )
        defer { core.stop() }
        let scope = core.scope(for: FeatureMock.self)

        XCTAssertNil(RUMContextHandoff.owner(in: core))
        XCTAssertNil(RUMContextHandoff.owner(in: scope))
        core.stop()
        XCTAssertNil(RUMContextHandoff.owner(in: scope))
    }

    private func handoffValue(_ name: String) -> RUMContextHandoff.CurrentValue {
        RUMContextHandoff.CurrentValue(
            rumContext: .mockWith(viewID: name),
            sceneIdentifier: name,
            hasPendingUserAction: false,
            excludedUserActionID: nil
        )
    }

    private var supportsHandoffScope: Bool {
        #if os(iOS)
        if #available(iOS 27.0, *) {
            return true
        }
        #endif
        return false
    }

    func testHandoffExecutionScopeRestoresNestedOwnersAndResult() {
        guard supportsHandoffScope else {
            return
        }
        let first = RUMContextHandoff.Owner()
        let second = RUMContextHandoff.Owner()
        var calls = 0
        let result = RUMContextHandoff.withValue(handoffValue("first"), for: first) {
            calls += 1
            XCTAssertEqual(RUMContextHandoff.current(for: first)?.rumContext?.viewID, "first")
            let nested = RUMContextHandoff.withValue(handoffValue("second"), for: second) {
                XCTAssertNil(RUMContextHandoff.current(for: first))
                XCTAssertEqual(RUMContextHandoff.current(for: second)?.rumContext?.viewID, "second")
                return 42
            }
            XCTAssertEqual(RUMContextHandoff.current(for: first)?.rumContext?.viewID, "first")
            XCTAssertNil(RUMContextHandoff.current(for: second))
            return nested
        }
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(result, 42)
        XCTAssertNil(RUMContextHandoff.current(for: first))
        XCTAssertNil(RUMContextHandoff.current(for: second))
    }

    func testHandoffExecutionScopePreservesAuthoritativeNilAndActionFields() throws {
        guard supportsHandoffScope else {
            return
        }
        let owner = RUMContextHandoff.Owner()
        try RUMContextHandoff.withValue(handoffValue("outer"), for: owner) {
            let empty = RUMContextHandoff.CurrentValue(
                rumContext: nil,
                sceneIdentifier: "attached",
                hasPendingUserAction: true,
                excludedUserActionID: "previous"
            )
            try RUMContextHandoff.withValue(empty, for: owner) {
                let value = try XCTUnwrap(RUMContextHandoff.current(for: owner))
                XCTAssertNil(value.rumContext)
                XCTAssertEqual(value.sceneIdentifier, "attached")
                XCTAssertTrue(value.hasPendingUserAction)
                XCTAssertEqual(value.excludedUserActionID, "previous")
            }
            XCTAssertEqual(RUMContextHandoff.current(for: owner)?.rumContext?.viewID, "outer")
        }
        XCTAssertNil(RUMContextHandoff.current(for: owner))
    }

    func testHandoffExecutionScopeRestoresAfterSyncThrow() throws {
        guard supportsHandoffScope else {
            return
        }
        let owner = RUMContextHandoff.Owner()
        var calls = 0
        try RUMContextHandoff.withValue(handoffValue("outer"), for: owner) {
            XCTAssertThrowsError(try RUMContextHandoff.withValue(handoffValue("inner"), for: owner) {
                calls += 1
                XCTAssertEqual(RUMContextHandoff.current(for: owner)?.sceneIdentifier, "inner")
                throw HandoffScopeTestError.expected
            }) { error in
                XCTAssertEqual(error as? HandoffScopeTestError, .expected)
            }
            XCTAssertEqual(RUMContextHandoff.current(for: owner)?.sceneIdentifier, "outer")
        }
        XCTAssertEqual(calls, 1)
        XCTAssertNil(RUMContextHandoff.current(for: owner))
    }

    func testHandoffExecutionScopeSeparatesConcurrentThreads() {
        guard supportsHandoffScope else {
            return
        }
        let first = RUMContextHandoff.Owner()
        let second = RUMContextHandoff.Owner()
        let entered = expectation(description: "both scopes entered")
        entered.expectedFulfillmentCount = 2
        let finished = expectation(description: "both scopes returned")
        finished.expectedFulfillmentCount = 2
        let release = DispatchSemaphore(value: 0)
        for (owner, peer, name) in [(first, second, "first"), (second, first, "second")] {
            DispatchQueue.global().async {
                defer { finished.fulfill() }
                RUMContextHandoff.withValue(self.handoffValue(name), for: owner) {
                    entered.fulfill()
                    XCTAssertEqual(release.wait(timeout: .now() + 5), .success)
                    XCTAssertEqual(RUMContextHandoff.current(for: owner)?.sceneIdentifier, name)
                    XCTAssertNil(RUMContextHandoff.current(for: peer))
                }
                XCTAssertNil(RUMContextHandoff.current(for: owner))
            }
        }
        wait(for: [entered], timeout: 5)
        release.signal()
        release.signal()
        wait(for: [finished], timeout: 5)
    }

    func testHandoffExecutionScopeSeparatesConcurrentTasks() async {
        guard supportsHandoffScope else {
            return
        }
        let first = RUMContextHandoff.Owner()
        let second = RUMContextHandoff.Owner()
        let barrier = HandoffScopeTestGate()
        let firstTask = RUMContextHandoff.withValue(handoffValue("first"), for: first) {
            Task {
                await barrier.arriveAndWait()
                await Task.yield()
                XCTAssertNil(RUMContextHandoff.current(for: second))
                return RUMContextHandoff.current(for: first)?.sceneIdentifier
            }
        }
        let secondTask = RUMContextHandoff.withValue(handoffValue("second"), for: second) {
            Task {
                await barrier.arriveAndWait()
                await Task.yield()
                XCTAssertNil(RUMContextHandoff.current(for: first))
                return RUMContextHandoff.current(for: second)?.sceneIdentifier
            }
        }
        let firstValue = await firstTask.value
        let secondValue = await secondTask.value
        XCTAssertEqual(firstValue, "first")
        XCTAssertEqual(secondValue, "second")
        XCTAssertNil(RUMContextHandoff.current(for: first))
        XCTAssertNil(RUMContextHandoff.current(for: second))
    }

    func testHandoffExecutionScopeInheritedTaskRetainsBindingAfterParentReturns() async {
        let owner = RUMContextHandoff.Owner()
        let gate = HandoffScopeTestGate()
        let task = RUMContextHandoff.withValue(handoffValue("parent"), for: owner) {
            Task {
                await gate.wait()
                return RUMContextHandoff.current(for: owner)?.sceneIdentifier
            }
        }
        XCTAssertNil(RUMContextHandoff.current(for: owner))
        await gate.release()
        let actual = await task.value
        XCTAssertEqual(actual, supportsHandoffScope ? "parent" : nil)
    }

    func testHandoffExecutionScopeDetachedTaskDoesNotInherit() async {
        guard supportsHandoffScope else {
            return
        }
        let owner = RUMContextHandoff.Owner()
        let task = RUMContextHandoff.withValue(handoffValue("parent"), for: owner) {
            XCTAssertEqual(RUMContextHandoff.current(for: owner)?.sceneIdentifier, "parent")
            return Task.detached {
                RUMContextHandoff.current(for: owner)?.sceneIdentifier
            }
        }
        let actual = await task.value
        XCTAssertNil(actual)
        XCTAssertNil(RUMContextHandoff.current(for: owner))
    }

    func testHandoffExecutionScopeRejectsForeignCoreOwner() throws {
        guard supportsHandoffScope else {
            return
        }
        let first = makeHandoffCore()
        let second = makeHandoffCore()
        defer { first.stop(); second.stop() }
        let firstOwner = try first.activateRUMContextHandoff()
        let secondOwner = try second.activateRUMContextHandoff()
        RUMContextHandoff.withValue(handoffValue("first"), for: firstOwner) {
            XCTAssertNil(RUMContextHandoff.current(for: secondOwner))
            RUMContextHandoff.withValue(handoffValue("second"), for: secondOwner) {
                XCTAssertNil(RUMContextHandoff.current(for: firstOwner))
                XCTAssertEqual(RUMContextHandoff.current(for: secondOwner)?.sceneIdentifier, "second")
            }
            XCTAssertEqual(RUMContextHandoff.current(for: firstOwner)?.sceneIdentifier, "first")
        }
    }

    func testHandoffExecutionScopeRejectsStoppedAndReinitializedOwner() async throws {
        guard supportsHandoffScope else {
            return
        }
        let oldCore = makeHandoffCore()
        let oldOwner = try oldCore.activateRUMContextHandoff()
        let gate = HandoffScopeTestGate()
        let captured = RUMContextHandoff.withValue(handoffValue("old"), for: oldOwner) {
            Task {
                await gate.wait()
                return RUMContextHandoff.current(for: oldOwner)?.sceneIdentifier
            }
        }
        oldCore.stop()
        let newCore = makeHandoffCore()
        defer { newCore.stop() }
        let newOwner = try newCore.activateRUMContextHandoff()
        XCTAssertFalse(oldOwner.isValid)
        XCTAssertTrue(newOwner.isValid)
        XCTAssertFalse(oldOwner === newOwner)
        RUMContextHandoff.withValue(handoffValue("old"), for: oldOwner) {
            XCTAssertNil(RUMContextHandoff.current(for: oldOwner))
            XCTAssertNil(RUMContextHandoff.current(for: newOwner))
        }
        RUMContextHandoff.withValue(handoffValue("new"), for: newOwner) {
            XCTAssertEqual(RUMContextHandoff.current(for: newOwner)?.sceneIdentifier, "new")
        }
        await gate.release()
        let actual = await captured.value
        XCTAssertNil(actual)
    }

    func testHandoffExecutionScopeDoesNotRetainCore() async throws {
        guard supportsHandoffScope else {
            return
        }
        var core: DatadogCore? = makeHandoffCore()
        weak var weakCore = core
        let owner = try XCTUnwrap(core).activateRUMContextHandoff()
        let gate = HandoffScopeTestGate()
        let captured = RUMContextHandoff.withValue(handoffValue("retained value"), for: owner) {
            Task {
                await gate.wait()
                return RUMContextHandoff.current(for: owner)?.sceneIdentifier
            }
        }
        core?.flush()
        core?.stop()
        core = nil
        XCTAssertNil(weakCore)
        XCTAssertFalse(owner.isValid)
        await gate.release()
        let actual = await captured.value
        XCTAssertNil(actual)
    }

    func testHandoffExecutionScopeMissingOrInvalidOwnerRunsFallbackOnce() {
        guard supportsHandoffScope else {
            return
        }
        let active = RUMContextHandoff.Owner()
        let invalid = RUMContextHandoff.Owner()
        invalid.invalidate()
        let owners: [RUMContextHandoff.Owner?] = [
            nil,
            RUMContextHandoff.owner(in: PassthroughCoreMock()),
            RUMContextHandoff.owner(in: NOPDatadogCore()),
            invalid
        ]
        RUMContextHandoff.withValue(handoffValue("outer"), for: active) {
            for owner in owners {
                var calls = 0
                let result = RUMContextHandoff.withValue(handoffValue("fallback"), for: owner) {
                    calls += 1
                    XCTAssertNil(RUMContextHandoff.current(for: owner))
                    XCTAssertEqual(RUMContextHandoff.current(for: active)?.sceneIdentifier, "outer")
                    return 7
                }
                XCTAssertEqual(result, 7)
                XCTAssertEqual(calls, 1)
            }
        }
    }

    func testHandoffExecutionScopeEnclosingTaskGroupPreservesOwnership() async {
        guard supportsHandoffScope else {
            return
        }
        let owner = RUMContextHandoff.Owner()
        let task = RUMContextHandoff.withValue(handoffValue("group"), for: owner) {
            Task {
                await withTaskGroup(of: String?.self) { group in
                    for _ in 0..<2 {
                        group.addTask {
                            await Task.yield()
                            return RUMContextHandoff.current(for: owner)?.sceneIdentifier
                        }
                    }
                    var results: [String?] = []
                    for await result in group { results.append(result) }
                    return results
                }
            }
        }
        let results = await task.value
        XCTAssertEqual(results, ["group", "group"])
        XCTAssertNil(RUMContextHandoff.current(for: owner))
    }

    func testHandoffExecutionScopeInsideTaskGroupChildPreservesOwnership() async {
        guard supportsHandoffScope else {
            return
        }
        let first = RUMContextHandoff.Owner()
        let second = RUMContextHandoff.Owner()
        let results = await withTaskGroup(of: String?.self) { group in
            for (owner, peer, name) in [(first, second, "first"), (second, first, "second")] {
                group.addTask {
                    RUMContextHandoff.withValue(self.handoffValue(name), for: owner) {
                        XCTAssertNil(RUMContextHandoff.current(for: peer))
                        return RUMContextHandoff.current(for: owner)?.sceneIdentifier
                    }
                }
            }
            var results: [String?] = []
            for await result in group { results.append(result) }
            return results.compactMap { $0 }.sorted()
        }
        XCTAssertEqual(results, ["first", "second"])
        XCTAssertNil(RUMContextHandoff.current(for: first))
        XCTAssertNil(RUMContextHandoff.current(for: second))
    }

    func testHandoffExecutionScopePreservesSyncOperationOnSupportedAndUnsupportedSystems() {
        let owner = RUMContextHandoff.Owner()
        var calls = 0
        let result = RUMContextHandoff.withValue(handoffValue("value"), for: owner) {
            calls += 1
            XCTAssertEqual(RUMContextHandoff.current(for: owner)?.sceneIdentifier, supportsHandoffScope ? "value" : nil)
            return 23
        }
        XCTAssertEqual(result, 23)
        XCTAssertEqual(calls, 1)
        XCTAssertThrowsError(try RUMContextHandoff.withValue(handoffValue("value"), for: owner) {
            calls += 1
            throw HandoffScopeTestError.expected
        }) { error in
            XCTAssertEqual(error as? HandoffScopeTestError, .expected)
        }
        XCTAssertEqual(calls, 2)
        XCTAssertNil(RUMContextHandoff.current(for: owner))
    }

    func testHandoffCallbackScopeCopiesSyncBindingIntoExternalTaskGroup() async {
        guard supportsHandoffScope else {
            return
        }
        let owner = RUMContextHandoff.Owner()
        let peer = RUMContextHandoff.Owner()
        let gate = HandoffAsyncScopeTestGate()
        var calls = 0
        let actual = await withTaskGroup(of: String?.self) { group in
            let result = RUMContextHandoff.withValue(handoffValue("outer"), for: owner) {
                let result = RUMContextHandoff.withValue(handoffValue("callback"), for: owner) {
                    calls += 1
                    group.addTask {
                        await gate.wait()
                        XCTAssertNil(RUMContextHandoff.current(for: peer))
                        return RUMContextHandoff.current(for: owner)?.sceneIdentifier
                    }
                    return false
                }
                XCTAssertEqual(RUMContextHandoff.current(for: owner)?.sceneIdentifier, "outer")
                return result
            }
            XCTAssertFalse(result)
            XCTAssertEqual(calls, 1)
            XCTAssertNil(RUMContextHandoff.current(for: owner))
            await gate.waitUntilWaiting()
            await gate.release()
            return await group.next()!
        }
        XCTAssertEqual(actual, "callback")
        XCTAssertNil(RUMContextHandoff.current(for: owner))
    }

    func testHandoffCallbackScopeCopiesAsyncBindingIntoExternalTaskGroup() async {
        guard supportsHandoffScope else {
            return
        }
        let owner = RUMContextHandoff.Owner()
        let peer = RUMContextHandoff.Owner()
        let gate = HandoffAsyncScopeTestGate()
        var calls = 0
        let actual = await withTaskGroup(of: String?.self) { group in
            let result = await RUMContextHandoff.withValue(handoffValue("outer"), for: owner) {
                let result = await RUMContextHandoff.withValue(handoffValue("callback"), for: owner) {
                    calls += 1
                    group.addTask {
                        await gate.wait()
                        XCTAssertNil(RUMContextHandoff.current(for: peer))
                        return RUMContextHandoff.current(for: owner)?.sceneIdentifier
                    }
                    await gate.waitUntilWaiting()
                    return false
                }
                XCTAssertEqual(RUMContextHandoff.current(for: owner)?.sceneIdentifier, "outer")
                return result
            }
            XCTAssertFalse(result)
            XCTAssertEqual(calls, 1)
            XCTAssertNil(RUMContextHandoff.current(for: owner))
            await gate.release()
            return await group.next()!
        }
        XCTAssertEqual(actual, "callback")
        XCTAssertNil(RUMContextHandoff.current(for: owner))
    }

    func testHandoffCallbackScopePreservesTasklessMainActorLifetimeAndInheritedTask() async {
        guard #available(iOS 17.0, tvOS 17.0, macOS 14.0, watchOS 10.0, *) else {
            return
        }
        let owner = RUMContextHandoff.Owner()
        let gate = HandoffAsyncScopeTestGate()
        let value = handoffValue("callback")
        let child: Task<String?, Never> = await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    XCTAssertTrue(withUnsafeCurrentTask { $0 == nil })
                    MainActor.assertIsolated()
                    var calls = 0
                    let (result, child) = RUMContextHandoff.withValue(value, for: owner) {
                        MainActor.assertIsolated()
                        calls += 1
                        XCTAssertEqual(RUMContextHandoff.current(for: owner)?.sceneIdentifier, self.supportsHandoffScope ? "callback" : nil)
                        var reference: HandoffCallbackMainActorTestReference? = HandoffCallbackMainActorTestReference()
                        weak var released = reference
                        XCTAssertEqual(reference?.value, 23)
                        reference = nil
                        XCTAssertNil(released)
                        let child = Task { @MainActor in
                            await gate.wait()
                            MainActor.assertIsolated()
                            return RUMContextHandoff.current(for: owner)?.sceneIdentifier
                        }
                        return (false, child)
                    }
                    MainActor.assertIsolated()
                    XCTAssertTrue(withUnsafeCurrentTask { $0 == nil })
                    XCTAssertFalse(result)
                    XCTAssertEqual(calls, 1)
                    XCTAssertNil(RUMContextHandoff.current(for: owner))
                    continuation.resume(returning: child)
                }
            }
        }
        await gate.waitUntilWaiting()
        await gate.release()
        let actual = await child.value
        XCTAssertEqual(actual, supportsHandoffScope ? "callback" : nil)
        XCTAssertNil(RUMContextHandoff.current(for: owner))
    }

    @MainActor
    func testHandoffAsyncExecutionScopePreservesMainActorAndNonSendableResultAcrossSuspension() async {
        guard #available(iOS 17.0, tvOS 17.0, macOS 14.0, watchOS 10.0, *) else {
            return
        }
        let owner = RUMContextHandoff.Owner()
        let gate = HandoffAsyncScopeTestGate()
        let original = HandoffAsyncScopeTestResult()
        let release = Task {
            await gate.waitUntilWaiting()
            await gate.release()
        }
        MainActor.assertIsolated()
        let result = await RUMContextHandoff.withValue(handoffValue("main"), for: owner) {
            MainActor.assertIsolated()
            XCTAssertEqual(RUMContextHandoff.current(for: owner)?.sceneIdentifier, self.supportsHandoffScope ? "main" : nil)
            await gate.wait()
            MainActor.assertIsolated()
            XCTAssertEqual(RUMContextHandoff.current(for: owner)?.sceneIdentifier, self.supportsHandoffScope ? "main" : nil)
            original.calls += 1
            return original
        }
        await release.value
        MainActor.assertIsolated()
        XCTAssertTrue(result === original)
        XCTAssertEqual(result.calls, 1)
        XCTAssertNil(RUMContextHandoff.current(for: owner))
    }

    func testHandoffAsyncExecutionScopePreservesCustomActorAndNonSendableResultAcrossSuspension() async {
        guard #available(iOS 17.0, tvOS 17.0, macOS 14.0, watchOS 10.0, *), supportsHandoffScope else {
            return
        }
        let owner = RUMContextHandoff.Owner()
        let gate = HandoffAsyncScopeTestGate()
        let actor = HandoffAsyncScopeTestActor()
        let task = Task { await actor.exercise(owner: owner, gate: gate) }
        await gate.waitUntilWaiting()
        await gate.release()
        await task.value
        XCTAssertNil(RUMContextHandoff.current(for: owner))
    }

    func testHandoffAsyncExecutionScopeRestoresNestedBindingAfterThrow() async {
        guard supportsHandoffScope else {
            return
        }
        let owner = RUMContextHandoff.Owner()
        var calls = 0
        await RUMContextHandoff.withValue(handoffValue("outer"), for: owner) {
            do {
                try await RUMContextHandoff.withValue(handoffValue("inner"), for: owner) {
                    calls += 1
                    XCTAssertEqual(RUMContextHandoff.current(for: owner)?.sceneIdentifier, "inner")
                    await Task.yield()
                    XCTAssertEqual(RUMContextHandoff.current(for: owner)?.sceneIdentifier, "inner")
                    throw HandoffScopeTestError.expected
                }
                XCTFail("Expected operation error")
            } catch {
                XCTAssertEqual(error as? HandoffScopeTestError, .expected)
            }
            XCTAssertEqual(RUMContextHandoff.current(for: owner)?.sceneIdentifier, "outer")
            await Task.yield()
            XCTAssertEqual(RUMContextHandoff.current(for: owner)?.sceneIdentifier, "outer")
        }
        XCTAssertEqual(calls, 1)
        XCTAssertNil(RUMContextHandoff.current(for: owner))
    }

    func testHandoffAsyncExecutionScopeSeparatesConcurrentOwnersAcrossSuspension() async {
        guard supportsHandoffScope else {
            return
        }
        let first = RUMContextHandoff.Owner()
        let second = RUMContextHandoff.Owner()
        let gate = HandoffScopeTestGate()
        let firstTask = Task {
            await RUMContextHandoff.withValue(handoffValue("first"), for: first) {
                await gate.arriveAndWait()
                XCTAssertEqual(RUMContextHandoff.current(for: first)?.sceneIdentifier, "first")
                XCTAssertNil(RUMContextHandoff.current(for: second))
                return 1
            }
        }
        let secondTask = Task {
            await RUMContextHandoff.withValue(handoffValue("second"), for: second) {
                await gate.arriveAndWait()
                XCTAssertEqual(RUMContextHandoff.current(for: second)?.sceneIdentifier, "second")
                XCTAssertNil(RUMContextHandoff.current(for: first))
                return 2
            }
        }
        let firstResult = await firstTask.value
        let secondResult = await secondTask.value
        XCTAssertEqual(firstResult, 1)
        XCTAssertEqual(secondResult, 2)
        XCTAssertNil(RUMContextHandoff.current(for: first))
        XCTAssertNil(RUMContextHandoff.current(for: second))
    }

    func testHandoffAsyncExecutionScopeInvalidatesStoppedOwnerDuringSuspension() async throws {
        guard supportsHandoffScope else {
            return
        }
        let oldCore = makeHandoffCore()
        let oldOwner = try oldCore.activateRUMContextHandoff()
        let gate = HandoffAsyncScopeTestGate()
        let captured = Task {
            await RUMContextHandoff.withValue(handoffValue("old"), for: oldOwner) {
                XCTAssertEqual(RUMContextHandoff.current(for: oldOwner)?.sceneIdentifier, "old")
                await gate.wait()
                return RUMContextHandoff.current(for: oldOwner)?.sceneIdentifier
            }
        }
        await gate.waitUntilWaiting()
        oldCore.stop()
        let newCore = makeHandoffCore()
        defer { newCore.stop() }
        let newOwner = try newCore.activateRUMContextHandoff()
        XCTAssertFalse(oldOwner.isValid)
        XCTAssertTrue(newOwner.isValid)
        XCTAssertFalse(oldOwner === newOwner)
        let fresh = await RUMContextHandoff.withValue(handoffValue("new"), for: newOwner) {
            await Task.yield()
            XCTAssertNil(RUMContextHandoff.current(for: oldOwner))
            return RUMContextHandoff.current(for: newOwner)?.sceneIdentifier
        }
        XCTAssertEqual(fresh, "new")
        await gate.release()
        let actual = await captured.value
        XCTAssertNil(actual)
        XCTAssertNil(RUMContextHandoff.current(for: newOwner))
    }

    @MainActor
    func testHandoffAsyncExecutionScopePreservesActorAndOuterBindingInDirectFallback() async {
        guard #available(iOS 17.0, tvOS 17.0, macOS 14.0, watchOS 10.0, *) else {
            return
        }
        let active = RUMContextHandoff.Owner()
        let invalid = RUMContextHandoff.Owner()
        invalid.invalidate()
        await RUMContextHandoff.withValue(handoffValue("outer"), for: active) {
            for owner in [nil, invalid] as [RUMContextHandoff.Owner?] {
                var calls = 0
                let result = await RUMContextHandoff.withValue(handoffValue("fallback"), for: owner) {
                    MainActor.assertIsolated()
                    calls += 1
                    await Task.yield()
                    MainActor.assertIsolated()
                    XCTAssertNil(RUMContextHandoff.current(for: owner))
                    XCTAssertEqual(RUMContextHandoff.current(for: active)?.sceneIdentifier, self.supportsHandoffScope ? "outer" : nil)
                    return 7
                }
                XCTAssertEqual(result, 7)
                XCTAssertEqual(calls, 1)
                do {
                    try await RUMContextHandoff.withValue(handoffValue("fallback"), for: owner) {
                        MainActor.assertIsolated()
                        calls += 1
                        await Task.yield()
                        MainActor.assertIsolated()
                        throw HandoffScopeTestError.expected
                    }
                    XCTFail("Expected fallback error")
                } catch {
                    XCTAssertEqual(error as? HandoffScopeTestError, .expected)
                }
                XCTAssertEqual(calls, 2)
                MainActor.assertIsolated()
                XCTAssertEqual(RUMContextHandoff.current(for: active)?.sceneIdentifier, self.supportsHandoffScope ? "outer" : nil)
            }
        }
        XCTAssertNil(RUMContextHandoff.current(for: active))
    }

    private func makeHandoffCore() -> DatadogCore {
        DatadogCore(
            directory: temporaryCoreDirectory,
            dateProvider: SystemDateProvider(),
            initialConsent: .notGranted,
            performance: .mockAny(),
            httpClient: HTTPClientMock(),
            encryption: nil,
            contextProvider: .mockAny(),
            applicationVersion: .mockAny(),
            maxBatchesPerUpload: 1,
            backgroundTasksEnabled: false
        )
    }

    func testHandoffActivationPublishesToExistingProviderWithoutLosingContext() throws {
        let core = makeHandoffCore()
        defer { core.stop() }
        let provider = NetworkContextCoreProvider()
        let receiver = HandoffReceiver(provider: provider)
        try core.register(feature: HandoffFeature(receiver: receiver))
        provider.currentNetworkContext = NetworkContext(rumContext: .mockAny())
        let context = provider.currentNetworkContext?.rumContext

        let owner = try core.activateRUMContextHandoff()

        XCTAssertTrue(provider.rumContextHandoffOwner === owner)
        XCTAssertTrue(RUMContextHandoff.owner(in: core.scope(for: HandoffFeature.self)) === owner)
        XCTAssertEqual(provider.currentNetworkContext?.rumContext?.viewID, context?.viewID)
        XCTAssertTrue(provider.receive(message: .context(.mockAny()), from: core))
        XCTAssertTrue(provider.rumContextHandoffOwner === owner)
    }

    func testProviderRegisteredAfterActivationReceivesSameOwner() throws {
        let core = makeHandoffCore()
        defer { core.stop() }
        let owner = try core.activateRUMContextHandoff()
        let provider = NetworkContextCoreProvider()
        try core.register(feature: HandoffFeature(receiver: HandoffReceiver(provider: provider)))
        XCTAssertTrue(provider.rumContextHandoffOwner === owner)
    }

    func testDuplicateActivationAndForeignRollbackPreserveExistingLifetime() throws {
        let core = makeHandoffCore()
        defer { core.stop() }
        let owner = try core.activateRUMContextHandoff()
        let foreign = RUMContextHandoff.Owner()
        XCTAssertThrowsError(try core.activateRUMContextHandoff())
        core.deactivateRUMContextHandoff(owner: foreign)
        XCTAssertTrue(core.rumContextHandoffOwner === owner)
        XCTAssertTrue(owner.isValid)
        XCTAssertTrue(foreign.isValid)
    }

    func testDelayedActivePublicationCannotReplaceNewLifetime() throws {
        let core = makeHandoffCore()
        defer { core.stop() }
        let provider = NetworkContextCoreProvider()
        let receiver = HandoffReceiver(provider: provider)
        try core.register(feature: HandoffFeature(receiver: receiver))
        var replacement: RUMContextHandoff.Owner?
        receiver.beforePublication = { owner, active in
            guard active else {
                return
            }
            receiver.beforePublication = nil
            // Reentrant Core mutation proves receiver callbacks run outside its lock.
            core.deactivateRUMContextHandoff(owner: owner)
            replacement = try? core.activateRUMContextHandoff()
        }
        let old = try core.activateRUMContextHandoff()
        XCTAssertFalse(old.isValid)
        XCTAssertNotNil(replacement)
        XCTAssertTrue(provider.rumContextHandoffOwner === replacement)
        provider.receiveRUMContextHandoff(owner: old, active: false)
        XCTAssertTrue(provider.rumContextHandoffOwner === replacement)
    }

    func testRegistrationAndContextUpdateDuringPausedPublicationKeepOwner() throws {
        let core = makeHandoffCore()
        defer { core.stop() }
        let firstProvider = NetworkContextCoreProvider()
        let receiver = HandoffReceiver(provider: firstProvider)
        try core.register(feature: HandoffFeature(receiver: receiver))
        let entered = expectation(description: "publication entered")
        let finished = expectation(description: "activation completed")
        let release = DispatchSemaphore(value: 0)
        receiver.beforePublication = { _, active in
            if active {
                entered.fulfill()
                XCTAssertEqual(release.wait(timeout: .now() + 5), .success)
            }
        }
        DispatchQueue.global().async {
            defer { finished.fulfill() }
            do {
                _ = try core.activateRUMContextHandoff()
            } catch {
                XCTFail("Activation unexpectedly failed")
            }
        }
        wait(for: [entered], timeout: 5)
        let owner = try XCTUnwrap(core.rumContextHandoffOwner)
        let secondProvider = NetworkContextCoreProvider()
        try core.register(feature: OtherHandoffFeature(receiver: HandoffReceiver(provider: secondProvider)))
        firstProvider.currentNetworkContext = NetworkContext(rumContext: .mockAny())
        let viewID = firstProvider.currentNetworkContext?.rumContext?.viewID
        release.signal()
        wait(for: [finished], timeout: 5)
        XCTAssertTrue(firstProvider.rumContextHandoffOwner === owner)
        XCTAssertTrue(secondProvider.rumContextHandoffOwner === owner)
        XCTAssertEqual(firstProvider.currentNetworkContext?.rumContext?.viewID, viewID)
    }

    func testStopInvalidatesOwnerAndRejectsFurtherActivation() throws {
        let core = makeHandoffCore()
        let provider = NetworkContextCoreProvider()
        try core.register(feature: HandoffFeature(receiver: HandoffReceiver(provider: provider)))
        let owner = try core.activateRUMContextHandoff()
        let scope = core.scope(for: HandoffFeature.self)
        core.stop()
        XCTAssertFalse(owner.isValid)
        XCTAssertNil(provider.rumContextHandoffOwner)
        XCTAssertNil(RUMContextHandoff.owner(in: scope))
        XCTAssertThrowsError(try core.activateRUMContextHandoff())
        provider.receiveRUMContextHandoff(owner: owner, active: true)
        XCTAssertNil(provider.rumContextHandoffOwner)
    }

    func testRollbackRemovesOnlyIssuedOwnerAndAllowsFreshActivation() throws {
        let core = makeHandoffCore()
        defer { core.stop() }
        let provider = NetworkContextCoreProvider()
        try core.register(feature: HandoffFeature(receiver: HandoffReceiver(provider: provider)))
        let old = try core.activateRUMContextHandoff()
        core.deactivateRUMContextHandoff(owner: old)
        XCTAssertFalse(old.isValid)
        XCTAssertNil(provider.rumContextHandoffOwner)
        let current = try core.activateRUMContextHandoff()
        core.deactivateRUMContextHandoff(owner: old)
        XCTAssertTrue(provider.rumContextHandoffOwner === current)
        XCTAssertTrue(current.isValid)
    }

    func testDefaultCoreRegistrationDoesNotActivateHandoff() throws {
        let core = makeHandoffCore()
        defer { core.stop() }
        let provider = NetworkContextCoreProvider()
        let receiver = HandoffReceiver(provider: provider)
        try core.register(feature: HandoffFeature(receiver: receiver))
        XCTAssertNil(core.rumContextHandoffOwner)
        XCTAssertNil(provider.rumContextHandoffOwner)
        XCTAssertEqual(receiver.publications, 0)
    }

    func testCoreDeallocationInvalidatesExternallyRetainedOwner() throws {
        var core: DatadogCore? = makeHandoffCore()
        weak var weakCore = core
        let owner = try XCTUnwrap(core).activateRUMContextHandoff()
        core?.flush()
        core = nil
        XCTAssertNil(weakCore)
        XCTAssertFalse(owner.isValid)
    }

    func testPausedOldPublicationCannotOverwriteReinitializedCoreOwner() throws {
        let oldCore = makeHandoffCore()
        let newCore = makeHandoffCore()
        defer { oldCore.stop(); newCore.stop() }
        let provider = NetworkContextCoreProvider()
        let receiver = HandoffReceiver(provider: provider)
        try oldCore.register(feature: HandoffFeature(receiver: receiver))
        let entered = expectation(description: "old publication entered")
        let finished = expectation(description: "old activation returned")
        let release = DispatchSemaphore(value: 0)
        receiver.beforePublication = { _, active in
            if active {
                entered.fulfill()
                XCTAssertEqual(release.wait(timeout: .now() + 5), .success)
            }
        }
        DispatchQueue.global().async {
            defer { finished.fulfill() }
            do {
                _ = try oldCore.activateRUMContextHandoff()
            } catch {
                XCTFail("Activation unexpectedly failed")
            }
        }
        wait(for: [entered], timeout: 5)
        let old = try XCTUnwrap(oldCore.rumContextHandoffOwner)
        oldCore.stop()
        try newCore.register(feature: HandoffFeature(receiver: HandoffReceiver(provider: provider)))
        let fresh = try newCore.activateRUMContextHandoff()
        release.signal()
        wait(for: [finished], timeout: 5)
        XCTAssertFalse(old.isValid)
        XCTAssertTrue(fresh.isValid)
        XCTAssertTrue(provider.rumContextHandoffOwner === fresh)
    }

    func testRegistrationAfterStopRejectsFeatureAndRemovesOnlyCreatedStore() throws {
        let core = makeHandoffCore()
        defer { core.stop() }
        let owner = try core.activateRUMContextHandoff()
        let entered = expectation(description: "registration prepared its store")
        let finished = expectation(description: "registration returned")
        let release = DispatchSemaphore(value: 0)
        let feature = PausedHandoffRemoteFeature {
            entered.fulfill()
            XCTAssertEqual(release.wait(timeout: .now() + 5), .success)
        }
        DispatchQueue.global().async {
            defer { finished.fulfill() }
            do {
                try core.registerRUMContextHandoff(feature: feature, owner: owner)
                XCTFail("Registration unexpectedly succeeded after stop")
            } catch {
                // Rejection after the terminal stop is required.
            }
        }
        wait(for: [entered], timeout: 5)
        core.stop()
        release.signal()
        wait(for: [finished], timeout: 5)
        XCTAssertFalse(owner.isValid)
        XCTAssertNil(core.get(feature: PausedHandoffRemoteFeature.self))
        XCTAssertNil(core.stores[PausedHandoffRemoteFeature.name])
        core.flush()
    }

    func testStoppedOwnerSkipsQueuedConnectionAndInitialContext() throws {
        let core = makeHandoffCore()
        defer { core.stop() }
        let owner = try core.activateRUMContextHandoff()
        let activeReceiver = HandoffReceiver(provider: NetworkContextCoreProvider())
        try core.registerRUMContextHandoff(feature: HandoffFeature(receiver: activeReceiver), owner: owner)
        core.contextProvider.flush()
        core.bus.flush()
        XCTAssertGreaterThan(activeReceiver.messages, 0)

        let entered = expectation(description: "bus queue held before registration")
        let release = DispatchSemaphore(value: 0)
        core.bus.queue.async {
            entered.fulfill()
            XCTAssertEqual(release.wait(timeout: .now() + 5), .success)
        }
        wait(for: [entered], timeout: 5)
        let stoppedReceiver = HandoffReceiver(provider: NetworkContextCoreProvider())
        // The registry commit succeeds while connect and initial context await the bus.
        try core.registerRUMContextHandoff(feature: OtherHandoffFeature(receiver: stoppedReceiver), owner: owner)
        XCTAssertNotNil(core.get(feature: OtherHandoffFeature.self))
        core.contextProvider.flush()
        // This probe precedes stop's removal, so an unguarded connection is observable.
        core.send(message: .context(.mockAny()), else: {})
        core.stop()
        XCTAssertFalse(owner.isValid)
        release.signal()
        core.bus.flush()
        XCTAssertEqual(stoppedReceiver.messages, 0)
        XCTAssertNil(stoppedReceiver.provider.rumContextHandoffOwner)
    }

    func testForeignAndExpiredRegistrationPreserveAcceptedStoreAndFeature() throws {
        let core = makeHandoffCore()
        defer { core.stop() }
        let owner = try core.activateRUMContextHandoff()
        try core.registerRUMContextHandoff(feature: FeatureMock(), owner: owner)
        let acceptedStore = try XCTUnwrap(core.stores[FeatureMock.name])
        let acceptedUploader = try XCTUnwrap(acceptedStore.upload.uploader as? DataUploadWorker)
        let foreign = RUMContextHandoff.Owner()
        let expired = RUMContextHandoff.Owner()
        expired.invalidate()
        for rejectedOwner in [foreign, expired] {
            XCTAssertThrowsError(try core.registerRUMContextHandoff(feature: FeatureMock(), owner: rejectedOwner))
            let currentStore = try XCTUnwrap(core.stores[FeatureMock.name])
            XCTAssertTrue(currentStore.storage.authorizedFilesOrchestrator === acceptedStore.storage.authorizedFilesOrchestrator)
            XCTAssertTrue(currentStore.storage.unauthorizedFilesOrchestrator === acceptedStore.storage.unauthorizedFilesOrchestrator)
            XCTAssertTrue(try XCTUnwrap(currentStore.upload.uploader as? DataUploadWorker) === acceptedUploader)
            XCTAssertNotNil(core.get(feature: FeatureMock.self))
            XCTAssertTrue(core.rumContextHandoffOwner === owner)
        }
        let writeCompleted = expectation(description: "accepted scope remains usable")
        core.scope(for: FeatureMock.self).eventWriteContext { _, writer in
            writer.write(value: FeatureMock.Event(event: "retained-owner"))
            writeCompleted.fulfill()
        }
        wait(for: [writeCompleted], timeout: 5)
        core.flush()
    }

    func testReplacingFeatureReleasesItAfterRegistryUnlock() throws {
        let core = makeHandoffCore()
        defer { core.stop() }
        var released = false
        var feature: ReentrantDeinitFeature? = ReentrantDeinitFeature {
            // A registry lookup here would deadlock if destruction held its write lock.
            XCTAssertNotNil(core.get(feature: ReentrantDeinitFeature.self))
            released = true
        }
        try core.register(feature: XCTUnwrap(feature))
        feature = nil
        try core.register(feature: ReentrantDeinitFeature {})
        XCTAssertTrue(released)
    }

    func testGivenRemoteConfigurationProvider_whenReadingRemoteConfiguration_itReturnsCachedValue() throws {
        // Given
        let configurationData = try JSONEncoder().encode(RemoteConfiguration(rum: .init(applicationId: "cache-application-id")))
        let cache = RemoteConfigurationCache(etag: nil, metadata: nil, configurationData: configurationData)
        try JSONEncoder().encode(cache).write(
            to: temporaryCoreDirectory.coreDirectory.url.appendingPathComponent("test-id.json"),
            options: .atomic
        )
        let remoteConfigurationProvider = RemoteConfigurationProvider(
            id: "test-id",
            site: .us1,
            directory: temporaryCoreDirectory.coreDirectory,
            httpClient: PendingHTTPClientMock(),
            notificationCenterProvider: NotificationCenterProvider.makeTestProvider()
        )
        let core = DatadogCore(
            directory: temporaryCoreDirectory,
            dateProvider: SystemDateProvider(),
            initialConsent: .mockRandom(),
            performance: .mockRandom(),
            httpClient: HTTPClientMock(),
            encryption: nil,
            contextProvider: .mockAny(),
            applicationVersion: .mockAny(),
            maxBatchesPerUpload: .mockRandom(min: 1, max: 100),
            backgroundTasksEnabled: .mockAny(),
            remoteConfigurationProvider: remoteConfigurationProvider
        )

        // Then
        XCTAssertEqual(core.remoteConfiguration?.rum?.applicationId, "cache-application-id")
    }

    func testGivenNoRemoteConfigurationProvider_whenReadingRemoteConfiguration_itReturnsNil() throws {
        // Given
        let core = DatadogCore(
            directory: temporaryCoreDirectory,
            dateProvider: SystemDateProvider(),
            initialConsent: .mockRandom(),
            performance: .mockRandom(),
            httpClient: HTTPClientMock(),
            encryption: nil,
            contextProvider: .mockAny(),
            applicationVersion: .mockAny(),
            maxBatchesPerUpload: .mockRandom(min: 1, max: 100),
            backgroundTasksEnabled: .mockAny()
        )

        // Then
        XCTAssertNil(core.remoteConfiguration)
    }

    func testWhenWritingEventsWithDifferentTrackingConsent_itOnlyUploadsAuthorizedEvents() throws {
        // Given
        let core = DatadogCore(
            directory: temporaryCoreDirectory,
            dateProvider: SystemDateProvider(),
            initialConsent: .mockRandom(),
            performance: .mockRandom(),
            httpClient: HTTPClientMock(),
            encryption: nil,
            contextProvider: .mockAny(),
            applicationVersion: .mockAny(),
            maxBatchesPerUpload: .mockRandom(min: 1, max: 100),
            backgroundTasksEnabled: .mockAny()
        )

        let requestBuilderSpy = FeatureRequestBuilderSpy()
        try core.register(feature: FeatureMock(requestBuilder: requestBuilderSpy))
        let scope = core.scope(for: FeatureMock.self)

        // When
        core.set(trackingConsent: .notGranted)
        scope.eventWriteContext { context, writer in
            writer.write(value: FeatureMock.Event(event: "not granted"))
        }

        core.set(trackingConsent: .granted)
        scope.eventWriteContext { context, writer in
            writer.write(value: FeatureMock.Event(event: "granted"))
        }

        core.set(trackingConsent: .pending)
        scope.eventWriteContext { context, writer in
            writer.write(value: FeatureMock.Event(event: "pending"))
        }

        // Then
        core.flushAndTearDown()

        let uploadedEvents = requestBuilderSpy.requestParameters
            .flatMap { $0.events }
            .map { $0.data.utf8String }

        XCTAssertEqual(uploadedEvents, [#"{"event":"granted"}"#], "Only `.granted` events should be uploaded")
        XCTAssertEqual(requestBuilderSpy.requestParameters.count, 1, "It should send only one request")
    }

    func testWhenWritingEventsWithPendingConsentThenGranted_itUploadsAllEvents() throws {
        // Given
        let core = DatadogCore(
            directory: temporaryCoreDirectory,
            dateProvider: SystemDateProvider(),
            initialConsent: .mockRandom(),
            performance: .combining(
                storagePerformance: StoragePerformanceMock.readAllFiles,
                uploadPerformance: UploadPerformanceMock.veryQuick
            ),
            httpClient: HTTPClientMock(),
            encryption: nil,
            contextProvider: .mockAny(),
            applicationVersion: .mockAny(),
            maxBatchesPerUpload: 1,
            backgroundTasksEnabled: .mockAny()
        )
        defer { core.flushAndTearDown() }

        let send2RequestsExpectation = expectation(description: "send 2 requests")
        send2RequestsExpectation.expectedFulfillmentCount = 2

        let requestBuilderSpy = FeatureRequestBuilderSpy()
        requestBuilderSpy.onRequest = { _, _ in send2RequestsExpectation.fulfill() }

        try core.register(feature: FeatureMock(requestBuilder: requestBuilderSpy))

        // When
        let scope = core.scope(for: FeatureMock.self)
        core.set(trackingConsent: .pending)
        scope.eventWriteContext { context, writer in
            XCTAssertEqual(context.trackingConsent, .pending)
            writer.write(value: FeatureMock.Event(event: "pending"))
        }

        core.set(trackingConsent: .granted)
        scope.eventWriteContext { context, writer in
            XCTAssertEqual(context.trackingConsent, .granted)
            writer.write(value: FeatureMock.Event(event: "granted"))
        }

        // Then
        waitForExpectations(timeout: 2)

        let uploadedEvents = requestBuilderSpy.requestParameters
            .flatMap { $0.events }
            .map { $0.data.utf8String }

        XCTAssertEqual(
            uploadedEvents,
            [
                #"{"event":"pending"}"#,
                #"{"event":"granted"}"#
            ],
            "It should upload all events"
        )
        XCTAssertEqual(requestBuilderSpy.requestParameters.count, 2, "It should send 2 requests")
    }

    func testWhenWritingEventsWithBypassingConsent_itUploadsAllEvents() throws {
        // Given
        let core = DatadogCore(
            directory: temporaryCoreDirectory,
            dateProvider: SystemDateProvider(),
            initialConsent: .mockRandom(),
            performance: .mockRandom(),
            httpClient: HTTPClientMock(),
            encryption: nil,
            contextProvider: .mockAny(),
            applicationVersion: .mockAny(),
            maxBatchesPerUpload: .mockRandom(min: 1, max: 100),
            backgroundTasksEnabled: .mockAny()
        )

        let requestBuilderSpy = FeatureRequestBuilderSpy()
        try core.register(feature: FeatureMock(requestBuilder: requestBuilderSpy))
        let scope = core.scope(for: FeatureMock.self)

        // When
        core.set(trackingConsent: .notGranted)
        scope.eventWriteContext(bypassConsent: true) { context, writer in
            writer.write(value: FeatureMock.Event(event: "not granted"))
        }

        core.set(trackingConsent: .granted)
        scope.eventWriteContext(bypassConsent: true) { context, writer in
            writer.write(value: FeatureMock.Event(event: "granted"))
        }

        core.set(trackingConsent: .pending)
        scope.eventWriteContext(bypassConsent: true) { context, writer in
            writer.write(value: FeatureMock.Event(event: "pending"))
        }

        // Then
        core.flushAndTearDown()

        let uploadedEvents = requestBuilderSpy.requestParameters
            .flatMap { $0.events }
            .map { $0.data.utf8String }

        XCTAssertEqual(
            uploadedEvents,
            [
                #"{"event":"not granted"}"#,
                #"{"event":"granted"}"#,
                #"{"event":"pending"}"#,
            ],
            "It should upload all events"
        )
        XCTAssertEqual(requestBuilderSpy.requestParameters.count, 1, "It should send only one request")
    }

    func testWhenFeatureAdditionalContextIsUpdated_thenNewValueIsImmediatellyAvailable() throws {
        // Given
        let core = DatadogCore(
            directory: temporaryCoreDirectory,
            dateProvider: SystemDateProvider(),
            initialConsent: .mockRandom(),
            performance: .mockRandom(),
            httpClient: HTTPClientMock(),
            encryption: nil,
            contextProvider: .mockAny(),
            applicationVersion: .mockAny(),
            maxBatchesPerUpload: .mockRandom(min: 1, max: 100),
            backgroundTasksEnabled: .mockAny()
        )
        defer { core.flushAndTearDown() }

        let feature = FeatureMock()
        try core.register(feature: feature)
        let scope = core.scope(for: FeatureMock.self)

        // When
        struct ContextMock: AdditionalContext {
            static let key = "key"
            let value: String
        }
        let expectation1 = self.expectation(description: "retrieve context")
        let expectation2 = self.expectation(description: "retrieve context and event writer")
        expectation1.expectedFulfillmentCount = 2
        expectation2.expectedFulfillmentCount = 2

        core.set(context: ContextMock(value: "value 1"))
        scope.context { context in
            XCTAssertEqual(context.additionalContext(ofType: ContextMock.self)?.value, "value 1")
            expectation1.fulfill()
        }
        scope.eventWriteContext { context, _ in
            XCTAssertEqual(context.additionalContext(ofType: ContextMock.self)?.value, "value 1")
            expectation2.fulfill()
        }

        core.set(context: ContextMock(value: "value 1"))
        scope.context { context in
            XCTAssertEqual(context.additionalContext(ofType: ContextMock.self)?.value, "value 1")
            expectation1.fulfill()
        }
        scope.eventWriteContext { context, _ in
            XCTAssertEqual(context.additionalContext(ofType: ContextMock.self)?.value, "value 1")
            expectation2.fulfill()
        }

        waitForExpectations(timeout: 1)
    }

    func testWhenPerformancePresetOverrideIsProvided_itOverridesPresets() throws {
        // Given
        let core1 = DatadogCore(
            directory: temporaryCoreDirectory,
            dateProvider: RelativeDateProvider(advancingBySeconds: 0.01),
            initialConsent: .granted,
            performance: .mockRandom(),
            httpClient: HTTPClientMock(),
            encryption: nil,
            contextProvider: .mockAny(),
            applicationVersion: .mockAny(),
            maxBatchesPerUpload: .mockRandom(min: 1, max: 100),
            backgroundTasksEnabled: .mockAny()
        )
        let core2 = DatadogCore(
            directory: temporaryCoreDirectory,
            dateProvider: RelativeDateProvider(advancingBySeconds: 0.01),
            initialConsent: .granted,
            performance: .mockRandom(),
            httpClient: HTTPClientMock(),
            encryption: nil,
            contextProvider: .mockAny(),
            applicationVersion: .mockAny(),
            maxBatchesPerUpload: .mockRandom(min: 1, max: 100),
            backgroundTasksEnabled: .mockAny()
        )
        defer {
            core1.flushAndTearDown()
            core2.flushAndTearDown()
        }

        // When
        try core1.register(
            feature: FeatureMock(performanceOverride: nil)
        )
        try core2.register(
            feature: FeatureMock(
                performanceOverride: PerformancePresetOverride(
                    maxFileSize: 123,
                    maxObjectSize: 456,
                    meanFileAge: 100,
                    uploadDelay: nil
                )
            )
        )

        // Then
        let storage1 = core1.stores.values.first?.storage
        XCTAssertEqual(storage1?.authorizedFilesOrchestrator.performance.maxObjectSize, 1.MB.asUInt32())
        XCTAssertEqual(storage1?.authorizedFilesOrchestrator.performance.maxFileSize, 5.MB.asUInt32())

        let storage2 = core2.stores.values.first?.storage
        XCTAssertEqual(storage2?.authorizedFilesOrchestrator.performance.maxObjectSize, 456)
        XCTAssertEqual(storage2?.authorizedFilesOrchestrator.performance.maxFileSize, 123)
        XCTAssertEqual(storage2?.authorizedFilesOrchestrator.performance.maxFileAgeForWrite, 95)
        XCTAssertEqual(storage2?.authorizedFilesOrchestrator.performance.minFileAgeForRead, 105)
    }

    func testWhenStoppingInstance_itDoesNotUploadEvents() throws {
        // Given
        let core = DatadogCore(
            directory: temporaryCoreDirectory,
            dateProvider: SystemDateProvider(),
            initialConsent: .granted,
            performance: .mockRandom(),
            httpClient: HTTPClientMock(),
            encryption: nil,
            contextProvider: .mockAny(),
            applicationVersion: .mockAny(),
            maxBatchesPerUpload: .mockAny(),
            backgroundTasksEnabled: .mockAny()
        )

        let requestBuilderSpy = FeatureRequestBuilderSpy()
        try core.register(feature: FeatureMock(requestBuilder: requestBuilderSpy))
        let scope = core.scope(for: FeatureMock.self)

        // When
        core.stop()

        scope.eventWriteContext { context, writer in
            writer.write(value: FeatureMock.Event(event: "should not be sent"))
        }

        // Then
        XCTAssertNil(core.get(feature: FeatureMock.self))
        core.flush()
        XCTAssertEqual(requestBuilderSpy.requestParameters.count, 0, "It should not send any request")
    }

    func testWhenStoppingInstance_itStopsRemoteConfigurationProvider() throws {
        // Given
        let notificationCenterProvider = NotificationCenterProvider.makeTestProvider()
        let httpClient = PendingHTTPClientMock()
        weak var weakProvider: RemoteConfigurationProvider?
        let core = DatadogCore(
            directory: temporaryCoreDirectory,
            dateProvider: SystemDateProvider(),
            initialConsent: .granted,
            performance: .mockRandom(),
            httpClient: HTTPClientMock(),
            encryption: nil,
            contextProvider: .mockAny(),
            applicationVersion: .mockAny(),
            maxBatchesPerUpload: .mockAny(),
            backgroundTasksEnabled: .mockAny(),
            remoteConfigurationProvider: {
                let provider = RemoteConfigurationProvider(
                    id: "test-id",
                    site: .us1,
                    directory: temporaryCoreDirectory.coreDirectory,
                    httpClient: httpClient,
                    notificationCenterProvider: notificationCenterProvider
                )
                weakProvider = provider
                return provider
            }()
        )

        XCTAssertEqual(httpClient.requestsSent().count, 1)
        #if os(macOS)
        notificationCenterProvider.workspaceCenter.post(name: WorkspaceNotifications.didWake, object: nil)
        #else
        notificationCenterProvider.applicationCenter.post(name: ApplicationNotifications.willEnterForeground, object: nil)
        #endif
        XCTAssertEqual(httpClient.requestsSent().count, 2)

        // When
        core.stop()

        // Then
        XCTAssertNotNil(core.remoteConfigurationProvider)
        XCTAssertNotNil(weakProvider)
        #if os(macOS)
        notificationCenterProvider.workspaceCenter.post(name: WorkspaceNotifications.didWake, object: nil)
        #else
        notificationCenterProvider.applicationCenter.post(name: ApplicationNotifications.willEnterForeground, object: nil)
        #endif
        XCTAssertEqual(httpClient.requestsSent().count, 2)
    }

    func testItAppendsUserDataIfAnonymousIdentifierExists() {
        let core = DatadogCore(
            directory: temporaryCoreDirectory,
            dateProvider: SystemDateProvider(),
            initialConsent: .granted,
            performance: .mockRandom(),
            httpClient: HTTPClientMock(),
            encryption: nil,
            contextProvider: .mockAny(),
            applicationVersion: .mockAny(),
            maxBatchesPerUpload: .mockAny(),
            backgroundTasksEnabled: .mockAny()
        )
        core.set(anonymousId: "anonymous-id")
        let userBefore = core.userInfoPublisher.current
        XCTAssertEqual(userBefore.anonymousId, "anonymous-id")
        XCTAssertNil(userBefore.id)
        XCTAssertNil(userBefore.name)
        XCTAssertNil(userBefore.email)

        core.setUserInfo(id: "user-id", name: "user-name", email: "user-email")

        let userAfter = core.userInfoPublisher.current
        XCTAssertEqual(userAfter.anonymousId, "anonymous-id")
        XCTAssertEqual(userAfter.id, "user-id")
        XCTAssertEqual(userAfter.name, "user-name")
        XCTAssertEqual(userAfter.email, "user-email")
    }

    func testItAppendsAnonymousIdentifierIfUserExists() {
        let core = DatadogCore(
            directory: temporaryCoreDirectory,
            dateProvider: SystemDateProvider(),
            initialConsent: .granted,
            performance: .mockRandom(),
            httpClient: HTTPClientMock(),
            encryption: nil,
            contextProvider: .mockAny(),
            applicationVersion: .mockAny(),
            maxBatchesPerUpload: .mockAny(),
            backgroundTasksEnabled: .mockAny()
        )
        core.setUserInfo(id: "user-id", name: "user-name", email: "user-email")

        let userBefore = core.userInfoPublisher.current
        XCTAssertNil(userBefore.anonymousId)
        XCTAssertEqual(userBefore.id, "user-id")
        XCTAssertEqual(userBefore.name, "user-name")
        XCTAssertEqual(userBefore.email, "user-email")

        core.set(anonymousId: "anonymous-id")

        let userAfter = core.userInfoPublisher.current
        XCTAssertEqual(userAfter.anonymousId, "anonymous-id")
        XCTAssertEqual(userAfter.id, "user-id")
        XCTAssertEqual(userAfter.name, "user-name")
        XCTAssertEqual(userAfter.email, "user-email")
    }

    func testItAppendsAccountDataAndUpdatesIt() {
        let core = DatadogCore(
            directory: temporaryCoreDirectory,
            dateProvider: SystemDateProvider(),
            initialConsent: .granted,
            performance: .mockRandom(),
            httpClient: HTTPClientMock(),
            encryption: nil,
            contextProvider: .mockAny(),
            applicationVersion: .mockAny(),
            maxBatchesPerUpload: .mockAny(),
            backgroundTasksEnabled: .mockAny()
        )
        let accountBefore = core.accountInfoPublisher.current
        XCTAssertNil(accountBefore)

        core.setAccountInfo(id: "account-id", name: "account-name")
        let accountAfterInitialSet = core.accountInfoPublisher.current
        XCTAssertNotNil(accountAfterInitialSet)
        XCTAssertEqual(accountAfterInitialSet?.id, "account-id")
        XCTAssertEqual(accountAfterInitialSet?.name, "account-name")

        core.setAccountInfo(id: "account-id-2", name: "account-name-2")
        let accountAfterUpdate = core.accountInfoPublisher.current
        XCTAssertNotNil(accountAfterUpdate)
        XCTAssertEqual(accountAfterUpdate?.id, "account-id-2")
        XCTAssertEqual(accountAfterUpdate?.name, "account-name-2")
    }

    func testItUpdatesAccountExtraInfoWhileKeepingOriginalAccountInfo() {
        let core = DatadogCore(
            directory: temporaryCoreDirectory,
            dateProvider: SystemDateProvider(),
            initialConsent: .granted,
            performance: .mockRandom(),
            httpClient: HTTPClientMock(),
            encryption: nil,
            contextProvider: .mockAny(),
            applicationVersion: .mockAny(),
            maxBatchesPerUpload: .mockAny(),
            backgroundTasksEnabled: .mockAny()
        )
        let accountBefore = core.accountInfoPublisher.current
        XCTAssertNil(accountBefore)

        core.setAccountInfo(id: "account-id", name: "account-name")
        let accountAfterInitialSet = core.accountInfoPublisher.current
        XCTAssertNotNil(accountAfterInitialSet)
        XCTAssertEqual(accountAfterInitialSet?.id, "account-id")
        XCTAssertEqual(accountAfterInitialSet?.name, "account-name")

        core.addAccountExtraInfo(["test": "test"])
        let accountAfterAddExtraInfo = core.accountInfoPublisher.current
        XCTAssertNotNil(accountAfterAddExtraInfo)
        XCTAssertEqual(accountAfterAddExtraInfo?.id, "account-id")
        XCTAssertEqual(accountAfterAddExtraInfo?.name, "account-name")
    }

    func testItClearsAccountInfo() {
        let core = DatadogCore(
            directory: temporaryCoreDirectory,
            dateProvider: SystemDateProvider(),
            initialConsent: .granted,
            performance: .mockRandom(),
            httpClient: HTTPClientMock(),
            encryption: nil,
            contextProvider: .mockAny(),
            applicationVersion: .mockAny(),
            maxBatchesPerUpload: .mockAny(),
            backgroundTasksEnabled: .mockAny()
        )
        let accountBefore = core.accountInfoPublisher.current
        XCTAssertNil(accountBefore)

        core.setAccountInfo(id: "account-id", name: "account-name")
        let accountAfterInitialSet = core.accountInfoPublisher.current
        XCTAssertNotNil(accountAfterInitialSet)
        XCTAssertEqual(accountAfterInitialSet?.id, "account-id")
        XCTAssertEqual(accountAfterInitialSet?.name, "account-name")

        core.clearAccountInfo()
        let accountAfterUpdate = core.accountInfoPublisher.current
        XCTAssertNil(accountAfterUpdate)
    }

    func testItClearUserInfo() {
        let core = DatadogCore(
            directory: temporaryCoreDirectory,
            dateProvider: SystemDateProvider(),
            initialConsent: .granted,
            performance: .mockRandom(),
            httpClient: HTTPClientMock(),
            encryption: nil,
            contextProvider: .mockAny(),
            applicationVersion: .mockAny(),
            maxBatchesPerUpload: .mockAny(),
            backgroundTasksEnabled: .mockAny()
        )
        let userBefore = core.userInfoPublisher.current
        XCTAssertNil(userBefore.id)
        XCTAssertNil(userBefore.name)
        XCTAssertNil(userBefore.email)

        core.setUserInfo(id: "user-id", name: "user-name", email: "user-email")
        let userAfterInitialSet = core.userInfoPublisher.current
        XCTAssertEqual(userAfterInitialSet.id, "user-id")
        XCTAssertEqual(userAfterInitialSet.name, "user-name")
        XCTAssertEqual(userAfterInitialSet.email, "user-email")

        core.clearUserInfo()
        let userAfterUpdate = core.userInfoPublisher.current
        XCTAssertNil(userAfterUpdate.id)
        XCTAssertNil(userAfterUpdate.name)
        XCTAssertNil(userAfterUpdate.email)
    }

    func testFlushAndUpload_uploadsAuthorizedEvents() throws {
        // Given
        let core = DatadogCore(
            directory: temporaryCoreDirectory,
            dateProvider: SystemDateProvider(),
            initialConsent: .granted,
            performance: .mockRandom(),
            httpClient: HTTPClientMock(),
            encryption: nil,
            contextProvider: .mockAny(),
            applicationVersion: .mockAny(),
            maxBatchesPerUpload: .mockRandom(min: 1, max: 100),
            backgroundTasksEnabled: .mockAny()
        )
        defer { core.stop() }

        let requestBuilderSpy = FeatureRequestBuilderSpy()
        try core.register(feature: FeatureMock(requestBuilder: requestBuilderSpy))
        let scope = core.scope(for: FeatureMock.self)

        scope.eventWriteContext { _, writer in
            writer.write(value: FeatureMock.Event(event: "test"))
        }

        // When
        core.flushAndUpload()

        // Then
        let uploadedEvents = requestBuilderSpy.requestParameters
            .flatMap { $0.events }
            .map { $0.data.utf8String }

        XCTAssertEqual(uploadedEvents, [#"{"event":"test"}"#])
    }

    func testFlushAndUpload_sdkRemainsOperationalAfterFlush() throws {
        // Given
        let core = DatadogCore(
            directory: temporaryCoreDirectory,
            dateProvider: SystemDateProvider(),
            initialConsent: .granted,
            performance: .mockRandom(),
            httpClient: HTTPClientMock(),
            encryption: nil,
            contextProvider: .mockAny(),
            applicationVersion: .mockAny(),
            maxBatchesPerUpload: .mockRandom(min: 1, max: 100),
            backgroundTasksEnabled: .mockAny()
        )
        defer { core.stop() }

        let requestBuilderSpy = FeatureRequestBuilderSpy()
        try core.register(feature: FeatureMock(requestBuilder: requestBuilderSpy))
        let scope = core.scope(for: FeatureMock.self)

        scope.eventWriteContext { _, writer in
            writer.write(value: FeatureMock.Event(event: "first"))
        }
        core.flushAndUpload()

        // When - write more events after flush
        scope.eventWriteContext { _, writer in
            writer.write(value: FeatureMock.Event(event: "second"))
        }
        core.flushAndUpload()

        // Then
        let uploadedEvents = requestBuilderSpy.requestParameters
            .flatMap { $0.events }
            .map { $0.data.utf8String }

        XCTAssertTrue(uploadedEvents.contains(#"{"event":"first"}"#))
        XCTAssertTrue(uploadedEvents.contains(#"{"event":"second"}"#))
    }

    func testDatadogFlush_uploadsEventsAndReturnsSynchronously() throws {
        // Given
        let core = DatadogCore(
            directory: temporaryCoreDirectory,
            dateProvider: SystemDateProvider(),
            initialConsent: .granted,
            performance: .mockRandom(),
            httpClient: HTTPClientMock(),
            encryption: nil,
            contextProvider: .mockAny(),
            applicationVersion: .mockAny(),
            maxBatchesPerUpload: .mockRandom(min: 1, max: 100),
            backgroundTasksEnabled: .mockAny()
        )
        let requestBuilderSpy = FeatureRequestBuilderSpy()
        try core.register(feature: FeatureMock(requestBuilder: requestBuilderSpy))
        let scope = core.scope(for: FeatureMock.self)

        CoreRegistry.register(default: core)
        defer { Datadog.internalFlushAndDeinitialize() }

        scope.eventWriteContext { _, writer in
            writer.write(value: FeatureMock.Event(event: "test"))
        }

        // When
        Datadog.flush()

        // Then - if flush is synchronous, events are uploaded before this assertion
        let uploadedEvents = requestBuilderSpy.requestParameters
            .flatMap { $0.events }
            .map { $0.data.utf8String }

        XCTAssertEqual(uploadedEvents, [#"{"event":"test"}"#])
    }

    func testItClearsAnonymousIdentifier() {
        let core = DatadogCore(
            directory: temporaryCoreDirectory,
            dateProvider: SystemDateProvider(),
            initialConsent: .granted,
            performance: .mockRandom(),
            httpClient: HTTPClientMock(),
            encryption: nil,
            contextProvider: .mockAny(),
            applicationVersion: .mockAny(),
            maxBatchesPerUpload: .mockAny(),
            backgroundTasksEnabled: .mockAny()
        )
        core.set(anonymousId: "anonymous-id")
        core.setUserInfo(id: "user-id", name: "user-name", email: "user-email")
        core.set(anonymousId: nil)

        let userAfter = core.userInfoPublisher.current
        XCTAssertNil(userAfter.anonymousId)
        XCTAssertEqual(userAfter.id, "user-id")
        XCTAssertEqual(userAfter.name, "user-name")
        XCTAssertEqual(userAfter.email, "user-email")
    }
}

private struct HandoffFeature: DatadogFeature {
    static let name = "handoff-test"
    let receiver: HandoffReceiver
    var messageReceiver: FeatureMessageReceiver { receiver }
}

private struct OtherHandoffFeature: DatadogFeature {
    static let name = "other-handoff-test"
    let receiver: HandoffReceiver
    var messageReceiver: FeatureMessageReceiver { receiver }
}

private final class HandoffReceiver: FeatureMessageReceiver, RUMContextHandoffReceiving {
    let provider: NetworkContextCoreProvider
    var beforePublication: ((RUMContextHandoff.Owner, Bool) -> Void)?
    private(set) var publications = 0
    private(set) var messages = 0

    init(provider: NetworkContextCoreProvider) { self.provider = provider }

    func receiveRUMContextHandoff(owner: RUMContextHandoff.Owner, active: Bool) {
        beforePublication?(owner, active)
        publications += 1
        provider.receiveRUMContextHandoff(owner: owner, active: active)
    }

    func receive(message: FeatureMessage, from core: DatadogCoreProtocol) -> Bool {
        messages += 1
        return false
    }
}

private struct PausedHandoffRemoteFeature: DatadogRemoteFeature {
    static let name = "paused-handoff-registration"
    let beforeReceiverRead: () -> Void
    var requestBuilder: FeatureRequestBuilder { FeatureRequestBuilderMock() }
    var performanceOverride: PerformancePresetOverride? { nil }
    var messageReceiver: FeatureMessageReceiver {
        beforeReceiverRead()
        return NOPFeatureMessageReceiver()
    }
}

private final class ReentrantDeinitFeature: DatadogFeature {
    static let name = "reentrant-deinit-test"
    let messageReceiver: FeatureMessageReceiver = NOPFeatureMessageReceiver()
    let onDeinit: () -> Void
    init(onDeinit: @escaping () -> Void) { self.onDeinit = onDeinit }
    deinit { onDeinit() }
}

private enum HandoffScopeTestError: Error, Equatable {
    case expected
}

private actor HandoffScopeTestGate {
    private var isReleased = false
    private var arrivals = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isReleased else {
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func arriveAndWait() async {
        arrivals += 1
        if arrivals == 2 {
            release()
        } else {
            await wait()
        }
    }

    func release() {
        isReleased = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending { waiter.resume() }
    }
}

private final class HandoffAsyncScopeTestResult {
    var calls = 0
}

private actor HandoffAsyncScopeTestGate {
    private var isWaiting = false
    private var isReleased = false
    private var waiter: CheckedContinuation<Void, Never>?
    private var observers: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        precondition(!isWaiting)
        isWaiting = true
        let pending = observers
        observers.removeAll()
        for observer in pending { observer.resume() }
        guard !isReleased else {
            return
        }
        await withCheckedContinuation { waiter = $0 }
    }

    func waitUntilWaiting() async {
        guard !isWaiting else {
            return
        }
        await withCheckedContinuation { observers.append($0) }
    }

    func release() {
        isReleased = true
        waiter?.resume()
        waiter = nil
    }
}

@available(iOS 17.0, tvOS 17.0, macOS 14.0, watchOS 10.0, *)
private actor HandoffAsyncScopeTestActor {
    func exercise(owner: RUMContextHandoff.Owner, gate: HandoffAsyncScopeTestGate) async {
        let outer = RUMContextHandoff.CurrentValue(
            rumContext: nil,
            sceneIdentifier: "outer",
            hasPendingUserAction: false,
            excludedUserActionID: nil
        )
        let inner = RUMContextHandoff.CurrentValue(
            rumContext: nil,
            sceneIdentifier: "custom",
            hasPendingUserAction: false,
            excludedUserActionID: nil
        )
        let original = HandoffAsyncScopeTestResult()
        assertIsolated()
        await RUMContextHandoff.withValue(outer, for: owner) {
            let result = await RUMContextHandoff.withValue(inner, for: owner) {
                self.assertIsolated()
                XCTAssertEqual(RUMContextHandoff.current(for: owner)?.sceneIdentifier, "custom")
                await gate.wait()
                self.assertIsolated()
                XCTAssertEqual(RUMContextHandoff.current(for: owner)?.sceneIdentifier, "custom")
                original.calls += 1
                return original
            }
            self.assertIsolated()
            XCTAssertTrue(result === original)
            XCTAssertEqual(result.calls, 1)
            XCTAssertEqual(RUMContextHandoff.current(for: owner)?.sceneIdentifier, "outer")
        }
        assertIsolated()
        XCTAssertNil(RUMContextHandoff.current(for: owner))
    }
}
@MainActor
private final class HandoffCallbackMainActorTestReference {
    let value = 23
}

#if os(iOS)
private final class AcceptedReceiptActionCapture {
    @ReadWriteLock
    var id: String?
}

extension DatadogCoreTests {
    @MainActor
    func testBuiltInSamplingKeepsAnInvalidatedOwnerAuthoritative() throws {
        guard supportsHandoffScope else { throw XCTSkip("Consumer capture requires iOS 27") }
        let core = makeHandoffCore()
        defer { core.stop() }
        var configuration = RUM.Configuration(applicationID: "sampling-capture", trackAnonymousUser: false)
        configuration.bundle = .mockWith(UIApplicationSceneManifest: ["UIApplicationSupportsMultipleScenes": true])
        configuration.featureFlags = [.multiSceneTracking: true]
        try RUM.enableOrThrow(with: configuration, in: core)
        core.contextProvider.flush()
        let feature = try XCTUnwrap(core.get(feature: RUMFeature.self))
        let owner = try XCTUnwrap(feature.rumContextHandoffOwner)
        let sampler = try XCTUnwrap(core.sessionSampler as? SessionSamplerWithRUMContext)
        let session = try XCTUnwrap(UUID(uuidString: "a1b2c3d4-e5f6-7890-abcd-ceb01cf21171"))
        feature.sessionSamplingStore.setSession(id: session.uuidString.lowercased(), sampler: DeterministicSampler(uuid: session, samplingRate: 10))
        try RUMContextHandoff.withValue(handoffValue("original-view"), for: owner) {
            core.deactivateRUMContextHandoff(owner: owner)
            let sampled = sampler.decisionWithRUMContext(for: .featureRate, rate: 20)
            let captured = try XCTUnwrap(sampled.capture)
            XCTAssertTrue(captured.owner === owner)
            XCTAssertFalse(captured.owner.isValid)
            XCTAssertNil(captured.value.rumContext)
            XCTAssertNil(captured.value.resolvedRUMContext(for: owner))
            XCTAssertEqual(sampled.decision?.sessionID, session.uuidString.lowercased())
            XCTAssertEqual(sampled.decision?.isSampled, true)
        }
    }

    @MainActor
    func testBuiltInSamplingPreservesValidUnboundAndNilOwnership() throws {
        guard supportsHandoffScope else { throw XCTSkip("Consumer capture requires iOS 27") }
        let core = makeHandoffCore()
        defer { core.stop() }
        var configuration = RUM.Configuration(applicationID: "sampling-capture", trackAnonymousUser: false)
        configuration.bundle = .mockWith(UIApplicationSceneManifest: ["UIApplicationSupportsMultipleScenes": true])
        configuration.featureFlags = [.multiSceneTracking: true]
        try RUM.enableOrThrow(with: configuration, in: core)
        let feature = try XCTUnwrap(core.get(feature: RUMFeature.self))
        let owner = try XCTUnwrap(feature.rumContextHandoffOwner)
        let sampler = try XCTUnwrap(core.sessionSampler as? SessionSamplerWithRUMContext)
        XCTAssertNil(sampler.decisionWithRUMContext(for: .featureRate, rate: 100).capture)
        let empty = RUMContextHandoff.CurrentValue(rumContext: nil, sceneIdentifier: "original-scene", hasPendingUserAction: false, excludedUserActionID: nil)
        try RUMContextHandoff.withValue(empty, for: owner) {
            let captured = try XCTUnwrap(sampler.decisionWithRUMContext(for: .featureRate, rate: 100).capture)
            XCTAssertTrue(captured.owner === owner)
            XCTAssertNil(captured.value.rumContext)
            XCTAssertEqual(captured.value.sceneIdentifier, "original-scene")
        }
    }

    @MainActor
    func testQueuedActionReceiptKeepsItsOriginalViewAfterAnotherSceneBecomesRepresentative() throws {
        guard supportsHandoffScope else {
            throw XCTSkip("Execution-scope handoff requires iOS 27")
        }
        let date = Date()
        let initial = DatadogContext.mockWith(
            sdkInitDate: date,
            launchInfo: .mockWith(launchReason: .userLaunch, processLaunchDate: date),
            applicationStateHistory: .mockWith(initialState: .active, date: date)
        )
        let core = DatadogCore(
            directory: temporaryCoreDirectory,
            dateProvider: SystemDateProvider(),
            initialConsent: .granted,
            performance: .mockAny(),
            httpClient: HTTPClientMock(),
            encryption: nil,
            contextProvider: DatadogContextProvider(context: initial),
            applicationVersion: initial.version,
            maxBatchesPerUpload: 1,
            backgroundTasksEnabled: false
        )
        defer { core.flushAndTearDown() }
        var config = RUM.Configuration(applicationID: "receipt-application", trackAnonymousUser: false)
        config.bundle = .mockWith(UIApplicationSceneManifest: ["UIApplicationSupportsMultipleScenes": true])
        config.featureFlags = [.multiSceneTracking: true]
        config.sessionSampleRate = 100
        config.dateProvider = RelativeDateProvider(startingFrom: date, advancingBySeconds: 0)
        try RUM.enableOrThrow(with: config, in: core)
        let feature = try XCTUnwrap(core.get(feature: RUMFeature.self))
        let monitor = feature.monitor
        XCTAssertTrue(monitor.isMultiSceneTrackingEnabled)
        let owner = try XCTUnwrap(monitor.rumContextHandoffOwner)
        let first = RUMSceneIdentifier(rawValue: "receipt-first-scene")
        let second = RUMSceneIdentifier(rawValue: "receipt-second-scene")
        func start(_ scene: RUMSceneIdentifier, name: String, at time: Date) {
            monitor.process(command: RUMStartViewCommand(
                time: time,
                identity: ViewIdentifier(name),
                name: name,
                path: name,
                globalAttributes: [:],
                attributes: [:],
                instrumentationType: .manual,
                target: .scene(scene)
            ))
        }
        start(first, name: "first", at: date.addingTimeInterval(1))
        core.flush()
        let original = try XCTUnwrap(monitor.rumContextSnapshot(for: .scene(first)))
        let receipt = RUMContextHandoff.ActionReceipt(owner: owner, context: original)
        let submitted = RUMContextHandoff.CurrentValue(
            rumContext: original,
            sceneIdentifier: first.rawValue,
            hasPendingUserAction: true,
            excludedUserActionID: original.userActionID,
            actionReceipt: receipt
        )
        var action = RUMAddUserActionCommand(
            time: date.addingTimeInterval(2),
            attributes: [:],
            instrumentation: .swiftuiAutomatic,
            actionType: .tap,
            name: "original-action"
        )
        action.target = .scene(first)
        action.actionReceipt = receipt
        let retained = try RUMContextHandoff.withValue(submitted, for: owner) {
            let retained = try XCTUnwrap(RUMContextHandoff.current(for: owner))
            monitor.process(command: action)
            return retained
        }
        XCTAssertNil(RUMContextHandoff.current(for: owner))
        let acceptedAction = AcceptedReceiptActionCapture()
        core.scope(for: RUMFeature.self).context { _ in
            let firstView = monitor.applicationScope.activeSession?.viewScopes.first {
                $0.isActiveView && $0.sceneIdentifier == first
            }
            acceptedAction.id = firstView?.userActionScope?.actionUUID.toRUMDataFormat
            XCTAssertNotNil(acceptedAction.id)
            XCTAssertEqual(firstView?.userActionScope?.name, "original-action")
        }
        start(second, name: "second", at: date.addingTimeInterval(3))
        let observed = XCTestExpectation(description: "actual Core delivery after queued action and navigation")
        core.scope(for: RUMFeature.self).context { context in
            let delivered = context.additionalContext(ofType: RUMCoreContext.self)
            let firstView = monitor.applicationScope.activeSession?.viewScopes.first {
                $0.isActiveView && $0.sceneIdentifier == first
            }
            let accepted = acceptedAction.id
            XCTAssertNotNil(accepted)
            XCTAssertNil(firstView?.userActionScope, "Receipt survives the original action's expiration")
            XCTAssertNotEqual(delivered?.viewID, original.viewID)
            XCTAssertEqual(delivered?.viewID, monitor.rumContextSnapshot(for: .scene(second))?.viewID)
            let projected = retained.resolvedRUMContext(for: owner)
            XCTAssertEqual(projected?.viewID, original.viewID)
            XCTAssertEqual(projected?.sessionID, original.sessionID)
            XCTAssertEqual(projected?.userActionID, accepted)
            XCTAssertEqual(projected?.viewPath, original.viewPath)
            XCTAssertEqual(context.service, initial.service)
            observed.fulfill()
        }
        wait(for: [observed], timeout: 5)
        core.flush()
    }
}
#endif

#if os(iOS)
extension DatadogCoreTests {
    func testWriteCaptureUsesPublishedStoreOwnerBeforeFeatureRegistryCommit() throws {
        guard supportsHandoffScope else {
            throw XCTSkip("Execution-scope handoff requires iOS 27")
        }
        let core = makeHandoffCore()
        defer { core.stop() }
        let owner = try core.activateRUMContextHandoff()
        let scope = core.scope(for: PausedHandoffRemoteFeature.self)
        let delivered = expectation(description: "write queued before feature registry commit")
        var writes = 0
        core.set(context: RUMCoreContext.mockWith(viewID: "delivery-view"))
        core.contextProvider.flush()
        let feature = PausedHandoffRemoteFeature {
            XCTAssertNotNil(core.stores[PausedHandoffRemoteFeature.name])
            XCTAssertNil(core.get(feature: PausedHandoffRemoteFeature.self))
            scope.eventWriteContextWithRUMCapture { context, _, capture in
                writes += 1
                XCTAssertEqual(context.additionalContext(ofType: RUMCoreContext.self)?.viewID, "delivery-view")
                XCTAssertTrue(capture?.owner === owner)
                XCTAssertEqual(capture?.value.resolvedRUMContext(for: owner)?.viewID, "caller-view")
                delivered.fulfill()
            }
        }
        try RUMContextHandoff.withValue(handoffValue("caller-view"), for: owner) {
            try core.register(feature: feature)
        }
        wait(for: [delivered], timeout: 5)
        XCTAssertEqual(writes, 1)
        XCTAssertNotNil(core.get(feature: PausedHandoffRemoteFeature.self))
    }

    func testWriteCaptureAfterActivationUsesExistingStoreWithoutChangingDeliveryContext() throws {
        guard supportsHandoffScope else {
            throw XCTSkip("Execution-scope handoff requires iOS 27")
        }
        let core = makeHandoffCore()
        defer { core.stop() }
        try core.register(feature: FeatureMock())
        let scope = core.scope(for: FeatureMock.self)
        let owner = try core.activateRUMContextHandoff()
        core.set(context: RUMCoreContext.mockWith(viewID: "delivery-view"))
        let delivered = expectation(description: "activated existing store")
        RUMContextHandoff.withValue(handoffValue("caller-view"), for: owner) {
            scope.eventWriteContextWithRUMCapture { context, _, capture in
                XCTAssertEqual(context.additionalContext(ofType: RUMCoreContext.self)?.viewID, "delivery-view")
                XCTAssertTrue(capture?.owner === owner)
                XCTAssertEqual(capture?.value.resolvedRUMContext(for: owner)?.viewID, "caller-view")
                delivered.fulfill()
            }
        }
        wait(for: [delivered], timeout: 5)
    }

    func testWriteCapturePreservesAuthoritativeNilInsteadOfDeliveryView() throws {
        guard supportsHandoffScope else {
            throw XCTSkip("Execution-scope handoff requires iOS 27")
        }
        let core = makeHandoffCore()
        defer { core.stop() }
        let owner = try core.activateRUMContextHandoff()
        try core.register(feature: FeatureMock())
        core.set(context: RUMCoreContext.mockWith(viewID: "delivery-view"))
        let value = RUMContextHandoff.CurrentValue(
            rumContext: nil, sceneIdentifier: nil, hasPendingUserAction: false, excludedUserActionID: nil
        )
        let delivered = expectation(description: "authoritative empty caller")
        RUMContextHandoff.withValue(value, for: owner) {
            core.scope(for: FeatureMock.self).eventWriteContextWithRUMCapture { context, _, capture in
                XCTAssertEqual(context.additionalContext(ofType: RUMCoreContext.self)?.viewID, "delivery-view")
                XCTAssertTrue(capture?.owner === owner)
                XCTAssertNotNil(capture)
                XCTAssertNil(capture?.value.resolvedRUMContext(for: owner))
                delivered.fulfill()
            }
        }
        wait(for: [delivered], timeout: 5)
    }

    func testWriteCaptureInvalidatedInsideBindingCannotSelectLegacyDeliveryView() throws {
        guard supportsHandoffScope else {
            throw XCTSkip("Execution-scope handoff requires iOS 27")
        }
        let core = makeHandoffCore()
        defer { core.stop() }
        let owner = try core.activateRUMContextHandoff()
        try core.register(feature: FeatureMock())
        core.set(context: RUMCoreContext.mockWith(viewID: "delivery-view"))
        let delivered = expectation(description: "invalid published owner is authoritative")
        RUMContextHandoff.withValue(handoffValue("caller-view"), for: owner) {
            owner.invalidate()
            core.scope(for: FeatureMock.self).eventWriteContextWithRUMCapture { context, _, capture in
                XCTAssertEqual(context.additionalContext(ofType: RUMCoreContext.self)?.viewID, "delivery-view")
                XCTAssertTrue(capture?.owner === owner)
                XCTAssertNotNil(capture)
                XCTAssertNil(capture?.value.rumContext)
                XCTAssertNil(capture?.value.resolvedRUMContext(for: owner))
                delivered.fulfill()
            }
        }
        wait(for: [delivered], timeout: 5)
    }

    func testWriteCaptureQueuedBeforeOwnerReplacementCannotAdoptReplacement() throws {
        guard supportsHandoffScope else {
            throw XCTSkip("Execution-scope handoff requires iOS 27")
        }
        let core = makeHandoffCore()
        defer { core.stop() }
        let owner = try core.activateRUMContextHandoff()
        try core.register(feature: FeatureMock())
        core.set(context: RUMCoreContext.mockWith(viewID: "delivery-view"))
        core.contextProvider.flush()
        let entered = expectation(description: "actual context queue held")
        let release = DispatchSemaphore(value: 0)
        core.contextProvider.read { _ in
            entered.fulfill()
            XCTAssertEqual(release.wait(timeout: .now() + 5), .success)
        }
        wait(for: [entered], timeout: 5)
        let delivered = expectation(description: "queued capture retains invalid original owner")
        RUMContextHandoff.withValue(handoffValue("caller-view"), for: owner) {
            core.scope(for: FeatureMock.self).eventWriteContextWithRUMCapture { context, _, capture in
                XCTAssertEqual(context.additionalContext(ofType: RUMCoreContext.self)?.viewID, "delivery-view")
                XCTAssertTrue(capture?.owner === owner)
                XCTAssertFalse(owner.isValid)
                XCTAssertEqual(capture?.value.rumContext?.viewID, "caller-view")
                XCTAssertNil(capture?.value.resolvedRUMContext(for: owner))
                delivered.fulfill()
            }
        }
        core.deactivateRUMContextHandoff(owner: owner)
        let replacement = try core.activateRUMContextHandoff()
        XCTAssertFalse(owner === replacement)
        XCTAssertTrue(replacement.isValid)
        release.signal()
        wait(for: [delivered], timeout: 5)
    }

    func testWriteCaptureOffAndMissingBindingKeepLegacyContextExactlyOnce() throws {
        guard supportsHandoffScope else {
            throw XCTSkip("Execution-scope handoff requires iOS 27")
        }
        for activated in [false, true] {
            let core = makeHandoffCore()
            try core.register(feature: FeatureMock())
            if activated {
                _ = try core.activateRUMContextHandoff()
            }
            core.set(context: RUMCoreContext.mockWith(viewID: "delivery-view"))
            let delivered = expectation(description: "legacy context without matching binding")
            var calls = 0
            core.scope(for: FeatureMock.self).eventWriteContextWithRUMCapture { context, _, capture in
                calls += 1
                XCTAssertNil(capture)
                XCTAssertEqual(context.additionalContext(ofType: RUMCoreContext.self)?.viewID, "delivery-view")
                delivered.fulfill()
            }
            wait(for: [delivered], timeout: 5)
            XCTAssertEqual(calls, 1)
            core.stop()
        }
    }

    func testWriteCaptureKeepsOriginalConsentAndBypassWriterSelection() throws {
        guard supportsHandoffScope else {
            throw XCTSkip("Execution-scope handoff requires iOS 27")
        }
        for bypassConsent in [false, true] {
            let core = makeHandoffCore()
            let owner = try core.activateRUMContextHandoff()
            let requests = FeatureRequestBuilderSpy()
            try core.register(feature: FeatureMock(requestBuilder: requests))
            let scope = try XCTUnwrap(core.scope(for: FeatureMock.self) as? RUMContextHandoffEventWriting)
            for (consent, name) in [(TrackingConsent.notGranted, "not-granted"), (.granted, "granted"), (.pending, "pending")] {
                core.set(trackingConsent: consent)
                RUMContextHandoff.withValue(handoffValue("caller-view"), for: owner) {
                    scope.eventWriteContextWithRUMCapture(bypassConsent: bypassConsent) { context, writer, capture in
                        XCTAssertEqual(context.trackingConsent, consent)
                        XCTAssertEqual(capture?.value.resolvedRUMContext(for: owner)?.viewID, "caller-view")
                        writer.write(value: FeatureMock.Event(event: name))
                    }
                }
            }
            core.flushAndTearDown()
            let actual = requests.requestParameters.flatMap { $0.events }.map { $0.data.utf8String }
            let expected = bypassConsent
                ? [#"{"event":"not-granted"}"#, #"{"event":"granted"}"#, #"{"event":"pending"}"#]
                : [#"{"event":"granted"}"#]
            XCTAssertEqual(actual, expected)
        }
    }
}
#endif
