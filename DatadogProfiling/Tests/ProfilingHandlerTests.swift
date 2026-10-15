/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if !os(watchOS)

import XCTest
@_spi(Internal) import DatadogInternal
import TestUtilities
@testable import DatadogProfiling
//swiftlint:disable duplicate_imports
import DatadogMachProfiler
import DatadogMachProfiler.Testing
//swiftlint:enable duplicate_imports

final class ProfilingHandlerTests: XCTestCase {
    private var core: PassthroughCoreMock! // swiftlint:disable:this implicitly_unwrapped_optional
    private var handler: ProfilingHandlerMock! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUp() {
        super.setUp()
        core = PassthroughCoreMock()
        handler = ProfilingHandlerMock(
            attributes: [:],
            currentServerTimeOffset: .zero,
            featureScope: core.scope(for: ProfilerFeature.self),
            telemetryController: .init(),
            encoder: JSONEncoder()
        )
        dd_profiler_stop()
        dd_profiler_destroy()
    }

    override func tearDown() {
        dd_profiler_stop()
        dd_profiler_destroy()
        dd_delete_profiling_defaults()
        super.tearDown()
    }

    // MARK: - write(profile:rumVitals:)

    func testWriteWithNoVitals_doesNotAddVitalAttributesToEvent() throws {
        // Given
        let profile = try startProfilerAndFlushSampledProfile()

        // When
        handler.write(profile: profile, operation: .appLaunch, rumVitals: [])

        // Then
        let event = try XCTUnwrap(core.events.first as? ProfileEvent)
        XCTAssertNil(event.additionalAttributes?[RUMCoreContext.IDs.vitalID])
        XCTAssertNil(event.additionalAttributes?[RUMCoreContext.IDs.vitalLabel])
    }

    func testWriteWithVitals_addsVitalIDsAndLabelsToEvent() throws {
        // Given
        let profile = try startProfilerAndFlushSampledProfile()
        let vitals = [
            Vital.mockWith(id: "id1", name: "operation1"),
            Vital.mockWith(id: "id2", name: "operation2")
        ]

        // When
        handler.write(profile: profile, operation: .appLaunch, rumVitals: vitals)

        // Then
        let event = try XCTUnwrap(core.events.first as? ProfileEvent)
        let vitalIDs = event.additionalAttributes?[RUMCoreContext.IDs.vitalID] as? [String]
        let vitalLabels = event.additionalAttributes?[RUMCoreContext.IDs.vitalLabel] as? [String]
        XCTAssertEqual(vitalIDs, ["id1", "id2"])
        XCTAssertEqual(vitalLabels, ["operation1", "operation2"])
    }

    func testWriteContextAttributes_flowThroughToEvent() throws {
        // Given
        let profile = try startProfilerAndFlushSampledProfile()
        handler.attributes = ["session.id": "session1", "view.id": ["view1"]]

        // When
        handler.write(profile: profile, operation: .appLaunch, rumVitals: [])

        // Then
        let event = try XCTUnwrap(core.events.first as? ProfileEvent)
        XCTAssertEqual(event.additionalAttributes?["session.id"] as? String, "session1")
        XCTAssertEqual(event.additionalAttributes?["view.id"] as? [String], ["view1"])
    }

    func testWriteEvent_hasCorrectStaticFields_andTags() throws {
        // Given
        let profile = try startProfilerAndFlushSampledProfile()

        // When
        handler.write(profile: profile, operation: .appLaunch, rumVitals: [])

        // Then
        let event = try XCTUnwrap(core.events.first as? ProfileEvent)
        XCTAssertEqual(event.family, "ios")
        XCTAssertEqual(event.runtime, "ios")
        XCTAssertEqual(event.version, "4")
        XCTAssertEqual(event.attachments, [
            ProfileAttachments.Constants.pprofFilename,
            ProfileAttachments.Constants.rumEventsFilename
        ])

        XCTAssertTrue(event.tags.contains("language:swift"))
        XCTAssertTrue(event.tags.contains("format:pprof"))
        XCTAssertTrue(event.tags.contains("remote_symbols:yes"))
    }

    func testWriteProfileAttachments_containNonEmptyPprofData() throws {
        // Given
        let profile = try startProfilerAndFlushSampledProfile()

        // When
        handler.write(profile: profile, operation: .appLaunch, rumVitals: [])

        // Then
        let metadata = try XCTUnwrap(core.metadata.first as? ProfileAttachments)
        XCTAssertFalse(metadata.pprof.isEmpty)
    }

