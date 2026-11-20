/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if !os(watchOS) && !os(macOS)

import XCTest
import DatadogInternal
import TestUtilities
@testable import DatadogProfiling

final class ProfileWriterTests: XCTestCase {
    private var core: PassthroughCoreMock! // swiftlint:disable:this implicitly_unwrapped_optional
    private var telemetry: TelemetryMock! // swiftlint:disable:this implicitly_unwrapped_optional
    private var writer: ProfileWriter! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUp() {
        super.setUp()
        core = PassthroughCoreMock()
        telemetry = TelemetryMock()
        writer = ProfileWriter(
            featureScope: core.scope(for: ProfilerFeature.self),
            telemetryController: .init(telemetry: telemetry)
        )
    }

    func testWriteCPUProfile_preservesEventFieldsAndAttachmentNames() throws {
        let vital = Vital.mockWith(id: "vital", name: "operation")
        let snapshot = snapshot(rumEvents: [.vital(vital)])

        writer.write([snapshot], operation: .appLaunch)

        let event = try XCTUnwrap(core.events.first as? ProfileEvent)
        XCTAssertEqual(core.events.count, 1)
        XCTAssertEqual(event.family, "ios")
        XCTAssertEqual(event.runtime, "ios")
        XCTAssertEqual(event.version, "4")
        XCTAssertEqual(event.start, snapshot.start)
        XCTAssertEqual(event.end, snapshot.end)
        XCTAssertEqual(event.attachments, ["profile.pprof", "rum-mobile-events.json"])
        XCTAssertTrue(event.tags.contains("language:swift"))
        XCTAssertTrue(event.tags.contains("format:pprof"))
        XCTAssertTrue(event.tags.contains("remote_symbols:yes"))
        XCTAssertTrue(event.tags.contains("operation:application_launch"))

        let attachments = try XCTUnwrap(core.metadata.first as? ProfileAttachments)
        XCTAssertEqual(attachments.pprofs.map(\.filename), ["profile.pprof"])
        XCTAssertEqual(attachments.pprofs.first?.data, snapshot.attachment.data)
        XCTAssertEqual(try typedRUMEvents(from: attachments).count, 1)
        XCTAssertEqual(event.additionalAttributes?[RUMCoreContext.IDs.vitalID] as? [String], [vital.id])
        XCTAssertEqual(event.additionalAttributes?[RUMCoreContext.IDs.vitalLabel] as? [String], [vital.name])
        XCTAssertEqual(telemetry.messages.count, 1)
        XCTAssertNotNil(telemetry.messages.lastMetric(named: ProfilingSessionMetric.Constants.name)?.attributes[AggregationDiagnosticsMetric.Constants.diagnosticsKey])
    }

