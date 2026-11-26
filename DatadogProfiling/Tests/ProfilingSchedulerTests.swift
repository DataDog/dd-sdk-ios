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
// swiftlint:disable duplicate_imports
import DatadogMachProfiler
import DatadogMachProfiler.Pprof
import DatadogMachProfiler.Testing
// swiftlint:enable duplicate_imports

final class ProfileSnapshotSchedulingTests: XCTestCase {
    func testManyProvidersWriteOneEventWithAllAttachments() throws {
        let core = PassthroughCoreMock()
        let scheduler = ProfilingScheduler(writer: ProfileWriter(featureScope: core), profilingInterval: 0.1)
        let written = expectation(description: "one combined event")
        core.onEventWriteContext = { _ in written.fulfill() }
        let providers = (0..<8).map { index in
            SnapshotProviderMock(snapshot: snapshot(filename: "profile-\(index).pprof"))
        }

        providers.forEach { scheduler.startPeriodic(for: $0) }
        wait(for: [written], timeout: 3)
        providers.forEach { scheduler.stopPeriodic(for: $0) }

        XCTAssertEqual(core.events.count, 1)
        let attachments = try XCTUnwrap(core.metadata.first as? ProfileAttachments)
        XCTAssertEqual(Set(attachments.pprofs.map(\.filename)), Set((0..<8).map { "profile-\($0).pprof" }))
        XCTAssertTrue(providers.allSatisfy { $0.captureCount == 1 })
    }

    func testDelayedProviderDoesNotOverlapCapturesOrSuppressOtherSnapshots() throws {
        let core = PassthroughCoreMock()
        let scheduler = ProfilingScheduler(writer: ProfileWriter(featureScope: core), profilingInterval: 0.05)
        let captured = expectation(description: "all providers captured")
        captured.expectedFulfillmentCount = 3
        let providers = [
            SnapshotProviderMock(snapshot: snapshot(filename: "profile.pprof"), onCapture: { _ in captured.fulfill() }),
            SnapshotProviderMock(snapshot: snapshot(filename: "heap.pprof"), completesImmediately: false, onCapture: { _ in captured.fulfill() }),
            SnapshotProviderMock(snapshot: nil, onCapture: { _ in captured.fulfill() })
        ]
        let written = expectation(description: "combined event after delayed capture")
        core.onEventWriteContext = { _ in written.fulfill() }
        providers.forEach { scheduler.startPeriodic(for: $0) }
        wait(for: [captured], timeout: 3)

        let skippedTicks = expectation(description: "several ticks skipped while capture is pending")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.16) { skippedTicks.fulfill() }
        wait(for: [skippedTicks], timeout: 3)
        XCTAssertTrue(providers.allSatisfy { $0.captureCount == 1 })
        XCTAssertTrue(core.events.isEmpty)

        providers[1].completeNext()
        wait(for: [written], timeout: 3)
        providers.forEach { scheduler.stopPeriodic(for: $0) }

