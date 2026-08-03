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

/// Tests the Option-B memory-profiling lifecycle: memory runs on its OWN RUM-composed session
/// decision (independent of continuous CPU profiling), pauses in the background (foreground-only),
/// and can emit a heap-only `ProfileEvent` when no CPU profile is produced.
///
/// The swizzle, the Swift rebinding, and the passive sampler are process-global singletons. Every
/// test stops them in `tearDown` so state never leaks into the rest of the suite.

/// Pure-Swift class (allocated via swift_allocObject, not +allocWithZone:).
private final class ProdSwiftFixture { var payload = (0, 0, 0, 0) }

final class DatadogProfilerMemoryTests: XCTestCase {
    private var core: PassthroughCoreMock! // swiftlint:disable:this implicitly_unwrapped_optional
    private let profilerQueue = DispatchQueue(label: "test.profiler.memory")

    override func setUp() {
        super.setUp()
        // Start with a background context so the profiler doesn't auto-start at init.
        core = PassthroughCoreMock(context: .mockWith(applicationStateHistory: .mockAppInBackground()))
        DatadogProfiler.resetActiveInstance()
        dd_profiler_stop()
        dd_profiler_destroy()
        // Ensure the memory interception paths are clean at test start.
        MemorySwizzlingPOC.stop()
        SwiftAllocInterception.stop()
        dd_memory_test_reset()
    }

    override func tearDown() {
        // Always stop the memory interception — process-global, must not leak into other tests.
        MemorySwizzlingPOC.stop()
        SwiftAllocInterception.stop()
        dd_memory_test_reset()
        DatadogProfiler.resetActiveInstance()
        dd_profiler_stop()
        dd_profiler_destroy()
        dd_delete_profiling_defaults()
        core = nil
        super.tearDown()
    }

    // MARK: - Enablement (own decision)

    func testMemoryProfilingRuns_whenConfiguredAndForeground() {
        XCTAssertFalse(dd_memory_profiler_is_running(), "Precondition: memory profiler must be stopped")

        let provider = makeSamplerProvider(memorySampleRate: .maxSampleRate)
        let profiler = makeProfiler(profilingSamplerProvider: provider)
        connectMessageReceiver(to: profiler, profilingSamplerProvider: provider)

        core.context = .mockWith(applicationStateHistory: .mockAppInForeground())
        flushQueue()

        XCTAssertTrue(dd_memory_profiler_is_running(), "Memory profiling must run when configured + foreground")
        withExtendedLifetime(profiler) {}
    }

    func testMemoryProfilingDoesNotRun_whenNotConfigured() {
        let provider = makeSamplerProvider(memorySampleRate: 0)
        let profiler = makeProfiler(profilingSamplerProvider: provider)
        connectMessageReceiver(to: profiler, profilingSamplerProvider: provider)

        core.context = .mockWith(applicationStateHistory: .mockAppInForeground())
        flushQueue()

        XCTAssertFalse(dd_memory_profiler_is_running(), "Memory profiling must NOT run when memorySampleRate == 0")
        withExtendedLifetime(profiler) {}
    }

    // MARK: - Independence from continuous CPU profiling