    func testWriteHeapProfile_containsOnlyHeapPprof() throws {
        let task = DurationEvent(id: "task", type: .longTask, start: 20, duration: 30)
        let heap = snapshot(filename: "heap.pprof", rumEvents: [.longTask(task)], attributes: [
            RUMCoreContext.IDs.applicationID: "app",
            RUMCoreContext.IDs.sessionID: "session",
            RUMCoreContext.IDs.viewID: ["heap-view"]
        ])

        writer.write([heap], operation: .continuousProfiling)

        let event = try XCTUnwrap(core.events.first as? ProfileEvent)
        let attachments = try XCTUnwrap(core.metadata.first as? ProfileAttachments)
        XCTAssertEqual(event.attachments, ["heap.pprof", "rum-mobile-events.json"])
        XCTAssertEqual(try typedRUMEvents(from: attachments).first?["id"] as? String, task.id)
        XCTAssertEqual(attachments.pprofs.map(\.filename), ["heap.pprof"])
        XCTAssertEqual(attachments.pprofs.first?.data, heap.attachment.data)
        XCTAssertEqual(event.additionalAttributes?[RUMCoreContext.IDs.applicationID] as? String, "app")
        XCTAssertEqual(event.additionalAttributes?[RUMCoreContext.IDs.sessionID] as? String, "session")
        XCTAssertEqual(event.additionalAttributes?[RUMCoreContext.IDs.viewID] as? [String], ["heap-view"])

        let encoder = JSONEncoder.dd.default()
        let storedEvent = try Event(data: encoder.encode(event), metadata: encoder.encode(attachments))
        let multipart = MultipartBuilderSpy()
        _ = try RequestBuilder(multipartBuilder: multipart).request(for: [storedEvent], with: .mockAny(), execution: .mockAny())

        XCTAssertEqual(multipart.formFiles.map(\.filename), ["event.json", "heap.pprof", "rum-mobile-events.json"])
        let uploadedEvent = try XCTUnwrap(JSONSerialization.jsonObject(with: multipart.formFiles[0].data) as? [String: Any])
        XCTAssertEqual(uploadedEvent["attachments"] as? [String], ["heap.pprof", "rum-mobile-events.json"])
        XCTAssertEqual(multipart.formFiles[1].data, heap.attachment.data)
        let metric = try XCTUnwrap(telemetry.messages.lastMetric(named: ProfilingSessionMetric.Constants.name))
        XCTAssertNil(metric.attributes[AggregationDiagnosticsMetric.Constants.diagnosticsKey])
    }

    func testWriteTwoSnapshots_writesOneEventWithBothPprofsAndOneRUMAttachment() throws {
        let cpu = snapshot(start: 20, end: 70, rumEvents: [.vital(.mockAny())])
        let heap = snapshot(filename: "heap.pprof", start: 10, end: 60)

        writer.write([cpu, heap], operation: .continuousProfiling)

        XCTAssertEqual(core.events.count, 1)
        XCTAssertEqual(core.metadata.count, 1)
        let event = try XCTUnwrap(core.events.first as? ProfileEvent)
        let attachments = try XCTUnwrap(core.metadata.first as? ProfileAttachments)
        XCTAssertEqual(event.start, heap.start)
        XCTAssertEqual(event.end, cpu.end)
        XCTAssertEqual(event.attachments, ["profile.pprof", "heap.pprof", "rum-mobile-events.json"])
        XCTAssertEqual(attachments.pprofs.map(\.filename), ["profile.pprof", "heap.pprof"])
        XCTAssertEqual(attachments.pprofs.map(\.data), [cpu.attachment.data, heap.attachment.data])
        XCTAssertEqual(telemetry.messages.count, 1)
        XCTAssertNotNil(telemetry.messages.lastMetric(named: ProfilingSessionMetric.Constants.name)?.attributes[AggregationDiagnosticsMetric.Constants.diagnosticsKey])
    }

    func testWrite_selectsOneProvidersRUMDataInEitherSnapshotOrder() throws {
        let vital = Vital.mockWith(id: "vital-1", name: "operation")
        let hang = DurationEvent(id: "hang", type: .error, start: 40, duration: 50)
        let longTask = DurationEvent(id: "long-task", type: .longTask, start: 20, duration: 30)
        let cpu = snapshot(
            rumEvents: [.vital(vital), .hang(hang), .longTask(longTask)],
            attributes: ["application.id": "app", "session.id": "session", "view.id": ["cpu-view"], "view.name": ["CPU view"]]
        )
        let heap = snapshot(
            filename: "heap.pprof",
            rumEvents: [],
            attributes: ["application.id": "app", "session.id": "session", "view.id": ["heap-view"], "view.name": ["Heap view"]]
        )

        for snapshots in [[cpu, heap], [heap, cpu]] {
            writer.write(snapshots, operation: .continuousProfiling)

            let event = try XCTUnwrap(core.events.last as? ProfileEvent)
            XCTAssertEqual(event.additionalAttributes?["application.id"] as? String, "app")
            XCTAssertEqual(event.additionalAttributes?["session.id"] as? String, "session")
            XCTAssertEqual(event.additionalAttributes?["view.id"] as? [String], ["cpu-view"])
            XCTAssertEqual(event.additionalAttributes?["view.name"] as? [String], ["CPU view"])
            XCTAssertEqual(event.additionalAttributes?[RUMCoreContext.IDs.vitalID] as? [String], [vital.id])
            XCTAssertEqual(event.additionalAttributes?[RUMCoreContext.IDs.vitalLabel] as? [String], [vital.name])
            XCTAssertEqual(event.additionalAttributes?[RUMCoreContext.IDs.errorID] as? [String], [hang.id])
            XCTAssertEqual(event.additionalAttributes?[RUMCoreContext.IDs.longTaskID] as? [String], [longTask.id])

            let attachments = try XCTUnwrap(core.metadata.last as? ProfileAttachments)
            let events = try typedRUMEvents(from: attachments)
            XCTAssertEqual(attachments.pprofs.count, 2)
            XCTAssertEqual(events.compactMap { $0["id"] as? String }, [vital.id, hang.id, longTask.id])
        }
    }