        XCTAssertEqual(core.events.count, 1)
        let attachments = try XCTUnwrap(core.metadata.first as? ProfileAttachments)
        XCTAssertEqual(Set(attachments.pprofs.map(\.filename)), ["profile.pprof", "heap.pprof"])
        let deadlines = providers.flatMap(\.scheduledTimes)
        XCTAssertEqual(Set(deadlines.map(\.uptimeNanoseconds)).count, 1)
    }

    func testCombinedCapturePreservesCPURUMDataInEitherCompletionOrder() throws {
        for memoryCompletesFirst in [true, false] {
            let core = PassthroughCoreMock()
            let scheduler = ProfilingScheduler(writer: ProfileWriter(featureScope: core), profilingInterval: 0.05)
            let captured = expectation(description: "both providers captured")
            captured.expectedFulfillmentCount = 2
            let written = expectation(description: "one combined event")
            core.onEventWriteContext = { _ in written.fulfill() }
            let vital = Vital.mockWith(id: "cpu-vital", name: "operation")
            let cpu = snapshot(
                filename: "profile.pprof",
                rumEvents: [.vital(vital)],
                attributes: ["session.id": "session", "view.id": ["cpu-view"], "operation.name": "cpu-operation"]
            )
            let heap = snapshot(
                filename: "heap.pprof",
                data: Data([4, 5, 6]),
                rumEvents: [.error(.init(id: "heap-warning", type: .error, start: 20, duration: 0))],
                attributes: ["session.id": "session", "view.id": ["heap-view"]]
            )
            let cpuProvider = SnapshotProviderMock(snapshot: cpu, completesImmediately: false, onCapture: { _ in captured.fulfill() })
            let memoryProvider = SnapshotProviderMock(snapshot: heap, completesImmediately: false, onCapture: { _ in captured.fulfill() })
            let providers = [cpuProvider, memoryProvider]
            providers.forEach { scheduler.startPeriodic(for: $0) }
            wait(for: [captured], timeout: 3)
            providers.forEach { scheduler.stopPeriodic(for: $0) }

            let completionOrder = memoryCompletesFirst ? [memoryProvider, cpuProvider] : providers
            completionOrder.forEach { $0.completeNext() }
            wait(for: [written], timeout: 3)

            XCTAssertEqual(core.events.count, 1)
            let event = try XCTUnwrap(core.events.first as? ProfileEvent)
            let attachments = try XCTUnwrap(core.metadata.first as? ProfileAttachments)
            XCTAssertEqual(event.additionalAttributes?[RUMCoreContext.IDs.vitalID] as? [String], [vital.id])
            XCTAssertEqual(event.additionalAttributes?[RUMCoreContext.IDs.vitalLabel] as? [String], [vital.name])
            XCTAssertEqual(event.additionalAttributes?["view.id"] as? [String], ["cpu-view"])
            XCTAssertEqual(event.additionalAttributes?["operation.name"] as? String, "cpu-operation")
            let events = try XCTUnwrap(JSONSerialization.jsonObject(with: attachments.rumEvents) as? [[String: Any]])
            XCTAssertEqual(events.compactMap { $0["id"] as? String }, [vital.id])
            XCTAssertEqual(Set(attachments.pprofs.map(\.filename)), ["profile.pprof", "heap.pprof"])
            XCTAssertEqual(attachments.pprofs.first { $0.filename == "profile.pprof" }?.data, cpu.attachment.data)
            XCTAssertEqual(attachments.pprofs.first { $0.filename == "heap.pprof" }?.data, heap.attachment.data)
        }
    }

    func testRepeatedStartDoesNotDuplicateSubscriptionOrMoveCadence() {
        let core = PassthroughCoreMock()
        let interval: TimeInterval = 0.2
        let scheduler = ProfilingScheduler(writer: ProfileWriter(featureScope: core), profilingInterval: interval)
        let capturedTwice = expectation(description: "two periodic captures")
        capturedTwice.expectedFulfillmentCount = 2
        let provider = SnapshotProviderMock(snapshot: nil, onCapture: { _ in capturedTwice.fulfill() })
        let start = DispatchTime.now()
        scheduler.startPeriodic(for: provider)
        scheduler.startPeriodic(for: provider)
        let resubscribed = expectation(description: "start called again between ticks")
        DispatchQueue.global().asyncAfter(deadline: .now() + interval / 2) {
            scheduler.startPeriodic(for: provider)
            resubscribed.fulfill()
        }

        wait(for: [resubscribed, capturedTwice], timeout: 3)
        scheduler.stopPeriodic(for: provider)

        let times = provider.scheduledTimes
        XCTAssertEqual(times.count, 2)
        if times.count == 2 {
            XCTAssertEqual(Double(times[0].uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000_000, interval, accuracy: 0.075)
            XCTAssertEqual(Double(times[1].uptimeNanoseconds - times[0].uptimeNanoseconds) / 1_000_000_000, interval, accuracy: 0.001)
        }
    }

    func testStoppingOneProviderKeepsTheOtherSubscription() {
        let core = PassthroughCoreMock()
        let scheduler = ProfilingScheduler(writer: ProfileWriter(featureScope: core), profilingInterval: 0.1)
        let first = expectation(description: "first shared tick")
        let second = expectation(description: "remaining provider next tick")
        let writes = ReadWriteLock<Int>(wrappedValue: 0)
        core.onEventWriteContext = { _ in
            var count = 0
            writes.mutate { $0 += 1; count = $0 }
            if count == 1 { first.fulfill() }
            if count == 2 { second.fulfill() }
        }
        let stoppedProvider = SnapshotProviderMock(snapshot: snapshot(filename: "profile.pprof"))
        let activeProvider = SnapshotProviderMock(snapshot: snapshot(filename: "heap.pprof"))
        scheduler.startPeriodic(for: stoppedProvider)
        scheduler.startPeriodic(for: activeProvider)
        wait(for: [first], timeout: 3)

        scheduler.stopPeriodic(for: stoppedProvider)
        wait(for: [second], timeout: 3)
        scheduler.stopPeriodic(for: activeProvider)
        let cancelledTicks = expectation(description: "last subscription stopped")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.25) { cancelledTicks.fulfill() }
        wait(for: [cancelledTicks], timeout: 3)

        XCTAssertEqual(stoppedProvider.captureCount, 1)
        XCTAssertEqual(activeProvider.captureCount, 2)
        XCTAssertEqual(writes.wrappedValue, 2)
    }

    func testAllNilSnapshotsDoNotWriteAnEvent() {
        let core = PassthroughCoreMock()
        let scheduler = ProfilingScheduler(writer: ProfileWriter(featureScope: core), profilingInterval: 0.1)
        let captured = expectation(description: "empty providers captured")
        captured.expectedFulfillmentCount = 2
        let providers = (0..<2).map { _ in
            SnapshotProviderMock(snapshot: nil, onCapture: { _ in captured.fulfill() })
        }

        providers.forEach { scheduler.startPeriodic(for: $0) }
        wait(for: [captured], timeout: 3)
        providers.forEach { scheduler.stopPeriodic(for: $0) }

        XCTAssertTrue(core.events.isEmpty)
        XCTAssertTrue(core.metadata.isEmpty)
    }

    func testStoppedProviderCanCompleteAnAlreadyRequestedSnapshot() {
        let core = PassthroughCoreMock()
        let scheduler = ProfilingScheduler(writer: ProfileWriter(featureScope: core), profilingInterval: 0.1)
        let captured = expectation(description: "capture requested")
        let written = expectation(description: "in-flight capture written")
        core.onEventWriteContext = { _ in written.fulfill() }
        let provider = SnapshotProviderMock(
            snapshot: snapshot(filename: "heap.pprof"),
            completesImmediately: false,
            onCapture: { _ in captured.fulfill() }
        )
        scheduler.startPeriodic(for: provider)
        wait(for: [captured], timeout: 3)

        scheduler.stopPeriodic(for: provider)
        provider.completeNext()
        wait(for: [written], timeout: 3)

        XCTAssertEqual(core.events.count, 1)
        XCTAssertEqual(provider.captureCount, 1)
    }

    func testSubscriptionsDoNotRetainProviders() {
        let core = PassthroughCoreMock()
        let scheduler = ProfilingScheduler(writer: ProfileWriter(featureScope: core), profilingInterval: 0.05)
        let captured = expectation(description: "capture requested")
        let released = expectation(description: "provider released")
        var provider: SnapshotProviderMock? = SnapshotProviderMock(
            snapshot: nil,
            onCapture: { _ in captured.fulfill() },
            onDeinit: { released.fulfill() }
        )
        weak var weakProvider = provider
        scheduler.startPeriodic(for: provider!)
        wait(for: [captured], timeout: 3)

        provider = nil
        wait(for: [released], timeout: 3)

        XCTAssertNil(weakProvider)
        withExtendedLifetime(scheduler) {}
    }

    func testResubscriptionWaitsForThePreviousCaptureToComplete() {
        let core = PassthroughCoreMock()
        let scheduler = ProfilingScheduler(writer: ProfileWriter(featureScope: core), profilingInterval: 0.05)
        let first = expectation(description: "first capture")
        let second = expectation(description: "capture after resubscription")
        let written = expectation(description: "both completed cycles written")
        written.expectedFulfillmentCount = 2
        core.onEventWriteContext = { _ in written.fulfill() }
        let provider = SnapshotProviderMock(
            snapshot: snapshot(filename: "heap.pprof"),
            completesImmediately: false,
            onCapture: { count in
                if count == 1 { first.fulfill() }
                if count == 2 { second.fulfill() }
            }
        )
        scheduler.startPeriodic(for: provider)
        wait(for: [first], timeout: 3)

        scheduler.stopPeriodic(for: provider)
        scheduler.startPeriodic(for: provider)
        let skippedTicks = expectation(description: "new timer waits for pending capture")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.12) { skippedTicks.fulfill() }
        wait(for: [skippedTicks], timeout: 3)
        XCTAssertEqual(provider.captureCount, 1)

        provider.completeNext()
        wait(for: [second], timeout: 3)
        scheduler.stopPeriodic(for: provider)
        provider.completeNext()
        wait(for: [written], timeout: 3)

        XCTAssertEqual(provider.captureCount, 2)
        XCTAssertEqual(core.events.count, 2)
    }

    private func snapshot(
        filename: String,
        data: Data = Data([1, 2, 3]),
        rumEvents: [RUMEvent] = [.vital(.mockAny())],
        attributes: [AttributeKey: AttributeValue] = [:]
    ) -> ProfileSnapshot {
        ProfileSnapshot(
            start: Date(timeIntervalSince1970: 10),
            end: Date(timeIntervalSince1970: 70),
            attachment: .init(filename: filename, data: data),
            rumEvents: rumEvents,
            attributes: attributes
        )
    }
}

