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

/// Tests that the memory profiler (passive sampler + +allocWithZone: swizzle) is started and stopped
/// in lockstep with the wall profiler when `memorySampleRate` > 0.
///
/// The swizzle and the passive profiler are process-global singletons.  Every test must stop them
/// unconditionally in `tearDown` to avoid leaking state into the rest of the suite.
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
        // Ensure memory profiler is clean at test start.
        MemorySwizzlingPOC.stop()
        dd_memory_test_reset()
    }

    override func tearDown() {
        // Always stop the memory profiler — it is process-global and must not leak into other tests.
        MemorySwizzlingPOC.stop()
        dd_memory_test_reset()
        DatadogProfiler.resetActiveInstance()
        dd_profiler_stop()
        dd_profiler_destroy()
        dd_delete_profiling_defaults()
        core = nil
        super.tearDown()
    }

    // MARK: - Enablement

    func testMemoryProfilerStarts_whenMemorySampleRateIsPositive() {
        // Given — profiler init with memorySampleRate > 0, native status is NOT_CREATED.
        XCTAssertFalse(dd_memory_profiler_is_running(), "Precondition: memory profiler must be stopped")
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_NOT_CREATED)

        let profilingSamplerProvider = makeSamplerProvider()
        let profiler = makeProfiler(memorySampleRate: 100, profilingSamplerProvider: profilingSamplerProvider)
        connectMessageReceiver(to: profiler, profilingSamplerProvider: profilingSamplerProvider)

        // When — foreground context drives updateProfilerState through the NOT_CREATED → RUNNING path,
        // which calls dd_profiler_start() followed by startMemoryProfiling().
        core.context = .mockWith(applicationStateHistory: .mockAppInForeground())
        flushQueue()

        // Then
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_RUNNING)
        XCTAssertTrue(dd_memory_profiler_is_running(), "Memory profiler must be running when memorySampleRate > 0")
        withExtendedLifetime(profiler) {}
    }

    func testMemoryProfilerDoesNotStart_whenMemorySampleRateIsZero() {
        // Given — profiler init with memorySampleRate == 0.
        XCTAssertFalse(dd_memory_profiler_is_running(), "Precondition: memory profiler must be stopped")
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_NOT_CREATED)

        let profilingSamplerProvider = makeSamplerProvider()
        let profiler = makeProfiler(memorySampleRate: 0, profilingSamplerProvider: profilingSamplerProvider)
        connectMessageReceiver(to: profiler, profilingSamplerProvider: profilingSamplerProvider)

        // When — foreground context starts the wall profiler but NOT the memory profiler.
        core.context = .mockWith(applicationStateHistory: .mockAppInForeground())
        flushQueue()

        // Then
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_RUNNING)
        XCTAssertFalse(dd_memory_profiler_is_running(), "Memory profiler must NOT start when memorySampleRate == 0")
        withExtendedLifetime(profiler) {}
    }

    // MARK: - Teardown / stop

    func testMemoryProfilerStops_whenWallProfilerStops() {
        // Given — reach running state via the production start path.
        let dateProvider = DateProviderMock()
        let profilingSamplerProvider = makeSamplerProvider()
        let profiler = makeProfiler(memorySampleRate: 100, profilingSamplerProvider: profilingSamplerProvider, dateProvider: dateProvider)
        connectMessageReceiver(to: profiler, profilingSamplerProvider: profilingSamplerProvider)

        core.context = .mockWith(applicationStateHistory: .mockAppInForeground())
        flushQueue()
        XCTAssertTrue(dd_memory_profiler_is_running(), "Precondition: memory profiler must be running")

        // When — background context causes wall profiler stop → memory profiler stop.
        // Setting core.context fires didSet → messageReceiver.receive → profiler.receive.
        core.context = .mockWith(applicationStateHistory: .mockWith(
            initialState: .active,
            date: dateProvider.now.addingTimeInterval(-1),
            transitions: [(state: .background, date: dateProvider.now)]
        ))
        flushQueue()

        // Then
        XCTAssertFalse(dd_memory_profiler_is_running(), "Memory profiler must stop when wall profiler stops")
        withExtendedLifetime(profiler) {}
    }

    func testMemoryProfilerStops_whenProfilerDeallocates() {
        // Given — reach running state via the production start path.
        let profilingSamplerProvider = makeSamplerProvider()
        var profiler: DatadogProfiler? = makeProfiler(memorySampleRate: 100, profilingSamplerProvider: profilingSamplerProvider)
        connectMessageReceiver(to: profiler!, profilingSamplerProvider: profilingSamplerProvider)

        core.context = .mockWith(applicationStateHistory: .mockAppInForeground())
        flushQueue()
        XCTAssertTrue(dd_memory_profiler_is_running(), "Precondition: memory profiler must be running")

        // When — profiler is deallocated.
        // `connectMessageReceiver` wired the profiler into `core.messageReceiver`, so `core`
        // holds a strong reference to it. Drop that reference first, otherwise nil-ing the local
        // won't deallocate the profiler and `deinit` (which stops the memory profiler) never runs.
        core.messageReceiver = NOPFeatureMessageReceiver()
        profiler = nil
        DatadogProfiler.resetActiveInstance()

        // Then
        XCTAssertFalse(dd_memory_profiler_is_running(), "Memory profiler must stop when the profiler is deallocated")
    }
}

// MARK: - Helpers

private extension DatadogProfilerMemoryTests {
    /// Creates a `ProfilingSamplerProvider` configured for continuous profiling at max sample rate,
    /// mirroring the `profilingSamplerProvider(isContinuousProfiling: true)` helper in the sibling test.
    func makeSamplerProvider() -> ProfilingSamplerProvider {
        ProfilingSamplerProvider(continuousSampleRate: .maxSampleRate)
    }

    func makeProfiler(
        memorySampleRate: SampleRate,
        profilingSamplerProvider: ProfilingSamplerProvider = ProfilingSamplerProvider(continuousSampleRate: .maxSampleRate),
        quotaChecker: ProfilingQuotaChecking = ProfilingQuotaCheckerMock(),
        dateProvider: DateProvider = DateProviderMock()
    ) -> DatadogProfiler {
        DatadogProfiler(
            core: core,
            profilingSamplerProvider: profilingSamplerProvider,
            quotaChecker: quotaChecker,
            queue: profilerQueue,
            profilingInterval: .infinity,
            memorySampleRate: memorySampleRate,
            dateProvider: dateProvider
        )! // swiftlint:disable:this force_unwrapping
    }

    /// Wires the profiler into the core's message receiver alongside a `ProfilingContextMessageReceiver`
    /// and delivers the current (background) context, mirroring the sibling's `connectMessageReceiver`.
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
