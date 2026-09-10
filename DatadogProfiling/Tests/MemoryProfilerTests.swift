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
// swiftlint:disable duplicate_imports
import DatadogMachProfiler
import DatadogMachProfiler.Testing
// swiftlint:enable duplicate_imports

/// Tests event-triggered heap snapshots: a TTID, app hang or RUM memory warning captures a heap
/// profile at the moment it happened, instead of waiting for the next periodic window boundary.
///
/// Two properties matter beyond "a profile came out":
/// - **Isolation.** A trigger only ever adds a heap event. It never starts, stops or reschedules
///   the CPU profiler or the periodic timer, both of which `DatadogProfiler` alone owns.
/// - **Throttling.** Hangs and memory warnings arrive in bursts, so emissions are spaced by
///   `MemoryProfiler.Constants.minHeapEmissionInterval`. A trigger inside that window is folded:
///   its correlation is already recorded, so it still reaches the product on the next emission.
///
/// The swizzle, the Swift rebinding, and the passive sampler are process-global singletons. Every
/// test stops them in `tearDown` so state never leaks into the rest of the suite.

/// Pure-Swift class (allocated via swift_allocObject, not +allocWithZone:).
private final class TriggerSwiftFixture { var payload = (0, 0, 0, 0) }

final class MemoryProfilerTests: XCTestCase {
    private var core: PassthroughCoreMock! // swiftlint:disable:this implicitly_unwrapped_optional
    private let profilerQueue = DispatchQueue(label: "test.profiler.memory.triggers")

    override func setUp() {
        super.setUp()
        // Start with a background context so the CPU profiler doesn't auto-start at init. Memory
        // records in the background, so tests that need it off must use a terminal reason
        // (unconfigured, consent revoked, quota) rather than app state.
        core = PassthroughCoreMock(context: .mockWith(applicationStateHistory: .mockAppInBackground()))
        dd_profiler_stop()
        dd_profiler_destroy()
        ObjCAllocInterception.stop()
        SwiftAllocInterception.stop()
        dd_memory_test_reset()
    }

    override func tearDown() {
        ObjCAllocInterception.stop()
        SwiftAllocInterception.stop()
        dd_memory_test_reset()
        dd_profiler_stop()
        dd_profiler_destroy()
        dd_delete_profiling_defaults()
        core = nil
        super.tearDown()
    }

    // MARK: - App hang

    func testAppHang_emitsHeapSnapshotImmediately() throws {
        let dateProvider = DateProviderMock()
        let profiler = makeForegroundHeapOnlyProfiler(dateProvider: dateProvider)

        try withSampledObject {
            sendHang(id: "hang-1", to: profiler)

            XCTAssertEqual(heapAttachmentCount, 1, "An app hang must emit its own heap snapshot")
            let event = try XCTUnwrap(core.events.first as? ProfileEvent)
            XCTAssertTrue(event.tags.contains("trigger:app_hang"))
            XCTAssertEqual(event.additionalAttributes?[RUMCoreContext.IDs.errorID] as? [String], ["hang-1"])

            let metadata = try XCTUnwrap(core.metadata.first as? ProfileAttachments)
            XCTAssertNil(metadata.pprof, "An event-triggered snapshot is heap-only")
            XCTAssertNotNil(metadata.heapPprof)
        }
        withExtendedLifetime(profiler) {}
    }

    func testAppHangBurst_emitsOnce_andFoldsTheRestIntoTheNextEmission() throws {
        let dateProvider = DateProviderMock()
        let profiler = makeForegroundHeapOnlyProfiler(dateProvider: dateProvider)

        try withSampledObject {
            for id in ["hang-1", "hang-2", "hang-3"] {
                sendHang(id: id, to: profiler)
                dateProvider.now.addTimeInterval(1) // all three inside the cooldown
            }

            XCTAssertEqual(heapAttachmentCount, 1, "A burst inside the cooldown emits exactly one snapshot")

            // The folded hangs are not lost: they ride the next emission.
            dateProvider.now.addTimeInterval(10)
            enterBackground(at: dateProvider.now)

            XCTAssertEqual(heapAttachmentCount, 2)
            let second = try XCTUnwrap(core.events.last as? ProfileEvent)
            XCTAssertEqual(
                second.additionalAttributes?[RUMCoreContext.IDs.errorID] as? [String],
                ["hang-2", "hang-3"],
                "Hangs folded by the cooldown correlate on the next emission"
            )
        }
        withExtendedLifetime(profiler) {}
    }