final class ProfilingSchedulerTests: XCTestCase {
    private let cpuQueue = DispatchQueue(label: "test.profiling-scheduler-cpu")
    private let memoryQueue = DispatchQueue(label: "test.profiling-scheduler-memory")

    override func setUp() {
        super.setUp()
        dd_profiler_stop()
        dd_profiler_destroy()
        dd_memory_profiler_configure_for_testing(DD_MEMORY_TEST_HOOKS_SUCCEED)
    }

    override func tearDown() {
        cpuQueue.sync {}
        memoryQueue.sync {}
        dd_profiler_stop()
        dd_profiler_destroy()
        dd_memory_profiler_reset_for_testing()
        super.tearDown()
    }

    func testMemoryJoinsContinuousCPUCadence() throws {
        let interval: TimeInterval = 0.5
        let provider = sampledProvider(continuousSampleRate: 100)
        let core = PassthroughCoreMock(context: context())
        let writer = ProfileWriter(featureScope: core)
        let scheduler = ProfilingScheduler(writer: writer, profilingInterval: interval)
        let firstTick = expectation(description: "first continuous CPU window")
        let sharedTick = expectation(description: "next continuous CPU window")
        let ticks = ReadWriteLock<[TimeInterval]>(wrappedValue: [])
        core.onEventWriteContext = { _ in
            var count = 0
            ticks.mutate { values in
                values.append(ProcessInfo.processInfo.systemUptime)
                count = values.count
            }
            switch count {
            case 1: firstTick.fulfill()
            case 2: sharedTick.fulfill()
            default: break
            }
        }
        let cpu = makeCPU(provider: provider, core: core, scheduler: scheduler)
        startOngoingOperation(on: cpu, core: core)
        wait(for: [firstTick], timeout: 3)

        let halfway = expectation(description: "late memory subscription")
        DispatchQueue.global().asyncAfter(deadline: .now() + interval / 2) { halfway.fulfill() }
        wait(for: [halfway], timeout: 3)
        cpuQueue.sync { addCPUSample() }
        let memory = MemoryProfiler(profilingSamplerProvider: provider, writer: writer, scheduler: scheduler, queue: memoryQueue)
        defer { memory.flushAndStop() }
        _ = memory.receive(message: .context(core.context), from: core)
        memoryQueue.sync {}
        recordMemorySample()

        wait(for: [sharedTick], timeout: 3)
        scheduler.stopPeriodic(for: cpu)
        scheduler.stopPeriodic(for: memory)
        waitForMemoryCaptures(atLeast: 1)
        memoryQueue.sync {}
        let captures = dd_memory_profiler_capture_diagnostics_for_testing()
        XCTAssertEqual(captures.captures_count, 1, "A late subscriber must join the existing CPU tick")
        XCTAssertEqual(captures.alloc_space, 16)
        XCTAssertLessThan(captures.duration_nanos, Int64(interval * 0.8 * 1_000_000_000))
        let times = ticks.wrappedValue
        XCTAssertGreaterThanOrEqual(times.count, 2)
        if times.count >= 2 {
            XCTAssertEqual(times[1] - times[0], interval, accuracy: interval / 3)
        }
        XCTAssertEqual(core.events.count, 2, "The shared tick must write one combined event after the initial CPU-only event")
        XCTAssertEqual(core.metadata.count, 2)
        let events: [ProfileEvent] = core.events()
        let sharedEvent = try XCTUnwrap(events.last)
        let sharedAttachments = try XCTUnwrap(core.metadata.last as? ProfileAttachments)
        let expectedProfiles: Set<String> = [
            ProfileAttachments.Constants.pprofFilename,
            ProfileAttachments.Constants.heapPprofFilename
        ]
        XCTAssertEqual(Set(sharedAttachments.pprofs.map(\.filename)), expectedProfiles)
        XCTAssertTrue(sharedAttachments.pprofs.allSatisfy { !$0.data.isEmpty })
        XCTAssertTrue(expectedProfiles.isSubset(of: Set(sharedEvent.attachments)))
        let rum = try XCTUnwrap(core.context.additionalContext(ofType: RUMCoreContext.self))
        XCTAssertEqual(sharedEvent.additionalAttributes?[RUMCoreContext.IDs.applicationID] as? String, rum.applicationID)
        XCTAssertEqual(sharedEvent.additionalAttributes?[RUMCoreContext.IDs.sessionID] as? String, rum.sessionID)
        XCTAssertTrue(sharedEvent.tags.contains("operation:continuous"))
        withExtendedLifetime(cpu) {}
    }

