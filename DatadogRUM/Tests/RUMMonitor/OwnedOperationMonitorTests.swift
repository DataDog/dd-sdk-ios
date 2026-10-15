/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import XCTest
@_spi(Internal) @testable import DatadogInternal
@_spi(Internal) @testable import DatadogCore
@testable import DatadogRUM
@testable import TestUtilities

#if os(iOS)
@MainActor
final class OwnedOperationMonitorTests: XCTestCase {
    private nonisolated static func recordPhase(_ phase: StaticString) {
        let line = "OwnedOperationMonitorPhase " + String(describing: phase) + "\n"
        FileHandle.standardError.write(Data(line.utf8))
    }

    private final class OperationReceiver: FeatureMessageReceiver {
        @ReadWriteLock private var received: [OwnedOperationMessage] = []
        @ReadWriteLock private var receivedLegacy: [OperationMessage] = []

        var messages: [OwnedOperationMessage] { received }
        var legacyMessages: [OperationMessage] { receivedLegacy }

        func receive(message: FeatureMessage, from core: DatadogCoreProtocol) -> Bool {
            guard case let .payload(payload) = message else { return false }
            if let operation = payload as? OwnedOperationMessage {
                _received.mutate { $0.append(operation) }
                return true
            }
            if let operation = payload as? OperationMessage {
                _receivedLegacy.mutate { $0.append(operation) }
                return true
            }
            return false
        }
    }

    private struct OperationObserver: DatadogFeature {
        static let name = "owned-operation-observer"
        let messageReceiver: FeatureMessageReceiver
    }

    private struct ReplacementFeature: DatadogFeature {
        static let name = RUMFeature.name
        let messageReceiver: FeatureMessageReceiver
    }

    private struct CapturedContext {
        let owner: RUMContextHandoff.Owner
        let value: RUMContextHandoff.CurrentValue
    }

    @MainActor
    private final class Fixture {
        let directory: CoreDirectory
        let core: DatadogCore
        let clock: DateProviderMock
        let receiver: OperationReceiver
        let configuration: RUM.Configuration
        var feature: RUMFeature
        private let recordsPhases: Bool

        private func record(_ phase: StaticString) {
            if recordsPhases { OwnedOperationMonitorTests.recordPhase(phase) }
        }

        init(multiSceneTrackingEnabled: Bool = true, recordPhases: Bool = false, monotonicClock: MonotonicClock? = nil) throws {
            func record(_ phase: StaticString) {
                if recordPhases { OwnedOperationMonitorTests.recordPhase(phase) }
            }
            record("fixture.construct.enter")
            let directory = temporaryUniqueCoreDirectory()
            record("directory.create.enter")
            try directory.create()
            record("directory.create.return")
            let clock = DateProviderMock(now: Date(timeIntervalSince1970: 1_700_000_000))
            let receiver = OperationReceiver()
            let context = DatadogContext.mockWith(
                sdkInitDate: clock.now,
                trackingConsent: .granted,
                launchInfo: .mockWith(launchReason: .userLaunch, processLaunchDate: clock.now),
                applicationStateHistory: AppStateHistory(initialState: .active, date: clock.now)
            )
            record("core.init.enter")
            let core = DatadogCore(
                directory: directory,
                // Storage filenames need an advancing clock; RUM retains the controlled clock.
                dateProvider: SystemDateProvider(),
                initialConsent: .granted,
                performance: .combining(
                    storagePerformance: .writeEachObjectToNewFileAndReadAllFiles,
                    uploadPerformance: .noOp
                ),
                httpClient: HTTPClientMock(),
                encryption: nil,
                contextProvider: DatadogContextProvider(
                    context: context,
                    queue: DispatchQueue(label: "owned-operation-context-\(UUID().uuidString)")
                ),
                applicationVersion: "1",
                maxBatchesPerUpload: 0,
                backgroundTasksEnabled: false
            )
            record("core.init.return")
            var configuration = RUM.Configuration(applicationID: UUID().uuidString)
            configuration.dateProvider = clock
            configuration.monotonicClock = monotonicClock ?? DateProviderMonotonicClock(dateProvider: clock)
            configuration.sessionSampleRate = 100
            configuration.telemetrySampleRate = 0
            configuration.sessionEndedSampleRate = 0
            configuration.trackAnonymousUser = false
            configuration.longTaskThreshold = nil
            configuration.appHangThreshold = nil
            configuration.vitalsUpdateFrequency = nil
            configuration.bundle = .mockWith(
                UIApplicationSceneManifest: ["UIApplicationSupportsMultipleScenes": true]
            )
            configuration.featureFlags = [.multiSceneTracking: multiSceneTrackingEnabled]
            do {
                record("observer.register.enter")
                try core.register(feature: OperationObserver(messageReceiver: receiver))
                record("observer.register.return")
                record("rum.enable.enter")
                try RUM.enableOrThrow(with: configuration, in: core)
                record("rum.enable.return")
                record("original-feature.lookup.enter")
                self.feature = try XCTUnwrap(core.get(feature: RUMFeature.self))
                record("original-feature.lookup.return")
            } catch {
                record("fixture.failure.stop.enter")
                core.stop()
                record("fixture.failure.stop.return")
                record("fixture.failure.directory-delete.enter")
                try? directory.delete()
                record("fixture.failure.directory-delete.return")
                throw error
            }
            self.directory = directory
            self.core = core
            self.clock = clock
            self.receiver = receiver
            self.configuration = configuration
            self.recordsPhases = recordPhases
            record("fixture.initial-flush.enter")
            core.flush()
            record("fixture.initial-flush.return")
            record("fixture.construct.return")
        }