    func testAppHangAfterCooldown_emitsAgain() throws {
        let dateProvider = DateProviderMock()
        let profiler = makeForegroundHeapOnlyProfiler(dateProvider: dateProvider)

        try withSampledObject {
            sendHang(id: "hang-1", to: profiler)
            dateProvider.now.addTimeInterval(MemoryProfiler.Constants.minHeapEmissionInterval + 1)
            sendHang(id: "hang-2", to: profiler)

            XCTAssertEqual(heapAttachmentCount, 2, "A hang past the cooldown gets its own snapshot")
        }
        withExtendedLifetime(profiler) {}
    }

    func testAppHang_isIgnored_whenMemoryProfilingIsNotConfigured() throws {
        let provider = makeSamplerProvider(continuousSampleRate: 0, memorySampleRate: 0)
        let profiler = makeProfiler(profilingSamplerProvider: provider)
        connectMessageReceiver(to: profiler, profilingSamplerProvider: provider)
        enterForeground()

        sendHang(id: "hang-1", to: profiler)

        XCTAssertEqual(heapAttachmentCount, 0)
        withExtendedLifetime(profiler) {}
    }

    // MARK: - TTID

    /// No standalone launch harvest runs here (app-launch profiling off), so TTID must produce the
    /// launch dot itself — otherwise a memory-heavy start goes unexplained whenever CPU profiling
    /// is not the one harvesting it.
    func testTTID_emitsHeapSnapshot_whenNoLaunchProfileIsHarvested() throws {
        let dateProvider = DateProviderMock()
        let profiler = makeForegroundHeapOnlyProfiler(dateProvider: dateProvider)

        try withSampledObject {
            sendTTID(to: profiler, at: dateProvider.now)

            XCTAssertEqual(heapAttachmentCount, 1)
            let event = try XCTUnwrap(core.events.first as? ProfileEvent)
            XCTAssertTrue(event.tags.contains("trigger:ttid"))

            let metadata = try XCTUnwrap(core.metadata.first as? ProfileAttachments)
            XCTAssertNil(metadata.pprof, "With no launch harvest the TTID dot is heap-only")
            XCTAssertNotNil(metadata.heapPprof)
        }
        withExtendedLifetime(profiler) {}
    }

    /// The launch harvest already attached the heap to the app-launch profile. That attachment IS
    /// the TTID snapshot, so the trigger must fold rather than upload the same live set twice.
    func testTTID_foldsIntoTheAppLaunchProfile_whenOneIsHarvested() throws {
        let dateProvider = DateProviderMock()
        let provider = makeSamplerProvider(continuousSampleRate: 0, memorySampleRate: .maxSampleRate)
        let profiler = makeProfiler(
            profilingSamplerProvider: provider,
            dateProvider: dateProvider,
            isAppLaunchProfilingEnabled: true
        )
        connectMessageReceiver(to: profiler, profilingSamplerProvider: provider)
        enterForeground()
        XCTAssertTrue(dd_memory_profiler_is_running(), "Precondition: memory must be recording")
        XCTAssertEqual(dd_profiler_start(), 1, "Precondition: a CPU profile must exist to harvest")

        try withSampledObject {
            sendTTID(to: profiler, at: dateProvider.now)

            XCTAssertEqual(heapAttachmentCount, 1, "Exactly one heap upload for the launch window")
            let metadata = try XCTUnwrap(core.metadata.first as? ProfileAttachments)
            XCTAssertNotNil(metadata.pprof, "The launch heap rides the app-launch CPU profile")
            XCTAssertNotNil(metadata.heapPprof)

            let event = try XCTUnwrap(core.events.first as? ProfileEvent)
            XCTAssertTrue(event.tags.contains("operation:launch"))
            XCTAssertFalse(
                event.tags.contains("trigger:"),
                "A coupled launch profile is not tagged as event-triggered"
            )
        }
        withExtendedLifetime(profiler) {}
    }

