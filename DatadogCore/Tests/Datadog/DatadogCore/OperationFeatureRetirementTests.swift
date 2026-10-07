/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import TestUtilities
@_spi(Internal) @testable import DatadogInternal
@_spi(Internal) @testable import DatadogCore

final class OperationFeatureRetirementTests: XCTestCase {
    private final class OriginalFeature: DatadogFeature, RUMOperationOriginProviding, RUMOperationFeatureRetiring {
        static let name = "rum"
        let messageReceiver: FeatureMessageReceiver = NOPFeatureMessageReceiver()
        var operationOrigin: RUMOperationOrigin?
        let monitor = NSObject()
        var retirementCalls = 0
        var onRetirement: (() -> Void)?
        func isOperationMonitor(_ monitor: AnyObject) -> Bool { self.monitor === monitor }
        func isOperationSessionActive(start: Date, lastInteraction: Date) -> Bool { true }
        func retireOperationOrigin() {
            retirementCalls += 1
            operationOrigin?.retire()
            onRetirement?()
        }
    }

    private final class Cancellation: RUMOperationCancellationReceiving {
        var calls = 0
        func operationOwnershipDidRetire(_ ownership: RUMOperationOwnership) {
            calls += 1
            XCTAssertFalse(ownership.isValid)
            // Reentering the capability proves the original subscriber lock was released.
            ownership.unsubscribe(self)
        }
    }

    private func requireHandoff() throws {
        #if os(iOS)
        if #available(iOS 27.0, *) { return }
        #endif
        throw XCTSkip("Original lifetime handoff requires supported iOS")
    }

    private func makeCore() throws -> (DatadogCore, CoreDirectory) {
        let directory = temporaryUniqueCoreDirectory()
        try directory.create()
        let core = DatadogCore(
            directory: directory, dateProvider: SystemDateProvider(), initialConsent: .notGranted,
            performance: .mockAny(), httpClient: HTTPClientMock(), encryption: nil,
            contextProvider: .mockAny(), applicationVersion: .mockAny(),
            maxBatchesPerUpload: 1, backgroundTasksEnabled: false
        )
        return (core, directory)
    }

    private func install(in core: DatadogCore, owner: RUMContextHandoff.Owner) throws -> (OriginalFeature, RUMOperationOwnership) {
        let feature = OriginalFeature()
        let origin = RUMOperationOrigin(core: core, owner: owner)
        feature.operationOrigin = origin
        origin.attach(feature: feature, monitor: feature.monitor)
        try core.register(feature: feature)
        let now = Date()
        origin.setSession("original")
        origin.updateSession("original", start: now, lastInteraction: now)
        return (feature, try XCTUnwrap(origin.ownership(for: "original")))
    }

    func testReplacingFeatureRetiresOriginalAfterRegistryUnlockAndDetachesIt() throws {
        try requireHandoff()
        let (core, directory) = try makeCore()
        defer { core.stop(); try? directory.delete() }
        let owner = try core.activateRUMContextHandoff()
        let (original, ownership) = try install(in: core, owner: owner)
        let subscriber = Cancellation()
        XCTAssertTrue(ownership.subscribe(subscriber))
        original.onRetirement = {
            XCTAssertFalse(core.feature(named: "rum", type: OriginalFeature.self) === original)
        }
        defer { original.onRetirement = nil }
        let (replacement, replacementOwnership) = try install(in: core, owner: owner)
        XCTAssertEqual(subscriber.calls, 1)
        XCTAssertFalse(ownership.isValid)
        XCTAssertTrue(replacementOwnership.isValid)
        XCTAssertEqual(original.retirementCalls, 1)
        core.deactivateRUMContextHandoff(owner: owner)
        XCTAssertEqual(original.retirementCalls, 1, "The old participant was detached by exact identity")
        XCTAssertFalse(replacementOwnership.isValid)
        XCTAssertGreaterThanOrEqual(replacement.retirementCalls, 1)
        original.onRetirement = nil
    }

    func testStoppingCoreRetiresExternallyRetainedFeatureAndSubscription() throws {
        try requireHandoff()
        let (core, directory) = try makeCore()
        defer { core.stop(); try? directory.delete() }
        let owner = try core.activateRUMContextHandoff()
        let (feature, ownership) = try install(in: core, owner: owner)
        let subscriber = Cancellation()
        XCTAssertTrue(ownership.subscribe(subscriber))
        feature.onRetirement = {
            XCTAssertNil(core.feature(named: "rum", type: OriginalFeature.self))
        }
        core.stop()
        XCTAssertEqual(subscriber.calls, 1)
        XCTAssertFalse(ownership.isValid)
        XCTAssertNotNil(feature.operationOrigin, "The externally retained original remains alive")
        feature.onRetirement = nil
    }

    func testReleasingCoreRetiresExternallyRetainedFeatureWithoutTimer() throws {
        try requireHandoff()
        var created: (DatadogCore, CoreDirectory)? = try makeCore()
        var core: DatadogCore? = created?.0
        let directory = try XCTUnwrap(created).1
        created = nil
        defer { core?.stop(); try? directory.delete() }
        let owner = try XCTUnwrap(core).activateRUMContextHandoff()
        let (feature, ownership) = try install(in: XCTUnwrap(core), owner: owner)
        let subscriber = Cancellation()
        XCTAssertTrue(ownership.subscribe(subscriber))
        weak var weakCore = core
        // No subscriber, Feature, envelope or origin holds the original Core.
        core = nil
        XCTAssertNil(weakCore)
        XCTAssertFalse(ownership.isValid)
        XCTAssertEqual(subscriber.calls, 1)
        XCTAssertGreaterThanOrEqual(feature.retirementCalls, 1)
    }

    func testInactiveLegacyCoreDoesNotAttachOperationRetirementParticipant() throws {
        let (core, directory) = try makeCore()
        defer { core.stop(); try? directory.delete() }
        let feature = OriginalFeature()
        try core.register(feature: feature)
        core.stop()
        XCTAssertEqual(feature.retirementCalls, 0)
    }
}
