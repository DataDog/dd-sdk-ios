/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
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

extension OperationFeatureRetirementTests {
    private final class OperationBusProbe: FeatureMessageReceiver, RUMOperationBusModeReceiving, RUMContextHandoffReceiving {
        struct Observation {
            let kind: String
            let owner: ObjectIdentifier?
        }

        private weak var activeOwner: RUMContextHandoff.Owner?
        var activations: [ObjectIdentifier] = []
        var deactivations: [ObjectIdentifier] = []
        var synchronousHandoffStates: [Bool] = []
        var observations: [Observation] = []
        var consumesOwnedPayload = false

        func receiveRUMContextHandoff(owner: RUMContextHandoff.Owner, active: Bool) {
            synchronousHandoffStates.append(active)
        }

        func receiveRUMOperationBusMode(owner: RUMContextHandoff.Owner, active: Bool) {
            if active {
                activations.append(ObjectIdentifier(owner))
                activeOwner = owner
            } else {
                deactivations.append(ObjectIdentifier(owner))
                if activeOwner === owner { activeOwner = nil }
            }
        }

        func receive(message: FeatureMessage, from core: DatadogCoreProtocol) -> Bool {
            switch message {
            case .context:
                observations.append(Observation(kind: "context", owner: activeOwner.map(ObjectIdentifier.init)))
                return false
            case .payload(let value as OwnedOperationMessage):
                observations.append(Observation(kind: "owned", owner: activeOwner.map(ObjectIdentifier.init)))
                XCTAssertTrue(value.ownership.isValid)
                XCTAssertTrue(activeOwner === value.ownership.origin.owner)
                return consumesOwnedPayload
            case .payload(let value as String):
                observations.append(Observation(kind: value, owner: activeOwner.map(ObjectIdentifier.init)))
                return false
            default:
                return false
            }
        }
    }

    private final class OperationBusFeature: DatadogFeature {
        static let name = "profiling"
        let messageReceiver: FeatureMessageReceiver
        init(_ receiver: FeatureMessageReceiver) { messageReceiver = receiver }
    }

    private func drainOperationBus(_ core: DatadogCore) {
        core.contextProvider.flush()
        core.bus.flush()
    }

    private func disposeOperationBus(_ core: DatadogCore, directory: CoreDirectory) {
        core.stop()
        drainOperationBus(core)
        core.readWriteQueue.sync {}
        try? directory.delete()
    }

    private func sendFirstOwnedOperation(
        _ ownership: RUMOperationOwnership,
        through core: DatadogCore,
        fallback: @escaping () -> Void = {}
    ) {
        let vital = Vital(id: "first-owned", name: "operation", operationKey: nil, stepType: .start, date: Date())
        core.send(message: .payload(OwnedOperationMessage(
            ownership: ownership,
            attributes: [RUMCoreContext.IDs.sessionID: ownership.sessionID],
            operation: vital
        )), else: fallback)
        drainOperationBus(core)
    }

    func testOperationBusMode_lateProfilingRegistration_precedesInitialContextAndFirstOwnedPayload() throws {
        try requireHandoff()
        let (core, directory) = try makeCore()
        defer { disposeOperationBus(core, directory: directory) }
        let owner = try core.activateRUMContextHandoff()
        let (_, ownership) = try install(in: core, owner: owner)
        let probe = OperationBusProbe()
        probe.consumesOwnedPayload = true
        try core.registerRUMContextHandoff(feature: OperationBusFeature(probe), owner: owner)
        XCTAssertEqual(probe.synchronousHandoffStates, [true], "Network callback remains synchronous")
        drainOperationBus(core)

        let initialContexts = probe.observations.filter { $0.kind == "context" }
        XCTAssertFalse(initialContexts.isEmpty)
        XCTAssertTrue(initialContexts.allSatisfy { $0.owner == ObjectIdentifier(owner) })
        sendFirstOwnedOperation(ownership, through: core) { XCTFail("First owned payload unexpectedly fell back") }

        XCTAssertEqual(probe.activations, [ObjectIdentifier(owner)])
        XCTAssertEqual(probe.observations.filter { $0.kind == "owned" }.count, 1)
    }

    func testOperationBusMode_lateRUMActivation_precedesFirstOwnedPayload() throws {
        try requireHandoff()
        let (core, directory) = try makeCore()
        defer { disposeOperationBus(core, directory: directory) }
        let probe = OperationBusProbe()
        probe.consumesOwnedPayload = true
        try core.register(feature: OperationBusFeature(probe))
        drainOperationBus(core)
        XCTAssertTrue(probe.activations.isEmpty)
        XCTAssertTrue(probe.observations.filter { $0.kind == "context" }.allSatisfy { $0.owner == nil })

        let owner = try core.activateRUMContextHandoff()
        XCTAssertEqual(probe.synchronousHandoffStates, [true])
        let (_, ownership) = try install(in: core, owner: owner)
        sendFirstOwnedOperation(ownership, through: core) { XCTFail("First owned payload unexpectedly fell back") }

        XCTAssertEqual(probe.activations, [ObjectIdentifier(owner)])
        XCTAssertEqual(probe.observations.filter { $0.kind == "owned" }.count, 1)
    }