    func testShortCPUWindowDoesNotDelayMemoryCaptures() throws {
        let provider = sampledProvider(continuousSampleRate: 100)
        let core = PassthroughCoreMock(context: context())
        let writer = ProfileWriter(featureScope: core)
        let scheduler = ProfilingScheduler(writer: writer, profilingInterval: 0.1)
        let memory = MemoryProfiler(profilingSamplerProvider: provider, writer: writer, scheduler: scheduler, queue: memoryQueue)
        let cpu = makeCPU(provider: provider, core: core, scheduler: scheduler, minProfileDuration: 1)
        defer {
            scheduler.stopPeriodic(for: cpu)
            scheduler.stopPeriodic(for: memory)
            core.onEventWriteContext = nil
            memory.flushAndStop()
        }
        let vital = Vital.mockWith(id: "completed-cpu-vital", stepType: nil, date: Date())
        _ = cpu.receive(message: .payload(OperationMessage(attributes: [:], operation: vital)), from: core)
        cpuQueue.sync { addCPUSample() }
        _ = memory.receive(message: .context(core.context), from: core)
        memoryQueue.sync {}

        func recordHeapWindow() {
            recordMemorySample()
            let warning = DurationEvent(
                id: UUID().uuidString,
                type: .error,
                start: Date().timeIntervalSince1970.dd.toInt64Nanoseconds,
                duration: 0
            )
            _ = memory.receive(message: .payload(MemoryWarningMessage(attributes: [:], warning: warning)), from: core)
        }

        let heapOnly = expectation(description: "heap captured before the CPU minimum duration")
        let cpuCapture = expectation(description: "CPU window captured once its minimum duration is reached")
        core.onEventWriteContext = { _ in
            guard let attachments = core.metadata.last as? ProfileAttachments else {
                return XCTFail("Missing profile attachments")
            }
            if attachments.pprofs.contains(where: { $0.filename == ProfileAttachments.Constants.pprofFilename }) {
                scheduler.stopPeriodic(for: cpu)
                scheduler.stopPeriodic(for: memory)
                cpuCapture.fulfill()
            } else {
                XCTAssertEqual(attachments.pprofs.map(\.filename), [ProfileAttachments.Constants.heapPprofFilename])
                if core.events.count == 1 {
                    self.cpuQueue.sync {
                        XCTAssertTrue(dd_profiler_is_running())
                        XCTAssertGreaterThan(dd_pprof_sample_count(dd_profiler_get_profile()), 0)
                    }
                    heapOnly.fulfill()
                }
                recordHeapWindow()
            }
        }
        recordHeapWindow()

        wait(for: [heapOnly, cpuCapture], timeout: 3, enforceOrder: true)

        let attachments = try XCTUnwrap(core.metadata.last as? ProfileAttachments)
        XCTAssertEqual(attachments.pprofs.map(\.filename), ["profile.pprof"])
        XCTAssertTrue(attachments.pprofs.allSatisfy { !$0.data.isEmpty })
        let event = try XCTUnwrap(core.events.last as? ProfileEvent)
        XCTAssertEqual(event.additionalAttributes?[RUMCoreContext.IDs.vitalID] as? [String], [vital.id])
    }