    func testWriteProfileAttachments_containRumEventsWithProvidedVitals() throws {
        // Given
        let profile = try startProfilerAndFlushSampledProfile()
        let vitals = [
            Vital.mockWith(id: "id1", name: "operation1"),
            Vital.mockWith(id: "id2", name: "operation2")
        ]

        // When
        handler.write(profile: profile, operation: .appLaunch, rumVitals: vitals)

        // Then
        let metadata = try XCTUnwrap(core.metadata.first as? ProfileAttachments)
        let vitalsFromJson = try typedRUMEvents(from: metadata)
            .filter { $0["type"] as? String == "vital" }
        let vitalIDs = vitalsFromJson.compactMap { $0["id"] as? String }
        let vitalNames = vitalsFromJson.compactMap { $0["name"] as? String }
        XCTAssertEqual(vitalIDs, ["id1", "id2"])
        XCTAssertEqual(vitalNames, ["operation1", "operation2"])
    }

    func testWriteProfileAttachments_encodeTypedRumEventsForAllSupportedTypes() throws {
        // Given
        let profile = try startProfilerAndFlushSampledProfile()
        let vital = Vital.mockWith(id: "vital-id", name: "operation", duration: 60)
        let longTask = DurationEvent(id: "long-task-id", type: .longTask, start: 20, duration: 30)
        let hang = DurationEvent(id: "hang-id", type: .error, start: 40, duration: 50)

        // When
        handler.write(profile: profile, operation: .appLaunch, rumVitals: [vital], hangs: [hang], longTasks: [longTask])

        // Then
        let metadata = try XCTUnwrap(core.metadata.first as? ProfileAttachments)
        let rumEvents = try typedRUMEvents(from: metadata)
        XCTAssertEqual(rumEvents.count, 3)

        let vitalEvent = try XCTUnwrap(rumEvents.first { $0["type"] as? String == "vital" })
        XCTAssertEqual(vitalEvent["id"] as? String, vital.id)
        XCTAssertEqual(vitalEvent["name"] as? String, vital.name)
        XCTAssertNotNil(vitalEvent["start_ns"] as? NSNumber)
        XCTAssertNotNil(vitalEvent["duration_ns"] as? NSNumber)

        let longTaskEvent = try XCTUnwrap(rumEvents.first { $0["type"] as? String == "long_task" })
        XCTAssertEqual(longTaskEvent["id"] as? String, longTask.id)
        XCTAssertNil(longTaskEvent["name"])
        XCTAssertEqual(longTaskEvent["start_ns"] as? NSNumber, NSNumber(value: longTask.start))
        XCTAssertEqual(longTaskEvent["duration_ns"] as? NSNumber, NSNumber(value: longTask.duration))

        let errorEvent = try XCTUnwrap(rumEvents.first { $0["type"] as? String == "error" })
        XCTAssertEqual(errorEvent["id"] as? String, hang.id)
        XCTAssertNil(errorEvent["name"])
        XCTAssertEqual(errorEvent["start_ns"] as? NSNumber, NSNumber(value: hang.start))
        XCTAssertEqual(errorEvent["duration_ns"] as? NSNumber, NSNumber(value: hang.duration))
    }

    func testWrite_withServerTimeOffset_updatesExportedProfileDatesAndRumVitalTimestamps() throws {
        // Given
        let serverTimeOffset: TimeInterval = 2
        let vitalDate = Date(timeIntervalSince1970: 10)
        handler.currentServerTimeOffset = serverTimeOffset
        let vital = Vital.mockWith(
            id: "vital-id",
            name: "vital-name",
            operationKey: nil,
            stepType: nil,
            date: vitalDate,
            serverTimeOffset: serverTimeOffset
        )

        let profile = try startProfilerAndFlushSampledProfile()
        let originalStart = dd_pprof_get_start_timestamp_s(profile)
        let originalEnd = dd_pprof_get_end_timestamp_s(profile)

        // When
        handler.write(profile: profile, operation: .appLaunch, rumVitals: [vital])

        // Then
        let event = try XCTUnwrap(core.events.first as? ProfileEvent)
        XCTAssertEqual(event.start.timeIntervalSince1970, originalStart + serverTimeOffset, accuracy: 0.001)
        XCTAssertEqual(event.end.timeIntervalSince1970, originalEnd + serverTimeOffset, accuracy: 0.001)

        let metadata = try XCTUnwrap(core.metadata.first as? ProfileAttachments)
        let vitalsFromJson = try typedRUMEvents(from: metadata).filter { $0["type"] as? String == "vital" }
        let start = try XCTUnwrap(vitalsFromJson.first?["start_ns"] as? Int64)
        XCTAssertEqual(start, vitalDate.addingTimeInterval(serverTimeOffset).timeIntervalSince1970.dd.toInt64Nanoseconds)
    }