        func tearDown() {
            record("teardown.core-stop.enter")
            core.stop()
            record("teardown.core-stop.return")
            record("teardown.context-flush.enter")
            core.contextProvider.flush()
            record("teardown.context-flush.return")
            record("teardown.read-write-sync.enter")
            core.readWriteQueue.sync {}
            record("teardown.read-write-sync.return")
            record("teardown.bus-flush.enter")
            core.bus.flush()
            record("teardown.bus-flush.return")
            record("teardown.directory-delete.enter")
            try? directory.delete()
            record("teardown.directory-delete.return")
        }

        func drain() {
            record("fixture.drain.enter")
            core.flush()
            record("fixture.drain.return")
        }

        func startView(_ name: String, on feature: RUMFeature? = nil) {
            (feature ?? self.feature).monitor.process(command: RUMStartViewCommand(
                time: clock.now,
                identity: ViewIdentifier(name),
                name: name,
                path: name,
                globalAttributes: [:],
                attributes: [:],
                instrumentationType: .manual,
                target: .scene(.init(rawValue: name))
            ))
        }

        func capture(_ name: String, on feature: RUMFeature? = nil) throws -> CapturedContext {
            let feature = feature ?? self.feature
            let owner = try XCTUnwrap(feature.rumContextHandoffOwner)
            _ = try XCTUnwrap(feature.isMultiSceneTrackingEnabled && owner.isValid ? owner : nil)
            let context = feature.monitor.rumContextSnapshot(for: .scene(.init(rawValue: name)))
            return CapturedContext(
                owner: owner,
                value: .init(
                    rumContext: context,
                    sceneIdentifier: name,
                    hasPendingUserAction: false,
                    excludedUserActionID: nil
                )
            )
        }

        func start(_ name: String, capture: CapturedContext, on feature: RUMFeature? = nil) {
            let monitor = (feature ?? self.feature).monitor
            RUMContextHandoff.withValue(capture.value, for: capture.owner) {
                monitor.startOperation(
                    name: name,
                    operationKey: nil,
                    attributes: [:],
                    options: ProfilingOptions(sampleRate: 100)
                )
            }
        }

        func storedEvents(in storage: FeatureStorage) throws -> [Data] {
            storage.setIgnoreFilesAgeWhenReading(to: true)
            let reader = storage.reader
            let files = reader.readFiles(limit: 128)
            XCTAssertLessThan(files.count, 128, "Read the complete bounded fixture inventory")
            return try files.flatMap { file in
                try XCTUnwrap(reader.readBatch(from: file)).events.map(\.data)
            }
        }

        func storedVitals(in storage: FeatureStorage) throws -> [RUMVitalOperationStepEvent] {
            try storedEvents(in: storage).compactMap { data in
                let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
                guard object["type"] as? String == "vital",
                      let vital = object["vital"] as? [String: Any],
                      vital["type"] as? String == "operation_step" else { return nil }
                return try JSONDecoder().decode(RUMVitalOperationStepEvent.self, from: data)
            }
        }

        func bytes(in storage: FeatureStorage) throws -> [String] {
            try storedEvents(in: storage).map { $0.base64EncodedString() }.sorted()
        }
    }