    func testOperationBusMode_expiredQueuedActivation_doesNotEnableReceiver() throws {
        try requireHandoff()
        let (core, directory) = try makeCore()
        defer { disposeOperationBus(core, directory: directory) }
        let probe = OperationBusProbe()
        try core.register(feature: OperationBusFeature(probe))
        drainOperationBus(core)
        core.bus.queue.suspend()
        var suspended = true
        defer { if suspended { core.bus.queue.resume() } }

        let owner = try core.activateRUMContextHandoff()
        core.deactivateRUMContextHandoff(owner: owner)
        XCTAssertFalse(owner.isValid)
        XCTAssertEqual(probe.synchronousHandoffStates, [true, false])
        core.bus.queue.resume()
        suspended = false
        drainOperationBus(core)
        core.send(message: .payload("after-expiry"), else: {})
        drainOperationBus(core)

        XCTAssertTrue(probe.activations.isEmpty)
        XCTAssertEqual(probe.deactivations, [ObjectIdentifier(owner)])
        XCTAssertNil(try XCTUnwrap(probe.observations.last).owner)
    }

    func testOperationBusMode_oldDeactivation_cannotChangeReplacementOwner() throws {
        try requireHandoff()
        let (core, directory) = try makeCore()
        defer { disposeOperationBus(core, directory: directory) }
        let probe = OperationBusProbe()
        probe.consumesOwnedPayload = true
        try core.register(feature: OperationBusFeature(probe))
        drainOperationBus(core)
        let oldOwner = try core.activateRUMContextHandoff()
        drainOperationBus(core)
        core.deactivateRUMContextHandoff(owner: oldOwner)
        let owner = try core.activateRUMContextHandoff()
        let (_, ownership) = try install(in: core, owner: owner)
        drainOperationBus(core)
        let priorDeactivations = probe.deactivations

        core.bus.notifyOperationBusMode(receivers: [probe], owner: oldOwner, active: false)
        core.bus.flush()
        core.deactivateRUMContextHandoff(owner: oldOwner)
        sendFirstOwnedOperation(ownership, through: core) { XCTFail("Replacement owned payload unexpectedly fell back") }

        XCTAssertEqual(probe.activations, [ObjectIdentifier(oldOwner), ObjectIdentifier(owner)])
        XCTAssertEqual(probe.deactivations, priorDeactivations + [ObjectIdentifier(oldOwner)])
        XCTAssertTrue(core.rumContextHandoffOwner === owner)
        XCTAssertTrue(owner.isValid)
        XCTAssertEqual(try XCTUnwrap(probe.observations.last).owner, ObjectIdentifier(owner))
    }

    func testOperationBusMode_combinedActivation_preservesFirstConsumerAndFallback() throws {
        try requireHandoff()
        let (core, directory) = try makeCore()
        defer { disposeOperationBus(core, directory: directory) }
        let owner = try core.activateRUMContextHandoff()
        let (_, ownership) = try install(in: core, owner: owner)
        let first = OperationBusProbe()
        first.consumesOwnedPayload = true
        let second = OperationBusProbe()
        let combined = CombinedFeatureMessageReceiver(first, second)
        try core.registerRUMContextHandoff(feature: OperationBusFeature(combined), owner: owner)
        drainOperationBus(core)
        sendFirstOwnedOperation(ownership, through: core) { XCTFail("Consumed payload unexpectedly fell back") }

        XCTAssertEqual(first.activations, [ObjectIdentifier(owner)])
        XCTAssertEqual(second.activations, [ObjectIdentifier(owner)])
        XCTAssertEqual(first.observations.filter { $0.kind == "owned" }.count, 1)
        XCTAssertTrue(second.observations.filter { $0.kind == "owned" }.isEmpty)

        var fallbacks = 0
        core.send(message: .payload("unknown"), else: { fallbacks += 1 })
        drainOperationBus(core)
        XCTAssertEqual(first.observations.filter { $0.kind == "unknown" }.count, 1)
        XCTAssertEqual(second.observations.filter { $0.kind == "unknown" }.count, 1)
        XCTAssertEqual(fallbacks, 1)
    }

    func testOperationBusMode_coreStop_deactivatesBeforeReceiverRemoval() throws {
        try requireHandoff()
        let (core, directory) = try makeCore()
        defer { disposeOperationBus(core, directory: directory) }
        let owner = try core.activateRUMContextHandoff()
        let probe = OperationBusProbe()
        try core.registerRUMContextHandoff(feature: OperationBusFeature(probe), owner: owner)
        drainOperationBus(core)

        core.stop()
        drainOperationBus(core)
        XCTAssertFalse(owner.isValid)
        XCTAssertNil(core.rumContextHandoffOwner)
        XCTAssertEqual(probe.synchronousHandoffStates, [true, false])
        XCTAssertEqual(probe.deactivations, [ObjectIdentifier(owner)])
        let observationCount = probe.observations.count
        var fallbacks = 0
        core.send(message: .payload("after-stop"), else: { fallbacks += 1 })
        core.bus.flush()

        XCTAssertEqual(probe.observations.count, observationCount)
        XCTAssertEqual(fallbacks, 1)
    }
}