    /// Option B core property: memory runs even when continuous CPU profiling is NOT configured.
    func testMemoryProfilingRuns_independentlyOfContinuous() {
        // continuous OFF, memory ON.
        let provider = makeSamplerProvider(continuousSampleRate: 0, memorySampleRate: .maxSampleRate)
        let profiler = makeProfiler(profilingSamplerProvider: provider)
        connectMessageReceiver(to: profiler, profilingSamplerProvider: provider)

        core.context = .mockWith(applicationStateHistory: .mockAppInForeground())
        flushQueue()

        XCTAssertTrue(dd_memory_profiler_is_running(), "Memory must run even with continuous CPU profiling off")
        XCTAssertNotEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_RUNNING, "CPU profiler must NOT be running")
        withExtendedLifetime(profiler) {}
    }

    /// Option B independent EMISSION: with continuous off and memory on, the background transition
    /// flushes a heap-only `ProfileEvent` (no `profile.pprof`, a `heap.pprof`) — the pre-background
    /// window is emitted before memory pauses.
    func testMemoryEmitsHeapOnlyProfile_whenContinuousNotConfigured() throws {
        let dateProvider = DateProviderMock()
        let provider = makeSamplerProvider(continuousSampleRate: 0, memorySampleRate: .maxSampleRate)
        let profiler = makeProfiler(profilingSamplerProvider: provider, dateProvider: dateProvider)
        connectMessageReceiver(to: profiler, profilingSamplerProvider: provider)

        core.context = .mockWith(applicationStateHistory: .mockAppInForeground())
        flushQueue()
        XCTAssertTrue(dd_memory_profiler_is_running())
        XCTAssertNotEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_RUNNING, "CPU profiler must be off")

        // Produce a live sampled allocation so the heap snapshot is non-empty this window.
        dd_memory_test_force_next_sample()
        let obj = ProdSwiftFixture()

        try withExtendedLifetime(obj) {
            // Background transition triggers sendProfile() (pre-background flush) before memory pauses.
            core.context = .mockWith(applicationStateHistory: .mockWith(
                initialState: .active,
                date: dateProvider.now.addingTimeInterval(-1),
                transitions: [(state: .background, date: dateProvider.now)]
            ))
            flushQueue()

            let event = try XCTUnwrap(core.events.first as? ProfileEvent, "a ProfileEvent must be written")
            let metadata = try XCTUnwrap(core.metadata.first as? ProfileAttachments)
            XCTAssertNil(metadata.pprof, "heap-only event must carry no CPU profile.pprof")
            XCTAssertNotNil(metadata.heapPprof, "heap-only event must carry heap.pprof")
            XCTAssertTrue(event.attachments.contains(ProfileAttachments.Constants.heapFilename))
            XCTAssertFalse(event.attachments.contains(ProfileAttachments.Constants.pprofFilename))
        }
        withExtendedLifetime(profiler) {}
    }

    // MARK: - Foreground-only (pause/resume)

    /// Replaces the old `testMemoryProfilerStops_whenWallProfilerStops`. Under Option B memory is not
    /// tied to the wall profiler; it pauses in the background (foreground-only) and resumes on foreground.
    func testMemoryProfilingPausesOnBackground_andResumesOnForeground() {
        let dateProvider = DateProviderMock()
        let provider = makeSamplerProvider(memorySampleRate: .maxSampleRate)
        let profiler = makeProfiler(profilingSamplerProvider: provider, dateProvider: dateProvider)
        connectMessageReceiver(to: profiler, profilingSamplerProvider: provider)

        // Foreground → running.
        core.context = .mockWith(applicationStateHistory: .mockAppInForeground())
        flushQueue()
        XCTAssertTrue(dd_memory_profiler_is_running(), "Precondition: memory must run in foreground")

        // Background → paused (foreground-only, via profiling conditions).
        core.context = .mockWith(applicationStateHistory: .mockWith(
            initialState: .active,
            date: dateProvider.now.addingTimeInterval(-1),
            transitions: [(state: .background, date: dateProvider.now)]
        ))
        flushQueue()
        XCTAssertFalse(dd_memory_profiler_is_running(), "Memory must pause in the background")

        // Foreground again → resumed.
        core.context = .mockWith(applicationStateHistory: .mockAppInForeground())
        flushQueue()
        XCTAssertTrue(dd_memory_profiler_is_running(), "Memory must resume on foreground")
        withExtendedLifetime(profiler) {}
    }

    // MARK: - Teardown / stop

    func testMemoryProfilerStops_whenProfilerDeallocates() {
        let provider = makeSamplerProvider(memorySampleRate: .maxSampleRate)
        var profiler: DatadogProfiler? = makeProfiler(profilingSamplerProvider: provider)
        connectMessageReceiver(to: profiler!, profilingSamplerProvider: provider)

        core.context = .mockWith(applicationStateHistory: .mockAppInForeground())
        flushQueue()
        XCTAssertTrue(dd_memory_profiler_is_running(), "Precondition: memory profiler must be running")

        // `connectMessageReceiver` wired the profiler into `core.messageReceiver`, so `core`
        // holds a strong reference. Drop it first, otherwise `deinit` never runs.
        core.messageReceiver = NOPFeatureMessageReceiver()
        profiler = nil
        DatadogProfiler.resetActiveInstance()

        XCTAssertFalse(dd_memory_profiler_is_running(), "Memory profiler must stop when the profiler is deallocated")
    }

    // MARK: - Swift interception is wired

    func testSwiftInterception_isActive_whenMemoryProfilingRuns() {
        let provider = makeSamplerProvider(memorySampleRate: .maxSampleRate)
        let profiler = makeProfiler(profilingSamplerProvider: provider)
        connectMessageReceiver(to: profiler, profilingSamplerProvider: provider)

        core.context = .mockWith(applicationStateHistory: .mockAppInForeground())
        flushQueue()
        XCTAssertTrue(dd_memory_profiler_is_running(), "Precondition: memory profiler must be running")

        // A pure-Swift allocation (swift_allocObject path) must land in the shared live-set.
        dd_memory_test_force_next_sample()
        let before = dd_memory_test_live_count()
        let obj = ProdSwiftFixture()
        withExtendedLifetime(obj) {
            XCTAssertEqual(dd_memory_test_live_count(), before + 1,
                           "pure-Swift alloc must be captured => Swift interception active in the production path")
        }
        withExtendedLifetime(profiler) {}
    }
}

// MARK: - Helpers

private extension DatadogProfilerMemoryTests {
    func makeSamplerProvider(
        continuousSampleRate: SampleRate = .maxSampleRate,
        memorySampleRate: SampleRate = 0
    ) -> ProfilingSamplerProvider {
        ProfilingSamplerProvider(continuousSampleRate: continuousSampleRate, memorySampleRate: memorySampleRate)
    }

    func makeProfiler(
        profilingSamplerProvider: ProfilingSamplerProvider,
        quotaChecker: ProfilingQuotaChecking = ProfilingQuotaCheckerMock(),
        dateProvider: DateProvider = DateProviderMock()
    ) -> DatadogProfiler {
        DatadogProfiler(
            core: core,
            profilingSamplerProvider: profilingSamplerProvider,
            quotaChecker: quotaChecker,
            queue: profilerQueue,
            profilingInterval: .infinity,
            dateProvider: dateProvider
        )! // swiftlint:disable:this force_unwrapping
    }

    func connectMessageReceiver(
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

    func flushQueue() {
        profilerQueue.sync {}
    }
}

#endif // !os(watchOS)