    private func requireOwnedOperations() throws {
        guard #available(iOS 27.0, *) else {
            throw XCTSkip("Original operation ownership requires supported iOS")
        }
    }


    func testOwnedOperationAndSceneSnapshotUseMonotonicSessionLifetime() throws {
        try requireOwnedOperations()
        let monotonicClock = MonotonicClockMock()
        let fixture = try Fixture(monotonicClock: monotonicClock)
        defer { fixture.tearDown() }
        fixture.startView("original")
        fixture.drain()
        let capture = try fixture.capture("original")
        let context = try XCTUnwrap(capture.value.rumContext)
        let origin = try XCTUnwrap(fixture.feature.operationOrigin)
        let ownership = try XCTUnwrap(origin.ownership(for: context.sessionID))
        let wallDate = fixture.clock.now

        for shift in [86_400.0, -86_400.0] {
            fixture.clock.now = wallDate.addingTimeInterval(shift)
            XCTAssertEqual(
                fixture.feature.monitor.rumContextSnapshot(for: .scene(.init(rawValue: "original")))?.sessionID,
                context.sessionID
            )
            XCTAssertTrue(ownership.isValid)
        }

        monotonicClock.advance(by: RUMSessionScope.Constants.sessionTimeoutDuration)
        XCTAssertNil(fixture.feature.monitor.rumContextSnapshot(for: .scene(.init(rawValue: "original"))))
        XCTAssertFalse(ownership.isValid)
    }

    private func holdOriginalQueue(in fixture: Fixture, recordPhases: Bool = false) -> DispatchSemaphore {
        let entered = expectation(description: "original Core context queue held")
        let release = DispatchSemaphore(value: 0)
        if recordPhases { Self.recordPhase("held-queue.request.enter") }
        fixture.core.scope(for: RUMFeature.self).context { @Sendable _ in
            if recordPhases { OwnedOperationMonitorTests.recordPhase("held-queue.callback.enter") }
            entered.fulfill()
            if recordPhases { OwnedOperationMonitorTests.recordPhase("held-queue.release-wait.enter") }
            XCTAssertEqual(release.wait(timeout: .now() + 10), .success)
            if recordPhases { OwnedOperationMonitorTests.recordPhase("held-queue.release-wait.return") }
        }
        if recordPhases { Self.recordPhase("held-queue.request.return") }
        if recordPhases { Self.recordPhase("held-queue.entered-expectation.enter") }
        wait(for: [entered], timeout: 2)
        if recordPhases { Self.recordPhase("held-queue.entered-expectation.return") }
        return release
    }

    func testAuthoritativeAbsentSessionCannotBorrowLaterRepresentativeOnMonitorQueue() throws {
        Self.recordPhase("test.enter")
        defer { Self.recordPhase("test.exit") }
        try requireOwnedOperations()
        let fixture = try Fixture(recordPhases: true)
        defer { fixture.tearDown() }
        XCTAssertTrue(fixture.feature.isMultiSceneTrackingEnabled)
        Self.recordPhase("original-view.enter")
        fixture.startView("original")
        Self.recordPhase("original-view.return")
        fixture.drain()
        Self.recordPhase("absent-capture.enter")
        let absent = try fixture.capture("absent")
        Self.recordPhase("absent-capture.return")
        XCTAssertNil(absent.value.rumContext)
        Self.recordPhase("later-view.enter")
        fixture.startView("later")
        Self.recordPhase("later-view.return")
        fixture.drain()
        Self.recordPhase("later-capture.enter")
        let later = try fixture.capture("later")
        Self.recordPhase("later-capture.return")
        XCTAssertNotNil(later.value.rumContext)
        let session = try XCTUnwrap(fixture.feature.monitor.applicationScope.activeSession)
        let originalSessionID = session.sessionUUID
        let viewsBefore = session.viewScopes.map(\.viewUUID)
        let interactionBefore = session.lastInteraction
        Self.recordPhase("storage.lookup.enter")
        let storage = try XCTUnwrap(fixture.core.stores[RUMFeature.name]?.storage)
        Self.recordPhase("storage.lookup.return")
        Self.recordPhase("storage.before-read.enter")
        let eventsBefore = try fixture.bytes(in: storage)
        Self.recordPhase("storage.before-read.return")
        let messagesBefore = fixture.receiver.messages.count
        let release = holdOriginalQueue(in: fixture, recordPhases: true)
        defer { release.signal() }

        Self.recordPhase("public-absent-operation.enter")
        fixture.start("absent-public", capture: absent)
        Self.recordPhase("public-absent-operation.return")
        let step = RUMOperationStepVitalCommand.mockWith(
            vitalId: "absent-queued",
            name: "absent-queued",
            operationKey: nil,
            stepType: .start,
            options: ProfilingOptions(sampleRate: 100),
            time: fixture.clock.now
        )
        Self.recordPhase("explicit-owned-command.enter")
        fixture.feature.monitor.process(command: RUMOwnedOperationStepCommand(
            step: step,
            origin: try XCTUnwrap(fixture.feature.operationOrigin),
            capture: absent.value
        ))
        Self.recordPhase("explicit-owned-command.return")
        Self.recordPhase("held-queue.signal.enter")
        release.signal()
        Self.recordPhase("held-queue.signal.return")
        fixture.drain()

        XCTAssertTrue(fixture.feature.monitor.applicationScope.activeSession === session)
        XCTAssertEqual(session.sessionUUID, originalSessionID)
        XCTAssertEqual(session.viewScopes.map(\.viewUUID), viewsBefore)
        XCTAssertEqual(session.lastInteraction, interactionBefore)
        Self.recordPhase("storage.after-refusal-read.enter")
        XCTAssertEqual(try fixture.bytes(in: storage), eventsBefore)
        Self.recordPhase("storage.after-refusal-read.return")
        XCTAssertEqual(fixture.receiver.messages.count, messagesBefore)

        Self.recordPhase("public-admitted-operation.enter")
        fixture.start("admitted", capture: later)
        Self.recordPhase("public-admitted-operation.return")
        fixture.drain()
        Self.recordPhase("storage.admitted-vital-read.enter")
        let event = try XCTUnwrap(try fixture.storedVitals(in: storage).last)
        Self.recordPhase("storage.admitted-vital-read.return")
        let message = try XCTUnwrap(fixture.receiver.messages.last)
        XCTAssertEqual(event.vital.name, "admitted")
        XCTAssertEqual(event.session.id, later.value.rumContext?.sessionID)
        XCTAssertEqual(event.view.id, later.value.rumContext?.viewID)
        XCTAssertTrue(message.ownership.origin === fixture.feature.operationOrigin)
        XCTAssertEqual(message.ownership.sessionID, event.session.id)
        XCTAssertEqual(fixture.receiver.messages.count, messagesBefore + 1)
        Self.recordPhase("test.assertions.complete")
    }

    func testQueuedOriginalOperationRefusesSameOwnerRegistryReplacementAndFreshRUMProgresses() throws {
        try requireOwnedOperations()
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        fixture.startView("original")
        fixture.drain()
        let original = fixture.feature
        let capture = try fixture.capture("original")
        let origin = try XCTUnwrap(original.operationOrigin)
        let owner = try XCTUnwrap(original.rumContextHandoffOwner)
        let session = try XCTUnwrap(original.monitor.applicationScope.activeSession)
        let interactionBefore = session.lastInteraction
        let viewsBefore = session.viewScopes.map(\.viewUUID)
        let originalStorage = try XCTUnwrap(fixture.core.stores[RUMFeature.name]?.storage)
        let vitalsBefore = try fixture.storedVitals(in: originalStorage)
        let replacementReceiver = OperationReceiver()
        let messagesBefore = fixture.receiver.messages.count
        XCTAssertTrue(origin.isCurrent)
        let release = holdOriginalQueue(in: fixture)
        defer { release.signal() }

        fixture.start("stale-original", capture: capture, on: original)
        try fixture.core.registerRUMContextHandoff(
            feature: ReplacementFeature(messageReceiver: replacementReceiver),
            owner: owner
        )
        XCTAssertNotNil(fixture.core.get(feature: ReplacementFeature.self))
        XCTAssertNil(fixture.core.get(feature: RUMFeature.self))
        XCTAssertTrue(owner.isValid)
        XCTAssertFalse(origin.isCurrent)
        release.signal()
        fixture.drain()

        XCTAssertTrue(original.monitor.applicationScope.activeSession === session)
        XCTAssertEqual(session.lastInteraction, interactionBefore)
        XCTAssertEqual(session.viewScopes.map(\.viewUUID), viewsBefore)
        XCTAssertEqual(try fixture.storedVitals(in: originalStorage), vitalsBefore)
        XCTAssertEqual(fixture.receiver.messages.count, messagesBefore)
        XCTAssertTrue(replacementReceiver.messages.isEmpty)

        fixture.core.deactivateRUMContextHandoff(owner: owner)
        try RUM.enableOrThrow(with: fixture.configuration, in: fixture.core)
        let replacement = try XCTUnwrap(fixture.core.get(feature: RUMFeature.self))
        fixture.feature = replacement
        let replacementOwner = try XCTUnwrap(replacement.rumContextHandoffOwner)
        XCTAssertFalse(replacement === original)
        XCTAssertFalse(replacementOwner === owner)
        XCTAssertFalse(owner.isValid)
        XCTAssertTrue(replacementOwner.isValid)
        XCTAssertTrue(try XCTUnwrap(replacement.operationOrigin).isCurrent)
        fixture.drain()
        let replacementStorage = try XCTUnwrap(fixture.core.stores[RUMFeature.name]?.storage)
        XCTAssertFalse(try fixture.storedVitals(in: replacementStorage).contains {
            $0.vital.name == "stale-original"
        })
        fixture.startView("replacement")
        fixture.drain()
        let replacementCapture = try fixture.capture("replacement")
        let replacementSession = try XCTUnwrap(replacement.monitor.applicationScope.activeSession)
        fixture.start("replacement-admitted", capture: replacementCapture)
        fixture.drain()
        let event = try XCTUnwrap(try fixture.storedVitals(in: replacementStorage).last)
        let message = try XCTUnwrap(fixture.receiver.messages.last)
        XCTAssertTrue(replacement.monitor.applicationScope.activeSession === replacementSession)
        XCTAssertEqual(event.vital.name, "replacement-admitted")
        XCTAssertEqual(event.session.id, replacementCapture.value.rumContext?.sessionID)
        XCTAssertEqual(event.view.id, replacementCapture.value.rumContext?.viewID)
        XCTAssertTrue(message.ownership.origin === replacement.operationOrigin)
        XCTAssertFalse(message.ownership.origin === origin)
        XCTAssertEqual(message.ownership.sessionID, event.session.id)
        XCTAssertEqual(fixture.receiver.messages.count, messagesBefore + 1)
    }

    func testQueuedOriginalOperationRefusesRetiredOwnerWithoutWritingOrChangingSession() throws {
        try requireOwnedOperations()
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        fixture.startView("original")
        fixture.drain()
        let original = fixture.feature
        let capture = try fixture.capture("original")
        let origin = try XCTUnwrap(original.operationOrigin)
        let session = try XCTUnwrap(original.monitor.applicationScope.activeSession)
        let interactionBefore = session.lastInteraction
        let viewsBefore = session.viewScopes.map(\.viewUUID)
        let storage = try XCTUnwrap(fixture.core.stores[RUMFeature.name]?.storage)
        let eventsBefore = try fixture.bytes(in: storage)
        let messagesBefore = fixture.receiver.messages.count
        let release = holdOriginalQueue(in: fixture)
        defer { release.signal() }

        fixture.start("stale-retired", capture: capture)
        fixture.core.deactivateRUMContextHandoff(owner: capture.owner)
        XCTAssertFalse(capture.owner.isValid)
        XCTAssertFalse(origin.isCurrent)
        release.signal()
        fixture.drain()

        XCTAssertTrue(original.monitor.applicationScope.activeSession === session)
        XCTAssertEqual(session.lastInteraction, interactionBefore)
        XCTAssertEqual(session.viewScopes.map(\.viewUUID), viewsBefore)
        XCTAssertEqual(try fixture.bytes(in: storage), eventsBefore)
        XCTAssertEqual(fixture.receiver.messages.count, messagesBefore)
        XCTAssertTrue(fixture.core.get(feature: RUMFeature.self) === original)
    }

    func testFlagOffPublicOperationUsesLegacyEventAndMessage() throws {
        try requireOwnedOperations()
        let fixture = try Fixture(multiSceneTrackingEnabled: false)
        defer { fixture.tearDown() }
        let original = fixture.feature
        XCTAssertFalse(original.isMultiSceneTrackingEnabled)
        XCTAssertNil(original.operationOrigin)
        XCTAssertNil(original.rumContextHandoffOwner)
        let session = try XCTUnwrap(original.monitor.applicationScope.activeSession)
        let storage = try XCTUnwrap(fixture.core.stores[RUMFeature.name]?.storage)
        let vitalsBefore = try fixture.storedVitals(in: storage).count
        let legacyBefore = fixture.receiver.legacyMessages.count
        XCTAssertTrue(fixture.receiver.messages.isEmpty)

        original.monitor.startOperation(
            name: "legacy-first",
            operationKey: nil,
            attributes: [:],
            options: ProfilingOptions(sampleRate: 100)
        )
        fixture.drain()

        XCTAssertTrue(fixture.core.get(feature: RUMFeature.self) === original)
        XCTAssertTrue(original.monitor.applicationScope.activeSession === session)
        let vitals = try fixture.storedVitals(in: storage)
        let event = try XCTUnwrap(vitals.last)
        let message = try XCTUnwrap(fixture.receiver.legacyMessages.last)
        XCTAssertEqual(vitals.count, vitalsBefore + 1)
        XCTAssertEqual(event.vital.name, "legacy-first")
        XCTAssertEqual(event.session.id, session.sessionUUID.toRUMDataFormat)
        XCTAssertEqual(message.operation.id, event.vital.id)
        XCTAssertEqual(message.operation.name, event.vital.name)
        XCTAssertEqual(message.operation.stepType, .start)
        XCTAssertEqual(fixture.receiver.legacyMessages.count, legacyBefore + 1)
        XCTAssertTrue(fixture.receiver.messages.isEmpty)
        XCTAssertNil(original.operationOrigin)
        XCTAssertNil(original.rumContextHandoffOwner)
    }

    func testFirstSourceLessOperationUsesOriginalSDKInitializedSession() throws {
        try requireOwnedOperations()
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        let original = fixture.feature
        let owner = try XCTUnwrap(original.rumContextHandoffOwner)
        let origin = try XCTUnwrap(original.operationOrigin)
        let session = try XCTUnwrap(original.monitor.applicationScope.activeSession)
        let sessionID = session.sessionUUID.toRUMDataFormat
        let storage = try XCTUnwrap(fixture.core.stores[RUMFeature.name]?.storage)
        let vitalsBefore = try fixture.storedVitals(in: storage).count
        let ownedBefore = fixture.receiver.messages.count
        let legacyBefore = fixture.receiver.legacyMessages.count
        XCTAssertTrue(origin.isCurrent)
        XCTAssertNil(RUMContextHandoff.captureValue(for: owner))

        original.monitor.startOperation(
            name: "source-less-first",
            operationKey: nil,
            attributes: [:],
            options: ProfilingOptions(sampleRate: 100)
        )
        fixture.drain()

        XCTAssertTrue(fixture.core.get(feature: RUMFeature.self) === original)
        XCTAssertTrue(original.monitor.applicationScope.activeSession === session)
        XCTAssertTrue(original.rumContextHandoffOwner === owner)
        let vitals = try fixture.storedVitals(in: storage)
        let event = try XCTUnwrap(vitals.last)
        let message = try XCTUnwrap(fixture.receiver.messages.last)
        XCTAssertEqual(vitals.count, vitalsBefore + 1)
        XCTAssertEqual(event.vital.name, "source-less-first")
        XCTAssertEqual(event.session.id, sessionID)
        XCTAssertTrue(message.ownership.origin === origin)
        XCTAssertTrue(message.ownership.origin.owner === owner)
        XCTAssertEqual(message.ownership.sessionID, sessionID)
        XCTAssertTrue(message.ownership.isValid)
        XCTAssertEqual(fixture.receiver.messages.count, ownedBefore + 1)
        XCTAssertEqual(fixture.receiver.legacyMessages.count, legacyBefore)
    }

    private func assertStepProjection(
        event: RUMVitalOperationStepEvent,
        message: OwnedOperationMessage,
        expected: RUMCoreContext,
        step: RUMVitalOperationStepEvent.Vital.StepType,
        name: String,
        operationKey: String,
        date: Date
    ) throws {
        XCTAssertEqual(event.application.id, expected.applicationID)
        XCTAssertEqual(event.session.id, expected.sessionID)
        XCTAssertEqual(event.view.id, try XCTUnwrap(expected.viewID))
        XCTAssertEqual(event.view.url, expected.viewPath)
        XCTAssertEqual(event.vital.name, name)
        XCTAssertEqual(event.vital.operationKey, operationKey)
        XCTAssertEqual(event.vital.stepType, step)
        XCTAssertEqual(event.date, date.timeIntervalSince1970.dd.toInt64Milliseconds)
        XCTAssertEqual(message.operation.id, event.vital.id)
        XCTAssertEqual(message.operation.name, name)
        XCTAssertEqual(message.operation.operationKey, operationKey)
        XCTAssertEqual(message.operation.stepType, step)
        XCTAssertEqual(message.operation.date, date)
        XCTAssertEqual(message.ownership.sessionID, expected.sessionID)
        XCTAssertTrue(message.ownership.isValid)
        XCTAssertEqual(message.attributes[RUMCoreContext.IDs.applicationID] as? String, expected.applicationID)
        XCTAssertEqual(message.attributes[RUMCoreContext.IDs.sessionID] as? String, expected.sessionID)
        XCTAssertEqual(message.attributes[RUMCoreContext.IDs.viewID] as? [String], [try XCTUnwrap(expected.viewID)])
        XCTAssertEqual(message.attributes[RUMCoreContext.IDs.viewName] as? [String], [try XCTUnwrap(expected.viewName)])
        XCTAssertNil(expected.userActionID)
        XCTAssertEqual(Set(message.attributes.keys), Set([
            RUMCoreContext.IDs.applicationID,
            RUMCoreContext.IDs.sessionID,
            RUMCoreContext.IDs.viewID,
            RUMCoreContext.IDs.viewName
        ]))
    }

    func testCapturedCrossViewStepsKeepSelectedViewAndOriginalSessionProvenance() throws {
        try requireOwnedOperations()
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        let original = fixture.feature
        let owner = try XCTUnwrap(original.rumContextHandoffOwner)
        let origin = try XCTUnwrap(original.operationOrigin)
        let session = try XCTUnwrap(original.monitor.applicationScope.activeSession)
        fixture.startView("selected-a")
        fixture.drain()
        let captureA = try fixture.capture("selected-a")
        let contextA = try XCTUnwrap(captureA.value.rumContext)
        fixture.clock.now = fixture.clock.now.addingTimeInterval(1)
        fixture.startView("selected-b")
        fixture.drain()
        let captureB = try fixture.capture("selected-b")
        let contextB = try XCTUnwrap(captureB.value.rumContext)
        fixture.clock.now = fixture.clock.now.addingTimeInterval(1)
        fixture.startView("representative-peer")
        fixture.drain()
        let peer = try XCTUnwrap(try fixture.capture("representative-peer").value.rumContext)
        XCTAssertEqual(contextA.sessionID, session.sessionUUID.toRUMDataFormat)
        XCTAssertEqual(contextB.sessionID, contextA.sessionID)
        XCTAssertEqual(peer.sessionID, contextA.sessionID)
        XCTAssertNotEqual(contextA.viewID, contextB.viewID)
        XCTAssertNotEqual(peer.viewID, contextA.viewID)
        XCTAssertNotEqual(peer.viewID, contextB.viewID)
        XCTAssertTrue(captureA.owner === owner)
        XCTAssertTrue(captureB.owner === owner)
        let activeViewIDs = Set(session.viewScopes.filter { $0.isActiveView }.map { $0.viewUUID.toRUMDataFormat })
        XCTAssertTrue(activeViewIDs.contains(try XCTUnwrap(contextA.viewID)))
        XCTAssertTrue(activeViewIDs.contains(try XCTUnwrap(contextB.viewID)))
        XCTAssertTrue(activeViewIDs.contains(try XCTUnwrap(peer.viewID)))
        XCTAssertEqual(original.monitor.rumContextSnapshot(for: .processRepresentative)?.viewID, peer.viewID)
        let storage = try XCTUnwrap(fixture.core.stores[RUMFeature.name]?.storage)
        let vitalsBefore = try fixture.storedVitals(in: storage).count
        let ownedBefore = fixture.receiver.messages.count
        let legacyBefore = fixture.receiver.legacyMessages.count
        let name = "captured-cross-view"
        let key = "request"
        fixture.clock.now = fixture.clock.now.addingTimeInterval(1)
        let startDate = fixture.clock.now

        RUMContextHandoff.withValue(captureA.value, for: captureA.owner) {
            original.monitor.startOperation(
                name: name, operationKey: key, attributes: [:],
                options: ProfilingOptions(sampleRate: 100)
            )
        }
        fixture.drain()
        XCTAssertEqual(original.monitor.rumContextSnapshot(for: .processRepresentative)?.viewID, peer.viewID)
        fixture.clock.now = fixture.clock.now.addingTimeInterval(1)
        let endDate = fixture.clock.now
        RUMContextHandoff.withValue(captureB.value, for: captureB.owner) {
            original.monitor.succeedOperation(name: name, operationKey: key, attributes: [:])
        }
        fixture.drain()

        let vitals = try fixture.storedVitals(in: storage)
        let events = vitals.filter { $0.vital.name == name && $0.vital.operationKey == key }
        let messages = fixture.receiver.messages.filter { $0.operation.name == name && $0.operation.operationKey == key }
        XCTAssertEqual(vitals.count, vitalsBefore + 2)
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(fixture.receiver.messages.count, ownedBefore + 2)
        XCTAssertEqual(fixture.receiver.legacyMessages.count, legacyBefore)
        let startEvent = try XCTUnwrap(events.first { $0.vital.stepType == .start })
        let endEvent = try XCTUnwrap(events.first { $0.vital.stepType == .end })
        let startMessage = try XCTUnwrap(messages.first { $0.operation.stepType == .start })
        let endMessage = try XCTUnwrap(messages.first { $0.operation.stepType == .end })
        try assertStepProjection(event: startEvent, message: startMessage, expected: contextA,
                                 step: .start, name: name, operationKey: key, date: startDate)
        try assertStepProjection(event: endEvent, message: endMessage, expected: contextB,
                                 step: .end, name: name, operationKey: key, date: endDate)
        XCTAssertNotEqual(startEvent.vital.id, endEvent.vital.id)
        XCTAssertTrue(startMessage.ownership === endMessage.ownership)
        XCTAssertTrue(startMessage.ownership.origin === origin)
        XCTAssertTrue(endMessage.ownership.origin.owner === owner)
        XCTAssertTrue(fixture.core.get(feature: RUMFeature.self) === original)
        XCTAssertTrue(original.monitor.applicationScope.activeSession === session)
        XCTAssertEqual(original.monitor.rumContextSnapshot(for: .processRepresentative)?.viewID, peer.viewID)
    }

    func testCapturedStartAndSourceLessEndProjectTheirOwnViewsInSameSession() throws {
        try requireOwnedOperations()
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        let original = fixture.feature
        let owner = try XCTUnwrap(original.rumContextHandoffOwner)
        let origin = try XCTUnwrap(original.operationOrigin)
        let session = try XCTUnwrap(original.monitor.applicationScope.activeSession)
        fixture.startView("captured-start")
        fixture.drain()
        let captureA = try fixture.capture("captured-start")
        let contextA = try XCTUnwrap(captureA.value.rumContext)
        fixture.clock.now = fixture.clock.now.addingTimeInterval(1)
        fixture.startView("source-less-end")
        fixture.drain()
        let contextB = try XCTUnwrap(try fixture.capture("source-less-end").value.rumContext)
        XCTAssertEqual(contextA.sessionID, session.sessionUUID.toRUMDataFormat)
        XCTAssertEqual(contextB.sessionID, contextA.sessionID)
        XCTAssertNotEqual(contextA.viewID, contextB.viewID)
        XCTAssertTrue(captureA.owner === owner)
        let activeViewIDs = Set(session.viewScopes.filter { $0.isActiveView }.map { $0.viewUUID.toRUMDataFormat })
        XCTAssertTrue(activeViewIDs.contains(try XCTUnwrap(contextA.viewID)))
        XCTAssertTrue(activeViewIDs.contains(try XCTUnwrap(contextB.viewID)))
        XCTAssertEqual(original.monitor.rumContextSnapshot(for: .processRepresentative)?.viewID, contextB.viewID)
        let storage = try XCTUnwrap(fixture.core.stores[RUMFeature.name]?.storage)
        let vitalsBefore = try fixture.storedVitals(in: storage).count
        let ownedBefore = fixture.receiver.messages.count
        let legacyBefore = fixture.receiver.legacyMessages.count
        let name = "captured-to-source-less"
        let key = "request"
        fixture.clock.now = fixture.clock.now.addingTimeInterval(1)
        let startDate = fixture.clock.now

        RUMContextHandoff.withValue(captureA.value, for: captureA.owner) {
            original.monitor.startOperation(
                name: name, operationKey: key, attributes: [:],
                options: ProfilingOptions(sampleRate: 100)
            )
        }
        fixture.drain()
        XCTAssertNil(RUMContextHandoff.captureValue(for: owner))
        XCTAssertEqual(original.monitor.rumContextSnapshot(for: .processRepresentative)?.viewID, contextB.viewID)
        fixture.clock.now = fixture.clock.now.addingTimeInterval(1)
        let endDate = fixture.clock.now
        original.monitor.succeedOperation(name: name, operationKey: key, attributes: [:])
        fixture.drain()

        let vitals = try fixture.storedVitals(in: storage)
        let events = vitals.filter { $0.vital.name == name && $0.vital.operationKey == key }
        let messages = fixture.receiver.messages.filter { $0.operation.name == name && $0.operation.operationKey == key }
        XCTAssertEqual(vitals.count, vitalsBefore + 2)
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(fixture.receiver.messages.count, ownedBefore + 2)
        XCTAssertEqual(fixture.receiver.legacyMessages.count, legacyBefore)
        let startEvent = try XCTUnwrap(events.first { $0.vital.stepType == .start })
        let endEvent = try XCTUnwrap(events.first { $0.vital.stepType == .end })
        let startMessage = try XCTUnwrap(messages.first { $0.operation.stepType == .start })
        let endMessage = try XCTUnwrap(messages.first { $0.operation.stepType == .end })
        try assertStepProjection(event: startEvent, message: startMessage, expected: contextA,
                                 step: .start, name: name, operationKey: key, date: startDate)
        try assertStepProjection(event: endEvent, message: endMessage, expected: contextB,
                                 step: .end, name: name, operationKey: key, date: endDate)
        XCTAssertNotEqual(startEvent.vital.id, endEvent.vital.id)
        XCTAssertTrue(startMessage.ownership === endMessage.ownership)
        XCTAssertTrue(startMessage.ownership.origin === origin)
        XCTAssertTrue(endMessage.ownership.origin.owner === owner)
        XCTAssertTrue(fixture.core.get(feature: RUMFeature.self) === original)
        XCTAssertTrue(original.monitor.applicationScope.activeSession === session)
        XCTAssertEqual(original.monitor.rumContextSnapshot(for: .processRepresentative)?.viewID, contextB.viewID)
    }
}
#endif