    func testDisabledCPUDoesNotDisableMemoryCadence() throws {
        try assertMemoryKeepsCapturing(continuousSampleRate: 0, rejectCPUQuota: false)
    }

    func testCPULongTasksMakeCombinedPeriodicProfilesUploadable() throws {
        let provider = sampledProvider(continuousSampleRate: 100)
        let core = PassthroughCoreMock(context: context())
        let writer = ProfileWriter(featureScope: core)
        let scheduler = ProfilingScheduler(writer: writer, profilingInterval: 0.1)
        let cpu = makeCPU(provider: provider, core: core, scheduler: scheduler)
        let memory = MemoryProfiler(profilingSamplerProvider: provider, writer: writer, scheduler: scheduler, queue: memoryQueue)
        defer {
            scheduler.stopPeriodic(for: cpu)
            scheduler.stopPeriodic(for: memory)
            core.onEventWriteContext = nil
            memory.flushAndStop()
        }
        _ = memory.receive(message: .context(core.context), from: core)
        memoryQueue.sync {}

        func recordWindow(_ index: Int) {
            var sample = dd_memory_live_sample_t()
            sample.address = UnsafeRawPointer(bitPattern: 0x10000 + index * 0x10000)
            sample.size = 16
            sample.weight = 1
            dd_memory_profiler_record_for_testing(&sample)
            cpuQueue.sync { addCPUSample() }
            let task = DurationEvent(
                id: "cpu-periodic-task-\(index)",
                type: .longTask,
                start: Date().addingTimeInterval(core.context.serverTimeOffset - 1).timeIntervalSince1970.dd.toInt64Nanoseconds,
                duration: 1_000_000_000
            )
            let message = LongTaskMessage(
                attributes: [RUMCoreContext.IDs.viewID: ["cpu-view"], RUMCoreContext.IDs.viewName: ["CPU View"]],
                longTask: task
            )
            _ = cpu.receive(message: .payload(message), from: core)
            XCTAssertFalse(memory.receive(message: .payload(message), from: core))
            cpuQueue.sync {}
        }

        let uploaded = expectation(description: "CPU long tasks correlate two combined periodic uploads")
        uploaded.expectedFulfillmentCount = 2
        uploaded.assertForOverFulfill = true
        core.onEventWriteContext = { _ in
            if core.events.count == 1 {
                recordWindow(1)
            } else {
                scheduler.stopPeriodic(for: cpu)
                scheduler.stopPeriodic(for: memory)
            }
            uploaded.fulfill()
        }
        recordWindow(0)
        wait(for: [uploaded], timeout: 3)
        memoryQueue.sync {}

        let events: [ProfileEvent] = core.events()
        XCTAssertEqual(events.count, 2)
        XCTAssertTrue(events.allSatisfy { $0.tags.contains("operation:continuous") })
        for (index, metadata) in core.metadata.enumerated() {
            let attachments = try XCTUnwrap(metadata as? ProfileAttachments)
            XCTAssertEqual(Set(attachments.pprofs.map(\.filename)), ["profile.pprof", "heap.pprof"])
            let correlations = try XCTUnwrap(JSONSerialization.jsonObject(with: attachments.rumEvents) as? [[String: Any]])
            XCTAssertEqual(correlations.compactMap { $0["id"] as? String }, ["cpu-periodic-task-\(index)"])
            XCTAssertEqual(events[index].additionalAttributes?[RUMCoreContext.IDs.viewID] as? [String], ["cpu-view"])
            XCTAssertEqual(events[index].additionalAttributes?[RUMCoreContext.IDs.longTaskID] as? [String], ["cpu-periodic-task-\(index)"])
        }
        withExtendedLifetime(cpu) {}
    }

