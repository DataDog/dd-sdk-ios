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
        let rumEventsData = try XCTUnwrap(metadata.rumEvents)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: rumEventsData) as? [String: Any])
        let vitalsFromJson = try XCTUnwrap(json["vitals"] as? [[String: Any]])
        let vitalIDs = vitalsFromJson.compactMap { $0["id"] as? String }
        let vitalNames = vitalsFromJson.compactMap { $0["name"] as? String }
        XCTAssertEqual(vitalIDs, ["id1", "id2"])
        XCTAssertEqual(vitalNames, ["operation1", "operation2"])
    }
}

private struct ProfilingHandlerMock: ProfilingHandler {
    var attributes: [AttributeKey: AttributeValue]
    var operation: ProfilingOperation
    var featureScope: FeatureScope
    var telemetryController: ProfilingTelemetryController
    var encoder: JSONEncoder
}

#endif // !os(watchOS)