    func testWrite_capturesOperationBeforeEventWriteContextIsExecuted() throws {
        // Given
        let profile = try startProfilerAndFlushSampledProfile()
        let featureScope = FeatureScopeMock(deferEventWriteContext: true)
        let telemetry = TelemetryMock()
        let handler = ProfilingHandlerMock(
            attributes: [:],
            currentServerTimeOffset: .zero,
            featureScope: featureScope,
            telemetryController: .init(telemetry: telemetry),
            encoder: JSONEncoder()
        )

        // When
        handler.write(profile: profile, operation: .customProfiling, rumVitals: [])
        featureScope.flushDeferredEventWriteContexts()

        // Then
        let event = try XCTUnwrap(featureScope.eventsWritten(ofType: ProfileEvent.self).first)
        XCTAssertTrue(event.tags.contains("operation:custom"))

        let metricTelemetry = try XCTUnwrap(telemetry.messages.lastMetric(named: ProfilingSessionMetric.Constants.name))
        let metric = try XCTUnwrap(
            metricTelemetry.attributes[ProfilingSessionMetric.Constants.sessionKey] as? ProfilingSessionMetric.Attributes
        )
        XCTAssertEqual(metric.startReason, ProfilingSessionMetric.StartReason.rumOperation.rawValue)
    }

    func testOwnedCustomProfile_keepsCapturedAttributionWhenHandlerAttributesChangeBeforeWrite() throws {
        let fixture = OwnedProfileFixture()
        let ownership = try fixture.ownership()
        let scope = OwnedProfileDeferredScope(core: core)
        let telemetry = TelemetryMock()
        let correlation: [AttributeKey: AttributeValue] = [
            RUMCoreContext.IDs.sessionID: "original-session",
            RUMCoreContext.IDs.viewID: ["original-view"]
        ]
        let ownedHandler = makeOwnedHandler(scope: scope, telemetry: telemetry, attributes: correlation)
        let vital = Vital(id: "original-operation", name: "operation", operationKey: nil,
                          stepType: .start, date: fixture.date)
        let stamp = OwnedProfileCorrelation(ownership: ownership, generation: UUID(),
                                            installedKeys: Set(correlation.keys))
        let profile = try startProfilerAndFlushSampledProfile()

        ownedHandler.writeOwned(profile: profile, operation: .customProfiling, rumVitals: [],
                           ownedOperations: [.init(vital: vital, ownership: ownership)], ownedCorrelation: stamp)
        XCTAssertEqual(scope.pendingWrites, 1)
        XCTAssertTrue(core.events.isEmpty)
        ownedHandler.attributes = [RUMCoreContext.IDs.sessionID: "later-session"]
        scope.flush()

        let event = try XCTUnwrap(core.events.first as? ProfileEvent)
        XCTAssertEqual(core.events.count, 1)
        XCTAssertEqual(event.additionalAttributes?[RUMCoreContext.IDs.sessionID] as? String, "original-session")
        XCTAssertEqual(event.additionalAttributes?[RUMCoreContext.IDs.viewID] as? [String], ["original-view"])
        XCTAssertEqual(event.additionalAttributes?[RUMCoreContext.IDs.vitalID] as? [String], [vital.id])
        let metadata = try XCTUnwrap(core.metadata.first as? ProfileAttachments)
        XCTAssertEqual(try typedRUMEvents(from: metadata).compactMap { $0["id"] as? String }, [vital.id])
        XCTAssertNotNil(telemetry.messages.lastMetric(named: ProfilingSessionMetric.Constants.name))
        XCTAssertEqual(scope.pendingWrites, 0)
    }