    func testWriteUsesCapturedRUMContextAndPreservesEventAttributes() throws {
        let captured = RUMCoreContext.mockWith(
            applicationID: "captured-app",
            sessionID: UUID(),
            viewID: "captured-view",
            viewName: "Captured view"
        )
        let profile = snapshot(attributes: [RUMCoreContext.IDs.viewName: ["Event view"]], rumContext: captured)
        let later = RUMCoreContext.mockWith(
            applicationID: "later-app", sessionID: UUID(), viewID: "later-view", viewName: "Later view"
        )
        core.context = .mockWith(additionalContext: [later])

        writer.write([profile], operation: .continuousProfiling)

        let event = try XCTUnwrap(core.events.first as? ProfileEvent)
        XCTAssertEqual(event.additionalAttributes?[RUMCoreContext.IDs.applicationID] as? String, captured.applicationID)
        XCTAssertEqual(event.additionalAttributes?[RUMCoreContext.IDs.sessionID] as? String, captured.sessionID)
        XCTAssertEqual(event.additionalAttributes?[RUMCoreContext.IDs.viewID] as? [String], ["captured-view"])
        XCTAssertEqual(event.additionalAttributes?[RUMCoreContext.IDs.viewName] as? [String], ["Event view"])
    }

    func testWriteRejectsIncompatibleCapturedRUMContexts() {
        let sessionID = UUID()
        let first = RUMCoreContext.mockWith(applicationID: "app", sessionID: sessionID)
        let incompatible = [
            RUMCoreContext.mockWith(applicationID: "app", sessionID: UUID()),
            RUMCoreContext.mockWith(applicationID: "other-app", sessionID: sessionID)
        ]

        for context in incompatible {
            writer.write([
                snapshot(rumContext: first),
                snapshot(filename: "heap.pprof", rumContext: context)
            ], operation: .continuousProfiling)
        }

        XCTAssertTrue(core.events.isEmpty)
        XCTAssertTrue(core.metadata.isEmpty)
    }

    func testWrite_doesNotMergeRUMDataFromAnotherProvider() throws {
        let selected = Vital.mockWith(id: "selected", name: "Selected")
        let other = Vital.mockWith(id: "other", name: "Other")
        let cpu = snapshot(rumEvents: [.vital(selected)], attributes: ["view.id": ["selected-view"]])
        let another = snapshot(filename: "other.pprof", rumEvents: [.vital(other)], attributes: ["view.id": ["other-view"]])

        writer.write([cpu, another], operation: .continuousProfiling)

        let event = try XCTUnwrap(core.events.first as? ProfileEvent)
        let attachments = try XCTUnwrap(core.metadata.first as? ProfileAttachments)
        let events = try typedRUMEvents(from: attachments)
        XCTAssertEqual(event.additionalAttributes?["view.id"] as? [String], ["selected-view"])
        XCTAssertEqual(event.additionalAttributes?[RUMCoreContext.IDs.vitalID] as? [String], [selected.id])
        XCTAssertEqual(events.compactMap { $0["id"] as? String }, [selected.id])
    }