    func testCPUQuotaRejectionDoesNotDisableMemoryCadence() throws {
        try assertMemoryKeepsCapturing(continuousSampleRate: 100, rejectCPUQuota: true)
    }

    func testCustomCPUCompletionDoesNotCutOrResetMemoryWindow() {
        let interval: TimeInterval = 0.5
        let provider = sampledProvider(continuousSampleRate: 0)
        let core = PassthroughCoreMock(context: context())
        let writer = ProfileWriter(featureScope: core)
        let scheduler = ProfilingScheduler(writer: writer, profilingInterval: interval)
        let memory = MemoryProfiler(profilingSamplerProvider: provider, writer: writer, scheduler: scheduler, queue: memoryQueue)
        defer { memory.flushAndStop() }
        _ = memory.receive(message: .context(core.context), from: core)
        memoryQueue.sync {}
        recordMemorySample()
        let origin = dd_memory_profiler_window_start_time_nanos()
        let cpu = makeCPU(provider: provider, core: core, scheduler: scheduler)
        let completed = expectation(description: "custom CPU profile completed")
        core.onEventWriteContext = { _ in completed.fulfill() }
        let start = Vital.mockWith(stepType: .start, date: Date())
        dd_profiler_start_testing(100, false, Int64.max, 0)
        _ = cpu.receive(message: .payload(OperationMessage(attributes: [:], operation: start)), from: core)
        cpuQueue.sync {}
        addCPUSample()
        let end = Vital.mockWith(name: start.name, operationKey: start.operationKey, stepType: .end)

        _ = cpu.receive(message: .payload(OperationMessage(attributes: [:], operation: end)), from: core)
        wait(for: [completed], timeout: 3)
        core.onEventWriteContext = nil
        memoryQueue.sync {}
        XCTAssertEqual(dd_memory_profiler_capture_diagnostics_for_testing().captures_count, 0)
        XCTAssertEqual(dd_memory_profiler_window_start_time_nanos(), origin)

        waitForMemoryCaptures(atLeast: 1)
        let captured = dd_memory_profiler_capture_diagnostics_for_testing()
        XCTAssertEqual(captured.time_nanos, origin)
        XCTAssertGreaterThanOrEqual(captured.duration_nanos, Int64(interval * 0.8 * 1_000_000_000))
        XCTAssertEqual(captured.inuse_space, 16)
        withExtendedLifetime(cpu) {}
    }