    func testOwnedCustomProfile_retiredBeforeDeferredWrite_emitsNoEventAttachmentsOrSuccessTelemetry() throws {
        let fixture = OwnedProfileFixture()
        let ownership = try fixture.ownership()
        let scope = OwnedProfileDeferredScope(core: core)
        let telemetry = TelemetryMock()
        let correlation: [AttributeKey: AttributeValue] = [RUMCoreContext.IDs.sessionID: "original-session"]
        let ownedHandler = makeOwnedHandler(scope: scope, telemetry: telemetry, attributes: correlation)
        let vital = Vital(id: "retired-operation", name: "operation", operationKey: nil,
                          stepType: .start, date: fixture.date)
        let stamp = OwnedProfileCorrelation(ownership: ownership, generation: UUID(),
                                            installedKeys: Set(correlation.keys))
        let profile = try startProfilerAndFlushSampledProfile()

        ownedHandler.writeOwned(profile: profile, operation: .customProfiling, rumVitals: [],
                           ownedOperations: [.init(vital: vital, ownership: ownership)], ownedCorrelation: stamp)
        XCTAssertEqual(scope.pendingWrites, 1)
        XCTAssertTrue(core.events.isEmpty)
        XCTAssertTrue(ownership.isValid)
        fixture.origin.retire()
        XCTAssertFalse(ownership.isValid)
        ownedHandler.attributes = [RUMCoreContext.IDs.sessionID: "replacement-session"]
        scope.flush()

        XCTAssertTrue(core.events.isEmpty)
        XCTAssertTrue(core.metadata.isEmpty)
        XCTAssertTrue(telemetry.messages.isEmpty)
        XCTAssertEqual(scope.pendingWrites, 0)
    }

    func testMixedAppLaunchProfile_retiredOwnedOperation_preservesLegacyVitalHangAndLongTask() throws {
        let fixture = OwnedProfileFixture()
        let ownership = try fixture.ownership()
        let scope = OwnedProfileDeferredScope(core: core)
        let telemetry = TelemetryMock()
        let correlation: [AttributeKey: AttributeValue] = [
            RUMCoreContext.IDs.sessionID: "original-session",
            RUMCoreContext.IDs.viewID: ["original-view"]
        ]
        var attributes = correlation
        attributes["customer-attribute"] = "preserved"
        let ownedHandler = makeOwnedHandler(scope: scope, telemetry: telemetry, attributes: attributes)
        let owned = Vital(id: "retired-operation", name: "operation", operationKey: nil,
                          stepType: .start, date: fixture.date)
        let legacy = Vital.mockWith(id: "legacy-vital", name: "legacy")
        let hang = DurationEvent(id: "hang", type: .error, start: 40, duration: 50)
        let longTask = DurationEvent(id: "long-task", type: .longTask, start: 20, duration: 30)
        let stamp = OwnedProfileCorrelation(ownership: ownership, generation: UUID(),
                                            installedKeys: Set(correlation.keys))
        let profile = try startProfilerAndFlushSampledProfile()

        ownedHandler.writeOwned(profile: profile, operation: .appLaunch, rumVitals: [legacy],
                           hangs: [hang], longTasks: [longTask],
                           ownedOperations: [.init(vital: owned, ownership: ownership)], ownedCorrelation: stamp)
        XCTAssertEqual(scope.pendingWrites, 1)
        fixture.origin.retire()
        XCTAssertFalse(ownership.isValid)
        scope.flush()

        let event = try XCTUnwrap(core.events.first as? ProfileEvent)
        XCTAssertEqual(core.events.count, 1)
        XCTAssertTrue(event.tags.contains("operation:application_launch"))
        XCTAssertNil(event.additionalAttributes?[RUMCoreContext.IDs.sessionID])
        XCTAssertNil(event.additionalAttributes?[RUMCoreContext.IDs.viewID])
        XCTAssertEqual(event.additionalAttributes?["customer-attribute"] as? String, "preserved")
        XCTAssertEqual(event.additionalAttributes?[RUMCoreContext.IDs.vitalID] as? [String], [legacy.id])
        XCTAssertEqual(event.additionalAttributes?[RUMCoreContext.IDs.errorID] as? [String], [hang.id])
        XCTAssertEqual(event.additionalAttributes?[RUMCoreContext.IDs.longTaskID] as? [String], [longTask.id])
        let metadata = try XCTUnwrap(core.metadata.first as? ProfileAttachments)
        let events = try typedRUMEvents(from: metadata)
        XCTAssertEqual(events.count, 3)
        XCTAssertEqual(Set(events.compactMap { $0["id"] as? String }), Set([legacy.id, hang.id, longTask.id]))
        XCTAssertNotNil(telemetry.messages.lastMetric(named: ProfilingSessionMetric.Constants.name))
        XCTAssertEqual(scope.pendingWrites, 0)
    }

