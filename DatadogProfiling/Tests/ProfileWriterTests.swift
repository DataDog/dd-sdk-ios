/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if !os(watchOS) && !os(macOS)

import XCTest
import DatadogInternal
import DatadogMachProfiler
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
        XCTAssertNotNil(telemetry.messages.lastMetric(named: ProfilingSessionMetric.Constants.name)?.attributes[ProfilingDiagnostics.Constants.diagnosticsKey])
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
        XCTAssertNil(metric.attributes[ProfilingDiagnostics.Constants.diagnosticsKey])
    }

    func testWriteTriggeredHeapProfile_serializesTriggerOperationTag() throws {
        let warning = DurationEvent(id: "warning", type: .error, start: 20, duration: 0)
        let heap = snapshot(filename: "heap.pprof", rumEvents: [.error(warning)])

        writer.write([heap], operation: .trigger)

        let event = try XCTUnwrap(core.events.first as? ProfileEvent)
        let data = try JSONEncoder.dd.default().encode(event)
        let uploadedEvent = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let tags = try XCTUnwrap(uploadedEvent["tags_profiler"] as? String)
        XCTAssertTrue(tags.split(separator: ",").contains("operation:trigger"))
        XCTAssertFalse(tags.split(separator: ",").contains("operation:continuous"))
        XCTAssertEqual(event.attachments, ["heap.pprof", "rum-mobile-events.json"])
        XCTAssertEqual(event.additionalAttributes?[RUMCoreContext.IDs.errorID] as? [String], [warning.id])
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
        XCTAssertNotNil(telemetry.messages.lastMetric(named: ProfilingSessionMetric.Constants.name)?.attributes[ProfilingDiagnostics.Constants.diagnosticsKey])
    }

    func testWritePrefersCPURUMDataInEitherSnapshotOrder() throws {
        let vital = Vital.mockWith(id: "vital-1", name: "operation")
        let hang = DurationEvent(id: "hang", type: .error, start: 40, duration: 50)
        let longTask = DurationEvent(id: "long-task", type: .longTask, start: 20, duration: 30)
        let cpu = snapshot(
            rumEvents: [.vital(vital), .error(hang), .longTask(longTask)],
            attributes: ["application.id": "app", "session.id": "session", "view.id": ["cpu-view"], "view.name": ["CPU view"]]
        )
        let heap = snapshot(
            filename: "heap.pprof",
            rumEvents: [.longTask(.init(id: "heap-task", type: .longTask, start: 20, duration: 30))],
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

    func testWriteSeparatesIncompatibleCapturedSessions() throws {
        let first = RUMCoreContext.mockWith(applicationID: "app", sessionID: UUID())
        let second = RUMCoreContext.mockWith(applicationID: "app", sessionID: UUID())
        let vital = Vital.mockWith(id: "cpu-vital", name: "operation")
        let task = DurationEvent(id: "heap-task", type: .longTask, start: 20, duration: 30)
        let cpu = snapshot(data: Data([1]), start: 10, end: 60, rumEvents: [.vital(vital)], rumContext: first)
        let heap = snapshot(filename: "heap.pprof", data: Data([2]), start: 20, end: 70, rumEvents: [.longTask(task)], rumContext: second)

        writer.write([cpu, heap], operation: .continuousProfiling)

        let events: [ProfileEvent] = core.events()
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(core.metadata.count, 2)
        guard events.count == 2, core.metadata.count == 2 else {
            return
        }
        for (index, captured) in [cpu, heap].enumerated() {
            let event = events[index]
            let attachments = try XCTUnwrap(core.metadata[index] as? ProfileAttachments)
            XCTAssertEqual(event.additionalAttributes?[RUMCoreContext.IDs.applicationID] as? String, captured.rumContext?.applicationID)
            XCTAssertEqual(event.additionalAttributes?[RUMCoreContext.IDs.sessionID] as? String, captured.rumContext?.sessionID)
            XCTAssertEqual(event.start, captured.start)
            XCTAssertEqual(event.end, captured.end)
            XCTAssertEqual(event.attachments, [captured.attachment.filename, "rum-mobile-events.json"])
            XCTAssertEqual(attachments.pprofs.map(\.filename), [captured.attachment.filename])
            XCTAssertEqual(attachments.pprofs.map(\.data), [captured.attachment.data])
            XCTAssertEqual(try typedRUMEvents(from: attachments).compactMap { $0["id"] as? String }, [index == 0 ? vital.id : task.id])
        }
    }

    func testWriteUsesHeapRUMDataWhenCPUHasNoEvents() throws {
        let task = DurationEvent(id: "heap-task", type: .longTask, start: 20, duration: 30)
        let cpu = snapshot(rumEvents: [], attributes: ["view.id": ["cpu-view"]])
        let heap = snapshot(filename: "heap.pprof", rumEvents: [.longTask(task)], attributes: ["view.id": ["heap-view"]])

        for snapshots in [[cpu, heap], [heap, cpu]] {
            writer.write(snapshots, operation: .continuousProfiling)

            let event = try XCTUnwrap(core.events.last as? ProfileEvent)
            let attachments = try XCTUnwrap(core.metadata.last as? ProfileAttachments)
            XCTAssertEqual(event.additionalAttributes?["view.id"] as? [String], ["heap-view"])
            XCTAssertEqual(event.additionalAttributes?[RUMCoreContext.IDs.longTaskID] as? [String], [task.id])
            XCTAssertEqual(try typedRUMEvents(from: attachments).compactMap { $0["id"] as? String }, [task.id])
            XCTAssertEqual(Set(attachments.pprofs.map(\.filename)), ["profile.pprof", "heap.pprof"])
            let metric = try XCTUnwrap(telemetry.messages.lastMetric(named: ProfilingSessionMetric.Constants.name))
            XCTAssertNotNil(metric.attributes[ProfilingDiagnostics.Constants.diagnosticsKey])
        }
        XCTAssertEqual(core.events.count, 2)
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

    func testWriteSeparatesIncompatibleSessionsFromAttributes() throws {
        let cpu = snapshot(attributes: [RUMCoreContext.IDs.sessionID: "first"])
        let heap = snapshot(filename: "heap.pprof", attributes: [RUMCoreContext.IDs.sessionID: "second"])

        writer.write([cpu, heap], operation: .continuousProfiling)

        let events: [ProfileEvent] = core.events()
        XCTAssertEqual(events.count, 2)
        let first = try XCTUnwrap(events.first)
        let second = try XCTUnwrap(events.last)
        XCTAssertEqual(first.additionalAttributes?[RUMCoreContext.IDs.sessionID] as? String, "first")
        XCTAssertEqual(second.additionalAttributes?[RUMCoreContext.IDs.sessionID] as? String, "second")
        XCTAssertEqual(first.attachments, ["profile.pprof", "rum-mobile-events.json"])
        XCTAssertEqual(second.attachments, ["heap.pprof", "rum-mobile-events.json"])
        XCTAssertEqual(telemetry.messages.count, 2)
    }

    func testWriteSeparatesIncompatibleSessionsWhenSelectedProviderHasNoSession() throws {
        writer.write([
            snapshot(rumEvents: [.vital(.mockAny())]),
            snapshot(filename: "heap.pprof", attributes: [RUMCoreContext.IDs.sessionID: "session-1"]),
            snapshot(filename: "other.pprof", attributes: [RUMCoreContext.IDs.sessionID: "session-2"])
        ], operation: .continuousProfiling)

        let events: [ProfileEvent] = core.events()
        XCTAssertEqual(events.count, 3)
        guard events.count == 3 else {
            return
        }
        XCTAssertNil(events[0].additionalAttributes?[RUMCoreContext.IDs.sessionID])
        XCTAssertEqual(events[1].additionalAttributes?[RUMCoreContext.IDs.sessionID] as? String, "session-1")
        XCTAssertEqual(events[2].additionalAttributes?[RUMCoreContext.IDs.sessionID] as? String, "session-2")
        XCTAssertEqual(events.map(\.attachments), [
            ["profile.pprof", "rum-mobile-events.json"],
            ["heap.pprof", "rum-mobile-events.json"],
            ["other.pprof", "rum-mobile-events.json"]
        ])
    }

    func testWriteIncompatibleSessionsDoesNotUseAnotherSessionsRUMEvents() throws {
        let vital = Vital.mockWith(id: "cpu-vital", name: "operation")
        let cpu = snapshot(rumEvents: [.vital(vital)], attributes: [RUMCoreContext.IDs.sessionID: "session-1"])
        let heap = snapshot(filename: "heap.pprof", rumEvents: [], attributes: [RUMCoreContext.IDs.sessionID: "session-2"])

        writer.write([heap, cpu], operation: .continuousProfiling)

        XCTAssertEqual(core.events.count, 1)
        XCTAssertEqual(telemetry.messages.count, 1)
        let event = try XCTUnwrap(core.events.first as? ProfileEvent)
        let attachments = try XCTUnwrap(core.metadata.first as? ProfileAttachments)
        XCTAssertEqual(event.additionalAttributes?[RUMCoreContext.IDs.sessionID] as? String, "session-1")
        XCTAssertEqual(event.attachments, ["profile.pprof", "rum-mobile-events.json"])
        XCTAssertEqual(attachments.pprofs.map(\.filename), ["profile.pprof"])
        XCTAssertEqual(try typedRUMEvents(from: attachments).compactMap { $0["id"] as? String }, [vital.id])
    }

    func testWriteMissingContext_doesNotEraseContextCapturedByOtherProfiler() throws {
        writer.write(
            [snapshot(attributes: ["session.id": "session"]), snapshot(filename: "heap.pprof")],
            operation: .continuousProfiling
        )

        let event = try XCTUnwrap(core.events.first as? ProfileEvent)
        XCTAssertEqual(event.additionalAttributes?["session.id"] as? String, "session")
    }

    func testWriteDuplicateFilenamesKeepsFirstSnapshotAndOtherAttachments() throws {
        let task = DurationEvent(id: "heap-task", type: .longTask, start: 20, duration: 30)
        let cpu = snapshot(data: Data([1]), start: 20, end: 60, rumEvents: [], attributes: ["session.id": "session"])
        let duplicate = snapshot(
            data: Data([9]),
            start: 0,
            end: 100,
            rumEvents: [.vital(.mockWith(id: "duplicate-vital", name: "duplicate"))],
            attributes: ["session.id": "other-session", "view.id": ["duplicate-view"]]
        )
        let heap = snapshot(
            filename: "heap.pprof",
            data: Data([2]),
            start: 10,
            end: 70,
            rumEvents: [.longTask(task)],
            attributes: ["session.id": "session", "view.id": ["heap-view"]]
        )

        writer.write([cpu, duplicate, heap], operation: .continuousProfiling)

        XCTAssertEqual(core.events.count, 1)
        XCTAssertEqual(core.metadata.count, 1)
        let event = try XCTUnwrap(core.events.first as? ProfileEvent)
        let attachments = try XCTUnwrap(core.metadata.first as? ProfileAttachments)
        XCTAssertEqual(event.start, heap.start)
        XCTAssertEqual(event.end, heap.end)
        XCTAssertEqual(event.additionalAttributes?["session.id"] as? String, "session")
        XCTAssertEqual(event.additionalAttributes?["view.id"] as? [String], ["heap-view"])
        XCTAssertNil(event.additionalAttributes?[RUMCoreContext.IDs.vitalID])
        XCTAssertEqual(event.attachments, ["profile.pprof", "heap.pprof", "rum-mobile-events.json"])
        XCTAssertEqual(attachments.pprofs.map(\.filename), ["profile.pprof", "heap.pprof"])
        XCTAssertEqual(attachments.pprofs.map(\.data), [cpu.attachment.data, heap.attachment.data])
        XCTAssertEqual(try typedRUMEvents(from: attachments).compactMap { $0["id"] as? String }, [task.id])
    }

    func testWriteCombinedProfilesAboveSizeLimit_writesEachProfileSeparately() throws {
        let halfLimit = Int(ProfilerFeature.Constants.maxObjectSize) / 2
        let vital = Vital.mockWith(id: "cpu-vital", name: "operation")
        let task = DurationEvent(id: "heap-task", type: .longTask, start: 20, duration: 30)
        let cpu = snapshot(data: Data(repeating: 1, count: halfLimit), rumEvents: [.vital(vital)])
        let heap = snapshot(filename: "heap.pprof", data: Data(repeating: 2, count: halfLimit + 1), rumEvents: [.longTask(task)])

        writer.write([cpu, heap], operation: .continuousProfiling)

        let events: [ProfileEvent] = core.events()
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(core.metadata.count, 2)
        XCTAssertEqual(telemetry.messages.count, 2)
        guard events.count == 2, core.metadata.count == 2 else {
            return
        }
        for (index, captured) in [cpu, heap].enumerated() {
            let attachments = try XCTUnwrap(core.metadata[index] as? ProfileAttachments)
            XCTAssertEqual(events[index].attachments, [captured.attachment.filename, "rum-mobile-events.json"])
            XCTAssertEqual(attachments.pprofs.map(\.filename), [captured.attachment.filename])
            XCTAssertEqual(attachments.pprofs.map(\.data), [captured.attachment.data])
            XCTAssertEqual(try typedRUMEvents(from: attachments).compactMap { $0["id"] as? String }, [index == 0 ? vital.id : task.id])
        }
    }

    func testSizeSplitDoesNotGiveUncorrelatedHeapTheCPULongTaskCorrelations() throws {
        let halfLimit = Int(ProfilerFeature.Constants.maxObjectSize) / 2
        let task = DurationEvent(id: "cpu-long-task", type: .longTask, start: 20, duration: 30)
        let cpu = snapshot(
            data: Data(repeating: 1, count: halfLimit),
            rumEvents: [.longTask(task)],
            attributes: [RUMCoreContext.IDs.viewID: ["cpu-view"], "cpu-only": "cpu-value"]
        )
        let heap = snapshot(
            filename: "heap.pprof",
            data: Data(repeating: 2, count: halfLimit + 1),
            rumEvents: [],
            attributes: [RUMCoreContext.IDs.viewID: ["heap-view"], "heap-only": "heap-value"]
        )

        for snapshots in [[cpu, heap], [heap, cpu]] {
            let previousCount = core.events.count
            writer.write(snapshots, operation: .continuousProfiling)

            XCTAssertEqual(core.events.count, previousCount + 1)
            let event = try XCTUnwrap(core.events.last as? ProfileEvent)
            let attachments = try XCTUnwrap(core.metadata.last as? ProfileAttachments)
            XCTAssertEqual(event.attachments, ["profile.pprof", "rum-mobile-events.json"])
            XCTAssertEqual(attachments.pprofs.map(\.filename), ["profile.pprof"])
            XCTAssertEqual(attachments.pprofs.map(\.data), [cpu.attachment.data])
            XCTAssertEqual(event.additionalAttributes?[RUMCoreContext.IDs.viewID] as? [String], ["cpu-view"])
            XCTAssertEqual(event.additionalAttributes?[RUMCoreContext.IDs.longTaskID] as? [String], [task.id])
            XCTAssertEqual(event.additionalAttributes?["cpu-only"] as? String, "cpu-value")
            XCTAssertNil(event.additionalAttributes?["heap-only"])
            XCTAssertEqual(try typedRUMEvents(from: attachments).compactMap { $0["id"] as? String }, [task.id])
        }
    }

    func testWriteOversizedAttachmentDoesNotDiscardOtherProfiles() throws {
        let cpu = snapshot()
        let heap = snapshot(filename: "heap.pprof", data: Data(repeating: 2, count: Int(ProfilerFeature.Constants.maxObjectSize) + 1))

        for snapshots in [[cpu, heap], [heap, cpu]] {
            let previousCount = core.events.count

            writer.write(snapshots, operation: .continuousProfiling)

            XCTAssertEqual(core.events.count, previousCount + 1)
            let event = try XCTUnwrap(core.events.last as? ProfileEvent)
            let attachments = try XCTUnwrap(core.metadata.last as? ProfileAttachments)
            XCTAssertEqual(event.attachments, ["profile.pprof", "rum-mobile-events.json"])
            XCTAssertEqual(attachments.pprofs.map(\.data), [cpu.attachment.data])
        }
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
        XCTAssertNil(metric.attributes[ProfilingDiagnostics.Constants.diagnosticsKey])
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

    func testDeferredWritesKeepMemoryDiagnosticsWithTheirCaptureAndReportProfileTypes() throws {
        let scope = FeatureScopeMock(deferEventWriteContext: true)
        let writer = ProfileWriter(featureScope: scope, telemetryController: .init(telemetry: telemetry))
        var native = dd_memory_profiler_diagnostics_t()
        native.window.recorded_allocations = 11
        var heap = snapshot(filename: "heap.pprof")
        heap.memoryDiagnostics = .init(result: .encoded, diagnostics: native)
        writer.write([snapshot(), heap], operation: .continuousProfiling)

        native.window.recorded_allocations = 22
        heap.memoryDiagnostics = .init(result: .encoded, diagnostics: native)
        writer.write([heap], operation: .continuousProfiling)
        XCTAssertTrue(telemetry.messages.isEmpty)
        scope.flushDeferredEventWriteContexts()

        let metrics = telemetry.messages.compactMap(\.asMetric)
        XCTAssertEqual(metrics.count, 2)
        let sessions = metrics.compactMap { $0.attributes["profiling_session"] as? ProfilingSessionMetric.Attributes }
        XCTAssertEqual(sessions.map(\.profileTypes), [["cpu", "memory"], ["memory"]])
        XCTAssertEqual(sessions.map(\.cycleIndex), [0, 1])
        let diagnostics = metrics.compactMap { $0.attributes["profiling_diagnostics"] as? ProfilingDiagnostics }
        XCTAssertNotNil(diagnostics[0].cpu)
        XCTAssertNil(diagnostics[1].cpu)
        XCTAssertEqual(diagnostics.compactMap { $0.memory?.recordedAllocations }, [11, 22])
        XCTAssertTrue(metrics.allSatisfy { $0.name == "Profiling Session" })
    }

    func testUncorrelatedHeapStillReportsItsDiagnostics() throws {
        var heap = snapshot(filename: "heap.pprof", rumEvents: [])
        heap.memoryDiagnostics = .init(result: .encoded, diagnostics: .init())
        writer.write([heap], operation: .continuousProfiling)

        XCTAssertTrue(core.events.isEmpty)
        let metric = try XCTUnwrap(telemetry.messages.lastMetric(named: "Profiling Session"))
        let session = try XCTUnwrap(metric.attributes["profiling_session"] as? ProfilingSessionMetric.Attributes)
        XCTAssertEqual(session.profileTypes, ["memory"])
        XCTAssertEqual(session.errorMessage, ProfilingSessionMetric.Constants.noProfiledEventsErrorMessage)
        XCTAssertNotNil((metric.attributes["profiling_diagnostics"] as? ProfilingDiagnostics)?.memory)
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