    func testMissingMemoryRUMKeepsRecordingWithoutStoppingCPUCadence() throws {
        let provider = sampledProvider(continuousSampleRate: 100)
        let core = PassthroughCoreMock(context: context())
        let writer = ProfileWriter(featureScope: core)
        let scheduler = ProfilingScheduler(writer: writer, profilingInterval: 0.1)
        let capturedCPU = expectation(description: "continuous CPU captures while memory awaits RUM")
        core.onEventWriteContext = { _ in capturedCPU.fulfill() }
        let cpu = makeCPU(provider: provider, core: core, scheduler: scheduler)
        startOngoingOperation(on: cpu, core: core)
        let suiteName = "ProfilingSchedulerTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set(100, forKey: DD_PROFILING_MEMORY_SAMPLE_RATE_KEY)
        dd_memory_profiler_auto_start_for_testing(suiteName, false, false)
        defaults.removePersistentDomain(forName: suiteName)
        XCTAssertTrue(dd_memory_profiler_is_running())
        let memory = MemoryProfiler(
            profilingSamplerProvider: provider,
            writer: writer,
            scheduler: scheduler,
            queue: memoryQueue,
            dateProvider: DateProviderMock(now: Date().addingTimeInterval(61))
        )
        defer { memory.flushAndStop() }
        recordMemorySample()
        let origin = dd_memory_profiler_window_start_time_nanos()

        wait(for: [capturedCPU], timeout: 3)
        core.onEventWriteContext = nil
        memoryQueue.sync {
            XCTAssertEqual(memory.state, .waiting)
        }
        XCTAssertTrue(dd_profiler_is_running())
        XCTAssertTrue(dd_memory_profiler_is_running())
        XCTAssertEqual(dd_memory_profiler_window_start_time_nanos(), origin)
        XCTAssertEqual(dd_memory_profiler_capture_diagnostics_for_testing().captures_count, 0)
        let attachments = try XCTUnwrap(core.metadata.first as? ProfileAttachments)
        XCTAssertEqual(attachments.pprofs.map(\.filename), [ProfileAttachments.Constants.pprofFilename])
        withExtendedLifetime(cpu) {}
    }
}

private extension ProfilingSchedulerTests {
    func sampledProvider(continuousSampleRate: SampleRate) -> ProfilingSamplerProvider {
        let provider = ProfilingSamplerProvider(continuousSampleRate: continuousSampleRate, memorySampleRate: 100)
        provider.updateWith(deterministicSampler: DeterministicSampler(seed: 1, samplingRate: 100))
        return provider
    }

    func context() -> DatadogContext {
        .mockWith(
            applicationStateHistory: .mockAppInForeground(),
            additionalContext: [RUMCoreContext.mockWith(sessionSampleRate: 100)]
        )
    }

    func makeCPU(
        provider: ProfilingSamplerProvider,
        core: PassthroughCoreMock,
        scheduler: ProfilingScheduler,
        quotaChecker: ProfilingQuotaCheckerMock = .init(),
        minProfileDuration: TimeInterval = 0
    ) -> DatadogProfiler {
        dd_profiler_start_testing(100, false, Int64.max, 0)
        let cpu = DatadogProfiler(
            core: core,
            profilingSamplerProvider: provider,
            quotaChecker: quotaChecker,
            writer: ProfileWriter(featureScope: core),
            scheduler: scheduler,
            queue: cpuQueue,
            minProfileDuration: minProfileDuration
        )
        _ = cpu.receive(message: .context(core.context), from: core)
        cpuQueue.sync {}
        return cpu
    }

    func startOngoingOperation(on cpu: DatadogProfiler, core: PassthroughCoreMock) {
        let operation = Vital.mockWith(stepType: .start, date: Date())
        _ = cpu.receive(message: .payload(OperationMessage(attributes: [:], operation: operation)), from: core)
        cpuQueue.sync {}
        addCPUSample()
    }