    private func makeOwnedHandler(
        scope: FeatureScope,
        telemetry: TelemetryMock,
        attributes: [AttributeKey: AttributeValue]
    ) -> ProfilingHandlerMock {
        ProfilingHandlerMock(attributes: attributes, currentServerTimeOffset: .zero,
                             featureScope: scope, telemetryController: .init(telemetry: telemetry),
                             encoder: JSONEncoder())
    }

    private func typedRUMEvents(from metadata: ProfileAttachments) throws -> [[String: Any]] {
        let rumEventsData = try XCTUnwrap(metadata.rumEvents)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: rumEventsData) as? [[String: Any]])
    }

    private func startProfilerAndFlushSampledProfile() throws -> OpaquePointer {
        XCTAssertEqual(dd_profiler_start(), 1)
        dd_profiler_stop()

        let trace = UnsafeMutablePointer<stack_trace_t>.allocate(capacity: 1)
        trace.pointee = .mockWith(
            tid: 1,
            addresses: [0x100001000],
            timestamp: DispatchTime.now().uptimeNanoseconds
        )
        dd_pprof_add_samples(dd_profiler_get_profile(), trace, 1)
        dd_free(trace)

        return try XCTUnwrap(dd_profiler_flush_and_get_profile())
    }
}

private final class ProfilingHandlerMock: ProfilingHandler {
    var attributes: [AttributeKey: AttributeValue]
    var currentServerTimeOffset: TimeInterval
    var featureScope: FeatureScope
    var telemetryController: ProfilingTelemetryController
    var encoder: JSONEncoder

    init(
        attributes: [AttributeKey: AttributeValue],
        currentServerTimeOffset: TimeInterval,
        featureScope: FeatureScope,
        telemetryController: ProfilingTelemetryController,
        encoder: JSONEncoder
    ) {
        self.attributes = attributes
        self.currentServerTimeOffset = currentServerTimeOffset
        self.featureScope = featureScope
        self.telemetryController = telemetryController
        self.encoder = encoder
    }
}

private final class OwnedProfileFixture {
    private final class OriginalFeature: DatadogFeature, RUMOperationOriginProviding {
        static let name = "rum"
        let messageReceiver: FeatureMessageReceiver = NOPFeatureMessageReceiver()
        var operationOrigin: RUMOperationOrigin?
        let monitor = NSObject()
        func isOperationMonitor(_ monitor: AnyObject) -> Bool { self.monitor === monitor }
        func isOperationSessionActive(start: TimeInterval, lastInteraction: TimeInterval) -> Bool { true }
    }

    private let feature = OriginalFeature()
    private let core: SingleFeatureCoreMock<OriginalFeature>
    let origin: RUMOperationOrigin
    let date = Date(timeIntervalSince1970: 100)

    init() {
        core = SingleFeatureCoreMock(feature: feature)
        origin = RUMOperationOrigin(core: core, owner: RUMContextHandoff.Owner())
        feature.operationOrigin = origin
        origin.attach(feature: feature, monitor: feature.monitor)
        origin.setSession("original-session")
        origin.updateSession("original-session", start: 0, lastInteraction: 0)
    }

    func ownership() throws -> RUMOperationOwnership {
        try XCTUnwrap(origin.ownership(for: "original-session"))
    }
}

/// Holds the real writer closure for an explicit synchronous test drain.
private final class OwnedProfileDeferredScope: FeatureScope, @unchecked Sendable {
    private let core: PassthroughCoreMock
    private var deferred: [(Bool, (DatadogContext, Writer) -> Void)] = []
    let telemetry: Telemetry = NOPTelemetry()
    var dataStore: DataStore { core.dataStore }
    var pendingWrites: Int { deferred.count }

    init(core: PassthroughCoreMock) { self.core = core }

    func eventWriteContext(bypassConsent: Bool, _ block: @escaping (DatadogContext, Writer) -> Void) {
        deferred.append((bypassConsent, block))
    }

    func flush() {
        let pending = deferred
        deferred.removeAll()
        pending.forEach { core.eventWriteContext(bypassConsent: $0.0, $0.1) }
    }

    func context(_ block: @escaping (DatadogContext) -> Void) { core.context(block) }
    func send(message: FeatureMessage, else fallback: @escaping () -> Void) { core.send(message: message, else: fallback) }
    func set<Context>(context: @escaping () -> Context?) where Context: AdditionalContext { core.set(context: context) }
    func set(anonymousId: String?) { core.set(anonymousId: anonymousId) }
}

#endif // !os(watchOS)
