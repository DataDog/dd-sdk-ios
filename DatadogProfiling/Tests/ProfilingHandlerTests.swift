/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if !os(watchOS)

import XCTest
import DatadogInternal
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
            operation: .appLaunch,
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

    // MARK: - updateProfilingContext

    func testUpdateProfilingContext_whenProfilerIsNotStarted_returnsUnknownStatus() throws {
        // Given
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_NOT_CREATED)

        // When
        let result = handler.updateProfilingContext()

        // Then
        XCTAssertEqual(result.status, .unknown)
        let stored = try XCTUnwrap(core.context.additionalContext(ofType: ProfilingContext.self))
        XCTAssertEqual(stored.status, .unknown)
    }

    func testUpdateProfilingContext_whenProfilerIsRunning_returnsRunningStatus() throws {
        // Given
        XCTAssertEqual(dd_profiler_start(), 1)

        // When
        let result = handler.updateProfilingContext()

        // Then
        XCTAssertEqual(result.status, .running)
        let stored = try XCTUnwrap(core.context.additionalContext(ofType: ProfilingContext.self))
        XCTAssertEqual(stored.status, .running)
    }

    func testUpdateProfilingContext_whenProfilerIsStopped_returnsStoppedStatus() throws {
        // Given
        XCTAssertEqual(dd_profiler_start(), 1)
        dd_profiler_stop()
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_STOPPED)

        // When
        let result = handler.updateProfilingContext()

        // Then
        XCTAssertEqual(result.status, .stopped(reason: .manual))
        let stored = try XCTUnwrap(core.context.additionalContext(ofType: ProfilingContext.self))
        XCTAssertEqual(stored.status, .stopped(reason: .manual))
    }

    // MARK: - write(profile:rumVitals:)

    func testWriteWithNoVitals_doesNotAddVitalAttributesToEvent() throws {
        // Given
        XCTAssertEqual(dd_profiler_start(), 1)
        let profile = try XCTUnwrap(dd_profiler_flush_and_get_profile())

        // When
        handler.write(profile: profile, rumVitals: [])

        // Then
        let event = try XCTUnwrap(core.events.first as? ProfileEvent)
        XCTAssertNil(event.additionalAttributes?[RUMCoreContext.IDs.vitalID])
        XCTAssertNil(event.additionalAttributes?[RUMCoreContext.IDs.vitalLabel])
    }

    func testWriteWithVitals_addsVitalIDsAndLabelsToEvent() throws {
        // Given
        XCTAssertEqual(dd_profiler_start(), 1)
        let profile = try XCTUnwrap(dd_profiler_flush_and_get_profile())
        let vitals = [
            Vital.mockWith(id: "id1", name: "operation1"),
            Vital.mockWith(id: "id2", name: "operation2")
        ]

        // When
        handler.write(profile: profile, rumVitals: vitals)

        // Then
        let event = try XCTUnwrap(core.events.first as? ProfileEvent)
        let vitalIDs = event.additionalAttributes?[RUMCoreContext.IDs.vitalID] as? [String]
        let vitalLabels = event.additionalAttributes?[RUMCoreContext.IDs.vitalLabel] as? [String]
        XCTAssertEqual(vitalIDs, ["id1", "id2"])
        XCTAssertEqual(vitalLabels, ["operation1", "operation2"])
    }

    func testWriteContextAttributes_flowThroughToEvent() throws {
        // Given
        XCTAssertEqual(dd_profiler_start(), 1)
        let profile = try XCTUnwrap(dd_profiler_flush_and_get_profile())
        handler.attributes = ["session.id": "session1", "view.id": ["view1"]]

        // When
        handler.write(profile: profile, rumVitals: [])

        // Then
        let event = try XCTUnwrap(core.events.first as? ProfileEvent)
        XCTAssertEqual(event.additionalAttributes?["session.id"] as? String, "session1")
        XCTAssertEqual(event.additionalAttributes?["view.id"] as? [String], ["view1"])
    }

    func testWriteEvent_hasCorrectStaticFields_andTags() throws {
        // Given
        XCTAssertEqual(dd_profiler_start(), 1)
        let profile = try XCTUnwrap(dd_profiler_flush_and_get_profile())

        // When
        handler.write(profile: profile, rumVitals: [])

        // Then
        let event = try XCTUnwrap(core.events.first as? ProfileEvent)
        XCTAssertEqual(event.family, "ios")
        XCTAssertEqual(event.runtime, "ios")
        XCTAssertEqual(event.version, "4")
        XCTAssertEqual(event.attachments, [
            ProfileAttachments.Constants.wallFilename,
            ProfileAttachments.Constants.rumEventsFilename
        ])

        XCTAssertTrue(event.tags.contains("language:swift"))
        XCTAssertTrue(event.tags.contains("format:pprof"))
        XCTAssertTrue(event.tags.contains("remote_symbols:yes"))
    }

    func testWriteProfileAttachments_containNonEmptyPprofData() throws {
        // Given
        XCTAssertEqual(dd_profiler_start(), 1)
        let profile = try XCTUnwrap(dd_profiler_flush_and_get_profile())

        // When
        handler.write(profile: profile, rumVitals: [])

        // Then
        let metadata = try XCTUnwrap(core.metadata.first as? ProfileAttachments)
        XCTAssertFalse(metadata.pprof.isEmpty)
    }

    func testWriteProfileAttachments_containRumEventsWithProvidedVitals() throws {
        // Given
        XCTAssertEqual(dd_profiler_start(), 1)
        let profile = try XCTUnwrap(dd_profiler_flush_and_get_profile())
        let vitals = [
            Vital.mockWith(id: "id1", name: "operation1"),
            Vital.mockWith(id: "id2", name: "operation2")
        ]

        // When
        handler.write(profile: profile, rumVitals: vitals)

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
        XCTAssertEqual(dd_profiler_start(), 1)
        let profile = try XCTUnwrap(dd_profiler_flush_and_get_profile())
        let vital = Vital.mockWith(id: "vital-id", name: "operation", duration: 60)
        let longTask = DurationEvent(id: "long-task-id", type: .longTask, start: 20, duration: 30)
        let hang = DurationEvent(id: "hang-id", type: .error, start: 40, duration: 50)

        // When
        handler.write(profile: profile, rumVitals: [vital], hangs: [hang], longTasks: [longTask])

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

        dd_profiler_start_testing(100, false, 5.seconds.dd.toInt64Nanoseconds, 0)
        Thread.sleep(forTimeInterval: 0.05)
        let profile = try XCTUnwrap(dd_profiler_flush_and_get_profile())
        let originalStart = dd_pprof_get_start_timestamp_s(profile)
        let originalEnd = dd_pprof_get_end_timestamp_s(profile)

        // When
        handler.write(profile: profile, rumVitals: [vital])

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
        XCTAssertEqual(dd_profiler_start(), 1)
        let profile = try XCTUnwrap(dd_profiler_flush_and_get_profile())
        let featureScope = FeatureScopeMock(deferEventWriteContext: true)
        let telemetry = TelemetryMock()
        let handler = ProfilingHandlerMock(
            attributes: [:],
            currentServerTimeOffset: .zero,
            operation: .customProfiling,
            featureScope: featureScope,
            telemetryController: .init(telemetry: telemetry),
            encoder: JSONEncoder()
        )

        // When
        handler.write(profile: profile, rumVitals: [])
        handler.operation = .continuousProfiling
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

    private func typedRUMEvents(from metadata: ProfileAttachments) throws -> [[String: Any]] {
        let rumEventsData = try XCTUnwrap(metadata.rumEvents)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: rumEventsData) as? [[String: Any]])
    }
}

private final class ProfilingHandlerMock: ProfilingHandler {
    var attributes: [AttributeKey: AttributeValue]
    var currentServerTimeOffset: TimeInterval
    var operation: ProfilingOperation
    var featureScope: FeatureScope
    var telemetryController: ProfilingTelemetryController
    var encoder: JSONEncoder

    init(
        attributes: [AttributeKey: AttributeValue],
        currentServerTimeOffset: TimeInterval,
        operation: ProfilingOperation,
        featureScope: FeatureScope,
        telemetryController: ProfilingTelemetryController,
        encoder: JSONEncoder
    ) {
        self.attributes = attributes
        self.currentServerTimeOffset = currentServerTimeOffset
        self.operation = operation
        self.featureScope = featureScope
        self.telemetryController = telemetryController
        self.encoder = encoder
    }
}

#endif // !os(watchOS)