    func addCPUSample() {
        dd_profiler_stop()
        var trace = stack_trace_t.mockWith(
            tid: 1,
            addresses: [0x100001000],
            timestamp: DispatchTime.now().uptimeNanoseconds
        )
        dd_pprof_add_samples(dd_profiler_get_profile(), &trace, 1)
        XCTAssertEqual(dd_profiler_start(), 1)
    }

    func recordMemorySample() {
        var sample = dd_memory_live_sample_t()
        sample.address = UnsafeRawPointer(bitPattern: 0x10000)
        sample.size = 16
        sample.weight = 1
        dd_memory_profiler_record_for_testing(&sample)
    }

    func waitForMemoryCaptures(atLeast count: UInt64) {
        let captured = expectation(description: "shared memory capture")
        wait(until: {
            dd_memory_profiler_capture_diagnostics_for_testing().captures_count >= count
        }, andThenFulfill: captured)
        wait(for: [captured], timeout: 3)
    }

    func assertMemoryKeepsCapturing(continuousSampleRate: SampleRate, rejectCPUQuota: Bool) throws {
        let provider = sampledProvider(continuousSampleRate: continuousSampleRate)
        let core = PassthroughCoreMock(context: context())
        let writer = ProfileWriter(featureScope: core)
        let scheduler = ProfilingScheduler(writer: writer, profilingInterval: 0.05)
        let quota = ProfilingQuotaCheckerMock()
        if rejectCPUQuota {
            quota.quotaResult = .init(decision: .quotaKO, reason: .quotaExceeded)
        }
        let cpu = makeCPU(provider: provider, core: core, scheduler: scheduler, quotaChecker: quota)
        let memory = MemoryProfiler(profilingSamplerProvider: provider, writer: writer, scheduler: scheduler, queue: memoryQueue)
        defer { memory.flushAndStop() }
        _ = memory.receive(message: .context(core.context), from: core)
        memoryQueue.sync {}
        recordMemorySample()
        let task = DurationEvent(id: "memory-task", type: .longTask, start: Date().timeIntervalSince1970.dd.toInt64Nanoseconds, duration: 0)
        _ = memory.receive(message: .payload(LongTaskMessage(attributes: [:], longTask: task)), from: core)

        waitForMemoryCaptures(atLeast: 2)

        XCTAssertFalse(dd_profiler_is_running())
        XCTAssertTrue(dd_memory_profiler_is_running())
        memoryQueue.sync {
            XCTAssertEqual(memory.state, .running)
        }
        XCTAssertGreaterThanOrEqual(dd_memory_profiler_capture_diagnostics_for_testing().captures_count, 2)
        XCTAssertTrue(core.events.isEmpty)
        XCTAssertTrue(core.metadata.isEmpty)
        withExtendedLifetime(cpu) {}
    }
}

private final class SnapshotProviderMock: ProfileSnapshotProvider, @unchecked Sendable {
    private struct State {
        var scheduledTimes: [DispatchTime] = []
        var completions: [@Sendable (ProfileSnapshot?) -> Void] = []
    }

    private let state = ReadWriteLock<State>(wrappedValue: State())
    private let snapshot: ProfileSnapshot?
    private let completesImmediately: Bool
    private let onCapture: @Sendable (Int) -> Void
    private let onDeinit: @Sendable () -> Void

    var captureCount: Int { state.wrappedValue.scheduledTimes.count }
    var scheduledTimes: [DispatchTime] { state.wrappedValue.scheduledTimes }

    init(
        snapshot: ProfileSnapshot?,
        completesImmediately: Bool = true,
        onCapture: @escaping @Sendable (Int) -> Void = { _ in },
        onDeinit: @escaping @Sendable () -> Void = {}
    ) {
        self.snapshot = snapshot
        self.completesImmediately = completesImmediately
        self.onCapture = onCapture
        self.onDeinit = onDeinit
    }

    deinit {
        onDeinit()
    }

    func captureSnapshot(scheduledFor time: DispatchTime, completion: @escaping @Sendable (ProfileSnapshot?) -> Void) {
        var count = 0
        state.mutate {
            $0.scheduledTimes.append(time)
            count = $0.scheduledTimes.count
            if !completesImmediately {
                $0.completions.append(completion)
            }
        }
        onCapture(count)
        if completesImmediately {
            completion(snapshot)
        }
    }

    func completeNext() {
        var completion: (@Sendable (ProfileSnapshot?) -> Void)?
        state.mutate {
            if !$0.completions.isEmpty {
                completion = $0.completions.removeFirst()
            }
        }
        completion?(snapshot)
    }
}

#endif