    // MARK: - Memory warning

    /// The case the RFC cares about most: the OS reported pressure, and memory profiling explains
    /// it — whether or not this session sampled CPU profiling in.
    func testMemoryWarning_emitsHeapSnapshot_evenWithContinuousCPUSampledOut() throws {
        let dateProvider = DateProviderMock()
        let profiler = makeForegroundHeapOnlyProfiler(dateProvider: dateProvider)
        XCTAssertNotEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_RUNNING, "Precondition: CPU profiler off")

        try withSampledObject {
            sendMemoryWarning(id: "warning-1", to: profiler)

            XCTAssertEqual(heapAttachmentCount, 1)
            let event = try XCTUnwrap(core.events.first as? ProfileEvent)
            XCTAssertTrue(event.tags.contains("trigger:memory_warning"))
            XCTAssertEqual(event.additionalAttributes?[RUMCoreContext.IDs.errorID] as? [String], ["warning-1"])

            let metadata = try XCTUnwrap(core.metadata.first as? ProfileAttachments)
            XCTAssertNil(metadata.pprof)
            XCTAssertNotNil(metadata.heapPprof)
        }
        withExtendedLifetime(profiler) {}
    }

    func testMemoryWarning_isIgnored_whenMemoryProfilingIsNotConfigured() throws {
        let provider = makeSamplerProvider(continuousSampleRate: 0, memorySampleRate: 0)
        let profiler = makeProfiler(profilingSamplerProvider: provider)
        connectMessageReceiver(to: profiler, profilingSamplerProvider: provider)
        enterForeground()

        sendMemoryWarning(id: "warning-1", to: profiler)

        XCTAssertEqual(heapAttachmentCount, 0)
        withExtendedLifetime(profiler) {}
    }

    /// A warning and a hang inside the same cooldown produce one upload carrying both, not two.
    func testMemoryWarningAndHang_inSameCooldown_shareOneSnapshot() throws {
        let dateProvider = DateProviderMock()
        let profiler = makeForegroundHeapOnlyProfiler(dateProvider: dateProvider)

        try withSampledObject {
            sendHang(id: "hang-1", to: profiler)
            dateProvider.now.addTimeInterval(1)
            sendMemoryWarning(id: "warning-1", to: profiler)

            XCTAssertEqual(heapAttachmentCount, 1)

            dateProvider.now.addTimeInterval(10)
            enterBackground(at: dateProvider.now)

            let second = try XCTUnwrap(core.events.last as? ProfileEvent)
            XCTAssertEqual(
                second.additionalAttributes?[RUMCoreContext.IDs.errorID] as? [String],
                ["warning-1"],
                "The folded warning correlates on the next emission"
            )
        }
        withExtendedLifetime(profiler) {}
    }

    // MARK: - Isolation and cadence invariants

    /// The isolation invariant this whole design rests on: a memory trigger may only ever *add* a
    /// heap event. It must never start, stop or reschedule the CPU profiler, which
    /// `DatadogProfiler` alone owns.
    func testTriggers_neverTouchTheCPUProfiler() throws {
        let dateProvider = DateProviderMock()
        let provider = makeSamplerProvider(continuousSampleRate: .maxSampleRate, memorySampleRate: .maxSampleRate)
        let profiler = makeProfiler(profilingSamplerProvider: provider, dateProvider: dateProvider)
        connectMessageReceiver(to: profiler, profilingSamplerProvider: provider)
        enterForeground()

        let statusBefore = dd_profiler_get_status()

        try withSampledObject {
            sendHang(id: "hang-1", to: profiler)
            dateProvider.now.addTimeInterval(MemoryProfiler.Constants.minHeapEmissionInterval + 1)
            sendMemoryWarning(id: "warning-1", to: profiler)
            dateProvider.now.addTimeInterval(MemoryProfiler.Constants.minHeapEmissionInterval + 1)
            sendTTID(to: profiler, at: dateProvider.now)
        }

        XCTAssertEqual(
            dd_profiler_get_status(),
            statusBefore,
            "A memory trigger must not change CPU profiler state"
        )
        withExtendedLifetime(profiler) {}
    }

    /// A periodic emission stamps the cooldown, so a trigger arriving right behind it folds instead
    /// of re-uploading a live set that was just reported.
    func testTriggerImmediatelyAfterPeriodicEmission_isFolded() throws {
        let dateProvider = DateProviderMock()
        let profiler = makeForegroundHeapOnlyProfiler(dateProvider: dateProvider)

        try withSampledObject {
            // Close a window the periodic way (a background transition flushes it).
            enterBackground(at: dateProvider.now)
            XCTAssertEqual(heapAttachmentCount, 1, "Precondition: the periodic window emitted")

            enterForeground()
            dateProvider.now.addTimeInterval(1) // inside the cooldown
            sendHang(id: "hang-1", to: profiler)

            XCTAssertEqual(
                heapAttachmentCount,
                1,
                "The trigger folds into the periodic emission that just happened"
            )
        }
        withExtendedLifetime(profiler) {}
    }

    /// Recording continues in the background, but uploading must not: the conditions latch allows
    /// exactly one emission once conditions are lost, and triggers are bound by it too.
    func testTriggerWhileBackgrounded_doesNotReEmitTheLiveSet() throws {
        let dateProvider = DateProviderMock()
        let profiler = makeForegroundHeapOnlyProfiler(dateProvider: dateProvider)

        try withSampledObject {
            enterBackground(at: dateProvider.now) // spends the one allowed emission
            let afterBackground = heapAttachmentCount

            dateProvider.now.addTimeInterval(30) // well past the cooldown
            sendHang(id: "hang-1", to: profiler)

            XCTAssertEqual(
                heapAttachmentCount,
                afterBackground,
                "No re-upload of the same live set while backgrounded"
            )
        }
        withExtendedLifetime(profiler) {}
    }

    /// Long tasks stay correlation-only. They are frequent and rarely say anything about the heap,
    /// so they enrich the next emission rather than forcing one.
    func testLongTask_doesNotTriggerASnapshot() throws {
        let dateProvider = DateProviderMock()
        let profiler = makeForegroundHeapOnlyProfiler(dateProvider: dateProvider)

        try withSampledObject {
            _ = profiler.receive(
                message: .payload(LongTaskMessage(
                    attributes: mockRandomAttributes(),
                    longTask: DurationEvent(id: "long-task-1", type: .longTask, start: 0, duration: 100)
                )),
                from: core
            )
            flushQueue()

            XCTAssertEqual(heapAttachmentCount, 0, "A long task must not force a heap emission")

            // It still correlates on the next emission.
            dateProvider.now.addTimeInterval(10)
            enterBackground(at: dateProvider.now)

            let event = try XCTUnwrap(core.events.last as? ProfileEvent)
            XCTAssertEqual(
                event.additionalAttributes?[RUMCoreContext.IDs.longTaskID] as? [String],
                ["long-task-1"]
            )
        }
        withExtendedLifetime(profiler) {}
    }

    // MARK: - Helpers

    private func makeSamplerProvider(
        continuousSampleRate: SampleRate = .maxSampleRate,
        memorySampleRate: SampleRate = 0
    ) -> ProfilingSamplerProvider {
        ProfilingSamplerProvider(continuousSampleRate: continuousSampleRate, memorySampleRate: memorySampleRate)
    }

    private func makeProfiler(
        profilingSamplerProvider: ProfilingSamplerProvider,
        quotaChecker: ProfilingQuotaChecking = ProfilingQuotaCheckerMock(),
        dateProvider: DateProvider = DateProviderMock(),
        isAppLaunchProfilingEnabled: Bool = false
    ) -> DatadogProfiler {
        DatadogProfiler(
            core: core,
            profilingSamplerProvider: profilingSamplerProvider,
            quotaChecker: quotaChecker,
            queue: profilerQueue,
            profilingInterval: .infinity,
            isAppLaunchProfilingEnabled: isAppLaunchProfilingEnabled,
            dateProvider: dateProvider
        )
    }

    /// A heap-only profiler — continuous CPU sampled out, memory sampled in — connected to the core
    /// and brought to the foreground, so triggers land on a live memory window.
    private func makeForegroundHeapOnlyProfiler(dateProvider: DateProviderMock) -> DatadogProfiler {
        let provider = makeSamplerProvider(continuousSampleRate: 0, memorySampleRate: .maxSampleRate)
        let profiler = makeProfiler(profilingSamplerProvider: provider, dateProvider: dateProvider)
        connectMessageReceiver(to: profiler, profilingSamplerProvider: provider)
        enterForeground()
        XCTAssertTrue(dd_memory_profiler_is_running(), "Precondition: memory must record in the foreground")
        return profiler
    }

    private func enterForeground() {
        core.context = .mockWith(applicationStateHistory: .mockAppInForeground())
        flushQueue()
    }

    private func enterBackground(at date: Date) {
        core.context = .mockWith(applicationStateHistory: .mockWith(
            initialState: .active,
            date: date.addingTimeInterval(-1),
            transitions: [(state: .background, date: date)]
        ))
        flushQueue()
    }

    /// Forces the next allocation to be sampled and keeps that object alive for the duration of
    /// `body`, so it stays in the live set while the assertions run.
    private func withSampledObject(_ body: () throws -> Void) rethrows {
        dd_memory_test_force_next_sample()
        let object = TriggerSwiftFixture()
        try withExtendedLifetime(object) { try body() }
    }

    /// Number of emitted profiles carrying a `heap.pprof` attachment. Counts the heap specifically
    /// rather than events, so a CPU-only profile emitted alongside cannot skew the assertion.
    private var heapAttachmentCount: Int {
        core.metadata
            .compactMap { $0 as? ProfileAttachments }
            .filter { $0.heapPprof != nil }
            .count
    }

    private func sendHang(id: String, to profiler: DatadogProfiler) {
        _ = profiler.receive(
            message: .payload(AppHangMessage(
                attributes: mockRandomAttributes(),
                hang: DurationEvent(id: id, type: .error, start: 0, duration: 250)
            )),
            from: core
        )
        flushQueue()
    }

    private func sendTTID(to profiler: DatadogProfiler, at date: Date) {
        _ = profiler.receive(
            message: .payload(TTIDMessage(
                attributes: mockRandomAttributes(),
                ttid: .mockWith(id: "ttid-id", name: "time_to_initial_display", stepType: nil, date: date)
            )),
            from: core
        )
        flushQueue()
    }

    private func sendMemoryWarning(id: String, to profiler: DatadogProfiler) {
        _ = profiler.receive(
            message: .payload(MemoryWarningMessage(
                attributes: mockRandomAttributes(),
                error: DurationEvent(id: id, type: .error, start: 0, duration: 0)
            )),
            from: core
        )
        flushQueue()
    }

    private func connectMessageReceiver(
        to profiler: DatadogProfiler,
        profilingSamplerProvider: ProfilingSamplerProvider
    ) {
        let messageReceiver = CombinedFeatureMessageReceiver(
            ProfilingContextMessageReceiver(profilingSamplerProvider: profilingSamplerProvider),
            profiler
        )
        core.messageReceiver = messageReceiver
        _ = messageReceiver.receive(message: .context(core.context), from: core)
        flushQueue()
    }

    private func flushQueue() {
        profilerQueue.sync {}
    }
}

#endif // !os(watchOS)