    func testWriteWithoutRUMEvents_doesNotWriteEvenWithContext() {
        let cpu = snapshot(rumEvents: [], attributes: [RUMCoreContext.IDs.viewID: ["view-1"]])
        let heap = snapshot(filename: "heap.pprof", rumEvents: [], attributes: [RUMCoreContext.IDs.viewID: ["view-2"]])

        for snapshots in [[cpu], [heap], [cpu, heap]] {
            writer.write(snapshots, operation: .continuousProfiling)
        }

        XCTAssertTrue(core.events.isEmpty)
        XCTAssertTrue(core.metadata.isEmpty)
        XCTAssertTrue(telemetry.messages.isEmpty)
    }

    func testRUMEncodingFailure_doesNotWritePprofs() {
        let writer = ProfileWriter(featureScope: core, encoder: FailingJSONEncoder())

        writer.write([snapshot()], operation: .continuousProfiling)

        XCTAssertTrue(core.events.isEmpty)
        XCTAssertTrue(core.metadata.isEmpty)
    }

    func testWriteEmptySnapshots_doesNotWriteOrSendTelemetry() {
        writer.write([], operation: .continuousProfiling)

        XCTAssertTrue(core.events.isEmpty)
        XCTAssertTrue(telemetry.messages.isEmpty)
    }

    func testWriteIncompatibleSessions_dropsWholeBatch() {
        let cpu = snapshot(attributes: ["session.id": "session-1"])
        let heap = snapshot(filename: "heap.pprof", attributes: ["session.id": "session-2"])

        writer.write([cpu, heap], operation: .continuousProfiling)

        XCTAssertTrue(core.events.isEmpty)
        XCTAssertTrue(telemetry.messages.isEmpty)
    }

    func testWriteIncompatibleSessionsAreRejectedWhenSelectedProviderHasNoSession() {
        writer.write([
            snapshot(rumEvents: [.vital(.mockAny())]),
            snapshot(filename: "heap.pprof", attributes: [RUMCoreContext.IDs.sessionID: "session-1"]),
            snapshot(filename: "other.pprof", attributes: [RUMCoreContext.IDs.sessionID: "session-2"])
        ], operation: .continuousProfiling)

        XCTAssertTrue(core.events.isEmpty)
    }

    func testWriteIncompatibleApplications_dropsWholeBatch() {
        let cpu = snapshot(attributes: ["application.id": "app-1"])
        let heap = snapshot(filename: "heap.pprof", attributes: ["application.id": "app-2"])

        writer.write([cpu, heap], operation: .continuousProfiling)

        XCTAssertTrue(core.events.isEmpty)
    }

    func testWriteMissingContext_doesNotEraseContextCapturedByOtherProfiler() throws {
        writer.write(
            [snapshot(attributes: ["session.id": "session"]), snapshot(filename: "heap.pprof")],
            operation: .continuousProfiling
        )

        let event = try XCTUnwrap(core.events.first as? ProfileEvent)
        XCTAssertEqual(event.additionalAttributes?["session.id"] as? String, "session")
    }

    func testWriteCombinedProfilesAboveSizeLimit_dropsWholeBatch() {
        let halfLimit = Int(ProfilerFeature.Constants.maxObjectSize) / 2
        let cpu = snapshot(data: Data(repeating: 1, count: halfLimit))
        let heap = snapshot(filename: "heap.pprof", data: Data(repeating: 2, count: halfLimit + 1))

        writer.write([cpu, heap], operation: .continuousProfiling)

        XCTAssertTrue(core.events.isEmpty)
        XCTAssertEqual(telemetry.messages.count, 1)
        XCTAssertNotNil(telemetry.messages.lastMetric(named: ProfilingSessionMetric.Constants.name)?.attributes[AggregationDiagnosticsMetric.Constants.diagnosticsKey])
    }

    func testWriteCombinedProfilesAtSizeLimit_writesOneEvent() {
        let halfLimit = Int(ProfilerFeature.Constants.maxObjectSize) / 2
        let cpu = snapshot(data: Data(repeating: 1, count: halfLimit))
        let heap = snapshot(filename: "heap.pprof", data: Data(repeating: 2, count: halfLimit))

        writer.write([cpu, heap], operation: .continuousProfiling)

        XCTAssertEqual(core.events.count, 1)
    }

    func testWriteOversizedHeapOnlyProfile_doesNotAttachCPUDiagnostics() throws {
        let heap = snapshot(filename: "heap.pprof", data: Data(repeating: 1, count: Int(ProfilerFeature.Constants.maxObjectSize) + 1))

        writer.write([heap], operation: .continuousProfiling)

        XCTAssertTrue(core.events.isEmpty)
        let metric = try XCTUnwrap(telemetry.messages.lastMetric(named: ProfilingSessionMetric.Constants.name))
        XCTAssertNil(metric.attributes[AggregationDiagnosticsMetric.Constants.diagnosticsKey])
    }

    func testWriteDeferredContext_preservesOperationAndCapturedData() throws {
        let featureScope = FeatureScopeMock(deferEventWriteContext: true)
        let writer = ProfileWriter(featureScope: featureScope, telemetryController: .init(telemetry: telemetry))
        var snapshots = [snapshot(rumEvents: [.vital(.mockAny())], attributes: ["session.id": "captured-session"])]

        writer.write(snapshots, operation: .customProfiling)
        snapshots = [snapshot(filename: "heap.pprof", attributes: ["session.id": "later-session"])]
        featureScope.flushDeferredEventWriteContexts()

        let event = try XCTUnwrap(featureScope.eventsWritten(ofType: ProfileEvent.self).first)
        XCTAssertTrue(event.tags.contains("operation:custom"))
        XCTAssertEqual(event.attachments, ["profile.pprof", "rum-mobile-events.json"])
        XCTAssertEqual(event.additionalAttributes?["session.id"] as? String, "captured-session")
        let metricTelemetry = try XCTUnwrap(telemetry.messages.lastMetric(named: ProfilingSessionMetric.Constants.name))
        let metric = try XCTUnwrap(
            metricTelemetry.attributes[ProfilingSessionMetric.Constants.sessionKey] as? ProfilingSessionMetric.Attributes
        )
        XCTAssertEqual(metric.startReason, ProfilingSessionMetric.StartReason.rumOperation.rawValue)
    }

    private func snapshot(
        filename: String = "profile.pprof",
        data: Data = Data([1, 2, 3]),
        start: TimeInterval = 10,
        end: TimeInterval = 70,
        rumEvents: [RUMEvent] = [.vital(.mockAny())],
        attributes: [AttributeKey: AttributeValue] = [:],
        rumContext: RUMCoreContext? = nil
    ) -> ProfileSnapshot {
        ProfileSnapshot(
            start: Date(timeIntervalSince1970: start),
            end: Date(timeIntervalSince1970: end),
            attachment: .init(filename: filename, data: data),
            rumEvents: rumEvents,
            attributes: attributes,
            rumContext: rumContext
        )
    }

    private func typedRUMEvents(from metadata: ProfileAttachments) throws -> [[String: Any]] {
        let data = metadata.rumEvents
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
    }
}

private final class FailingJSONEncoder: JSONEncoder, @unchecked Sendable {
    private enum Failure: Error { case encoding }

    override func encode<T: Encodable>(_ value: T) throws -> Data {
        throw Failure.encoding
    }
}

#endif // !os(watchOS) && !os(macOS)
