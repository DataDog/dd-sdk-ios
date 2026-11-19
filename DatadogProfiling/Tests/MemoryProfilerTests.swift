/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if !os(watchOS) && !os(macOS)

import XCTest
import DatadogMachProfiler.Testing
import DatadogInternal
import TestUtilities
@testable import DatadogProfiling

final class MemoryProfilerTests: XCTestCase {
    private let queue = DispatchQueue(label: "test.memory-profiler")
    private let core = PassthroughCoreMock()
    private let sessionID = UUID()
    private var profilingSamplerProvider = ProfilingSamplerProvider(continuousSampleRate: 0, memorySampleRate: 100)

    override func setUp() {
        super.setUp()
        dd_memory_profiler_configure_for_testing(DD_MEMORY_TEST_HOOKS_SUCCEED)
        let suiteName = "MemoryProfilerTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set(100, forKey: DD_PROFILING_MEMORY_SAMPLE_RATE_KEY)
        dd_memory_profiler_auto_start_for_testing(suiteName, false, false)
        defaults.removePersistentDomain(forName: suiteName)
        profilingSamplerProvider = ProfilingSamplerProvider(
            continuousSampleRate: 0,
            memorySampleRate: 100
        )
    }

    override func tearDown() {
        drain()
        dd_memory_profiler_reset_for_testing()
        super.tearDown()
    }

    func testDisabledConfigurationDiscardsConstructorSampler() {
        XCTAssertTrue(dd_memory_profiler_start())
        record()
        let profiler = makeProfiler(memorySampleRate: 0)
        receive(context: context(), on: profiler)
        receiveTTID(on: profiler)
        profiler.captureWindow()
        drain()

        XCTAssertEqual(profiler.state, .stopped)
        XCTAssertFalse(dd_memory_profiler_is_running())
        XCTAssertEqual(diagnostics.captures_count, 0)
    }

    func testConfiguredSamplerWaitsForFirstRUMDecision() {
        let profiler = makeProfiler()
        XCTAssertEqual(profiler.state, .waiting)
        XCTAssertTrue(dd_memory_profiler_is_running())
        let origin = dd_memory_profiler_window_start_time_nanos()

        receive(context: context(), on: profiler)
        drain()

        XCTAssertEqual(profiler.state, .running)
        XCTAssertEqual(dd_memory_profiler_window_start_time_nanos(), origin)
        XCTAssertEqual(diagnostics.captures_count, 0)
    }

    func testUnrelatedContextChangesKeepActiveWindowOpen() {
        let profiler = makeRuntimeProfiler()
        receive(context: context(), on: profiler)
        drain()
        let origin = dd_memory_profiler_window_start_time_nanos()
        record(size: 16)

        for index in 0..<100 {
            receive(context: context(
                consent: .granted,
                battery: .mockWith(state: .charging, level: 0.5),
                viewID: "view-\(index)"
            ), on: profiler)
        }
        drain()

        XCTAssertEqual(profiler.state, .running)
        XCTAssertTrue(dd_memory_profiler_is_running())
        XCTAssertEqual(dd_memory_profiler_window_start_time_nanos(), origin)
        XCTAssertEqual(diagnostics.captures_count, 0)

        record(address: 0x20000, size: 8)
        profiler.captureWindow()
        drain()

        XCTAssertEqual(diagnostics.captures_count, 1)
        XCTAssertEqual(diagnostics.time_nanos, origin)
        XCTAssertEqual(diagnostics.alloc_space, 24)
    }

    func testMemorySamplingDoesNotRequireCPUProfilingDecision() {
        let profiler = makeRuntimeProfiler()
        receive(context: context(), on: profiler)
        drain()
        record(size: 16, weight: 2)
        profiler.captureWindow()
        drain()

        XCTAssertEqual(profilingSamplerProvider.continuousProfilingSampled, false)
        XCTAssertEqual(profiler.state, .running)
        XCTAssertEqual(diagnostics.ready_count, 1)
        XCTAssertEqual(diagnostics.alloc_space, 32)
        XCTAssertEqual(diagnostics.inuse_space, 32)
    }

    func testSampledOutSessionTracksAllocationsAndFreesWithoutEmitting() {
        let profiler = makeRuntimeProfiler()
        receive(context: context(sampleRate: 0), on: profiler)
        drain()
        let origin = dd_memory_profiler_window_start_time_nanos()
        record(size: 16)
        record(address: 0x20000, size: 8)
        for index in 0..<100 {
            receive(context: context(sampleRate: 0, viewID: "view-\(index)"), on: profiler)
            profiler.captureWindow()
        }
        drain()

        XCTAssertEqual(profiler.state, .running)
        XCTAssertTrue(dd_memory_profiler_is_running())
        XCTAssertEqual(dd_memory_profiler_window_start_time_nanos(), origin)
        XCTAssertEqual(diagnostics.captures_count, 0)
        dd_memory_profiler_remove_for_testing(UnsafeRawPointer(bitPattern: 0x20000))

        receive(context: context(sessionID: UUID()), on: profiler)
        drain()
        XCTAssertEqual(diagnostics.captures_count, 1)
        XCTAssertEqual(diagnostics.time_nanos, origin)
        XCTAssertEqual(diagnostics.alloc_space, 24)
        XCTAssertEqual(diagnostics.inuse_space, 16)
        let nextOrigin = dd_memory_profiler_window_start_time_nanos()

        record(address: 0x30000, size: 4)
        profiler.captureWindow()
        drain()
        XCTAssertEqual(profiler.state, .running)
        XCTAssertEqual(diagnostics.captures_count, 2)
        XCTAssertEqual(diagnostics.time_nanos, nextOrigin)
        XCTAssertEqual(diagnostics.alloc_space, 4)
        XCTAssertEqual(diagnostics.inuse_space, 20)
    }

    func testSamplingChangeWithinSessionClosesDeltaAndKeepsLiveObjects() {
        let profiler = makeRuntimeProfiler()
        receive(context: context(), on: profiler)
        drain()
        let origin = dd_memory_profiler_window_start_time_nanos()
        record(size: 16)

        receive(context: context(sampleRate: 0), on: profiler)
        profiler.captureWindow()
        drain()
        XCTAssertEqual(profiler.state, .running)
        XCTAssertTrue(dd_memory_profiler_is_running())
        XCTAssertEqual(diagnostics.time_nanos, origin)
        XCTAssertEqual(diagnostics.captures_count, 1)
        XCTAssertEqual(diagnostics.alloc_space, 16)

        record(address: 0x20000, size: 8)
        receive(context: context(), on: profiler)
        profiler.captureWindow()
        drain()

        XCTAssertEqual(profiler.state, .running)
        XCTAssertEqual(diagnostics.captures_count, 3)
        XCTAssertEqual(diagnostics.alloc_space, 0)
        XCTAssertEqual(diagnostics.inuse_space, 24)
    }

    func testMemorySamplerRejectsEmissionWhileRecordingContinues() {
        dd_memory_profiler_stop()
        let profiler = makeProfiler(memorySampleRate: 1)
        XCTAssertEqual(profiler.state, .stopped)
        receive(context: context(sessionID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!), on: profiler)
        profiler.captureWindow()
        drain()

        XCTAssertEqual(profilingSamplerProvider.memory.sampled, false)
        XCTAssertEqual(profiler.state, .running)
        XCTAssertTrue(dd_memory_profiler_is_running())
        XCTAssertEqual(diagnostics.captures_count, 0)
    }

    func testRuntimeStartsWithoutRUMAndKeepsRecordingInSampledOutSession() {
        dd_memory_profiler_stop()
        let profiler = makeProfiler(memorySampleRate: 10)
        XCTAssertEqual(profiler.state, .stopped)
        XCTAssertFalse(dd_memory_profiler_is_running())

        receive(context: context(hasRUM: false), on: profiler)
        drain()
        XCTAssertEqual(profiler.state, .waiting)
        XCTAssertTrue(dd_memory_profiler_is_running())
        XCTAssertFalse(dd_memory_profiler_was_started_at_launch())
        record(size: 16)

        receive(context: context(sessionID: UUID(uuidString: "a1b2c3d4-e5f6-7890-abcd-d860b2b9437a")!), on: profiler)
        receiveTTID(on: profiler)
        profiler.captureWindow()
        drain()
        XCTAssertEqual(profilingSamplerProvider.memory.sampled, false)
        XCTAssertEqual(profiler.state, .running)
        XCTAssertTrue(dd_memory_profiler_is_running())
        XCTAssertEqual(diagnostics.captures_count, 1)
        XCTAssertEqual(diagnostics.alloc_space, 16)

        record(address: 0x20000, size: 8)
        receive(context: context(sessionID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!), on: profiler)
        drain()
        XCTAssertEqual(profilingSamplerProvider.memory.sampled, true)
        XCTAssertEqual(diagnostics.captures_count, 2)
        XCTAssertEqual(diagnostics.alloc_space, 8)
        XCTAssertEqual(diagnostics.inuse_space, 24)

        record(address: 0x30000, size: 4)
        profiler.captureWindow()
        drain()
        XCTAssertEqual(diagnostics.captures_count, 3)
        XCTAssertEqual(diagnostics.alloc_space, 4)
        XCTAssertEqual(diagnostics.inuse_space, 28)
    }

    func testFirstSessionDiscardsRuntimeDeltaAndKeepsItsLiveObjects() {
        let profiler = makeRuntimeProfiler()
        receive(context: context(hasRUM: false), on: profiler)
        drain()
        XCTAssertFalse(dd_memory_profiler_was_started_at_launch())
        record(size: 16)

        receive(context: context(), on: profiler)
        drain()
        XCTAssertEqual(diagnostics.captures_count, 1)
        XCTAssertEqual(diagnostics.alloc_space, 16)
        XCTAssertEqual(diagnostics.inuse_space, 16)
        let origin = dd_memory_profiler_window_start_time_nanos()

        record(address: 0x20000, size: 8)
        profiler.captureWindow()
        drain()
        XCTAssertEqual(diagnostics.captures_count, 2)
        XCTAssertEqual(diagnostics.time_nanos, origin)
        XCTAssertEqual(diagnostics.alloc_space, 8)
        XCTAssertEqual(diagnostics.inuse_space, 24)
    }

    func testLaunchUsesMemorySessionSamplingAndKeepsRecordingWhenRejected() {
        let profiler = makeProfiler(memorySampleRate: 1)
        let origin = dd_memory_profiler_window_start_time_nanos()
        record()
        receive(context: context(sessionID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!), on: profiler)
        profiler.captureWindow()
        drain()

        XCTAssertEqual(profilingSamplerProvider.memory.sampled, false)
        XCTAssertTrue(dd_memory_profiler_is_running())
        XCTAssertEqual(diagnostics.captures_count, 0)

        receiveTTID(on: profiler)
        drain()

        XCTAssertEqual(diagnostics.captures_count, 1)
        XCTAssertEqual(diagnostics.time_nanos, origin)
        XCTAssertEqual(diagnostics.alloc_space, 16)
        XCTAssertEqual(profiler.state, .running)
        XCTAssertTrue(dd_memory_profiler_is_running())
    }

    func testPendingLaunchUsesMemorySessionSamplingWithoutStoppingRecording() {
        let profiler = makeProfiler(memorySampleRate: 1)
        let origin = dd_memory_profiler_window_start_time_nanos()
        record()
        receiveTTID(on: profiler)
        drain()

        receive(context: context(sessionID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!), on: profiler)
        drain()

        XCTAssertEqual(profilingSamplerProvider.memory.sampled, false)
        XCTAssertEqual(diagnostics.captures_count, 1)
        XCTAssertEqual(diagnostics.time_nanos, origin)
        XCTAssertEqual(diagnostics.alloc_space, 16)
        XCTAssertEqual(profiler.state, .running)
        XCTAssertTrue(dd_memory_profiler_is_running())
    }

    func testBlockedSampledOutLaunchClosesAtTTIDAndKeepsRecording() {
        let profiler = makeProfiler(memorySampleRate: 1)
        let sessionID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let origin = dd_memory_profiler_window_start_time_nanos()
        record(size: 16)
        receive(context: context(sessionID: sessionID, lowPower: true), on: profiler)
        drain()

        XCTAssertEqual(profilingSamplerProvider.memory.sampled, false)
        XCTAssertEqual(profiler.state, .emissionSuspended)
        XCTAssertTrue(dd_memory_profiler_is_running())
        XCTAssertEqual(diagnostics.captures_count, 0)
        XCTAssertEqual(dd_memory_profiler_window_start_time_nanos(), origin)

        record(address: 0x20000, size: 8)
        receiveTTID(on: profiler)
        drain()

        XCTAssertEqual(profiler.state, .emissionSuspended)
        XCTAssertTrue(dd_memory_profiler_is_running())
        XCTAssertEqual(diagnostics.captures_count, 1)
        XCTAssertEqual(diagnostics.time_nanos, origin)
        XCTAssertEqual(diagnostics.alloc_space, 24)

        receive(context: context(sessionID: sessionID), on: profiler)
        receiveTTID(on: profiler)
        profiler.captureWindow()
        drain()

        XCTAssertEqual(profiler.state, .running)
        XCTAssertTrue(dd_memory_profiler_is_running())
        XCTAssertEqual(diagnostics.captures_count, 1)
    }

    func testBlockedConditionsDeferLaunchCaptureUntilTTIDThenKeepContinuousEmissionSuspended() {
        let suiteName = "MemoryProfilerTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        for blocker in ["low-power", "battery", "background"] {
            dd_memory_profiler_configure_for_testing(DD_MEMORY_TEST_HOOKS_SUCCEED)
            defaults.set(100, forKey: DD_PROFILING_MEMORY_SAMPLE_RATE_KEY)
            dd_memory_profiler_auto_start_for_testing(suiteName, false, false)
            do {
                let profiler = makeProfiler()
                let origin = dd_memory_profiler_window_start_time_nanos()
                record(size: 16)
                receive(context: context(
                    state: blocker == "background" ? .background : .active,
                    lowPower: blocker == "low-power",
                    battery: blocker == "battery" ? .mockWith(state: .unplugged, level: 0.05) : nil,
                    hadForeground: blocker == "background"
                ), on: profiler)
                drain()

                XCTAssertEqual(profiler.state, .emissionSuspended, blocker)
                XCTAssertEqual(diagnostics.captures_count, 0, blocker)
                XCTAssertEqual(dd_memory_profiler_window_start_time_nanos(), origin, blocker)
                XCTAssertTrue(dd_memory_profiler_is_running(), blocker)
                XCTAssertFalse(dd_memory_profiler_is_paused(), blocker)

                record(address: 0x20000, size: 8)
                receiveTTID(on: profiler)
                receiveTTID(on: profiler)
                profiler.captureWindow()
                drain()

                XCTAssertEqual(profiler.state, .emissionSuspended, blocker)
                XCTAssertEqual(diagnostics.captures_count, 1, blocker)
                XCTAssertEqual(diagnostics.time_nanos, origin, blocker)
                XCTAssertEqual(diagnostics.alloc_space, 24, blocker)
                XCTAssertEqual(diagnostics.inuse_space, 24, blocker)

                record(address: 0x30000, size: 4)
                profiler.captureWindow()
                drain()
                XCTAssertEqual(diagnostics.captures_count, 1, blocker)

                receive(context: context(), on: profiler)
                profiler.captureWindow()
                drain()
                XCTAssertEqual(profiler.state, .running, blocker)
                XCTAssertEqual(diagnostics.captures_count, 2, blocker)
                XCTAssertEqual(diagnostics.alloc_space, 4, blocker)
                XCTAssertEqual(diagnostics.inuse_space, 28, blocker)
            }
        }
    }

    func testSessionChangeClosesPriorSessionBeforeBlockedRuntimeWindow() {
        let profiler = makeRuntimeProfiler()
        receive(context: context(), on: profiler)
        drain()
        record(size: 16)
        let nextSessionID = UUID()
        receive(context: context(sessionID: nextSessionID, lowPower: true), on: profiler)
        drain()

        XCTAssertEqual(profiler.state, .emissionSuspended)
        XCTAssertEqual(diagnostics.captures_count, 2)
        XCTAssertEqual(diagnostics.ready_count, 1)
        XCTAssertEqual(diagnostics.idle_count, 1)

        record(address: 0x20000, size: 8)
        receive(context: context(sessionID: nextSessionID), on: profiler)
        receiveTTID(on: profiler)
        receiveTTID(on: profiler)
        drain()

        XCTAssertEqual(profiler.state, .running)
        XCTAssertEqual(diagnostics.captures_count, 2)
        profiler.captureWindow()
        drain()

        XCTAssertEqual(diagnostics.captures_count, 3)
        XCTAssertEqual(diagnostics.alloc_space, 8)
        XCTAssertEqual(diagnostics.inuse_space, 24)
    }

    func testReceiverObservesTTIDWithoutConsumingCPUMessage() {
        let profiler = makeProfiler()
        let receiver = CombinedFeatureMessageReceiver([
            ProfilingContextMessageReceiver(profilingSamplerProvider: profilingSamplerProvider),
            profiler
        ])
        let contextConsumed = receiver.receive(message: .context(context()), from: core)
        record()
        let launchConsumed = profiler.receive(
            message: .payload(TTIDMessage(attributes: [:], ttid: .mockWith(stepType: nil))),
            from: core
        )
        drain()

        XCTAssertFalse(contextConsumed)
        XCTAssertFalse(launchConsumed)
        XCTAssertEqual(diagnostics.ready_count, 1)
    }

    func testNativeIdleWindowAndLastFreeHaveDifferentCaptureStatuses() {
        let profiler = makeRuntimeProfiler()
        receive(context: context(), on: profiler)
        profiler.captureWindow()
        drain()
        XCTAssertEqual(diagnostics.last_status, DD_MEMORY_CAPTURE_IDLE)

        record()
        profiler.captureWindow()
        drain()
        XCTAssertEqual(diagnostics.last_status, DD_MEMORY_CAPTURE_READY)
        dd_memory_profiler_remove_for_testing(UnsafeRawPointer(bitPattern: 0x10000))
        profiler.captureWindow()
        drain()

        XCTAssertEqual(diagnostics.captures_count, 3)
        XCTAssertEqual(diagnostics.ready_count, 2)
        XCTAssertEqual(diagnostics.idle_count, 1)
        XCTAssertEqual(diagnostics.last_status, DD_MEMORY_CAPTURE_READY)
        XCTAssertEqual(diagnostics.sample_count, 0, "The final free must close an empty ready window")
    }

    func testNativeFailureStopsHooksAndDoesNotRetryOnEveryContext() {
        for failure in [DD_MEMORY_TEST_SWIFT_HOOK_FAILS, DD_MEMORY_TEST_OBJC_HOOK_FAILS] {
            dd_memory_profiler_configure_for_testing(failure)
            do {
                let profiler = makeProfiler()
                XCTAssertEqual(profiler.state, .stopped)
                receive(context: context(), on: profiler)
                drain()
                XCTAssertEqual(profiler.state, .failed)
                XCTAssertFalse(dd_memory_profiler_is_running())
                // Successful native starts become possible, but this failed owner must stay disabled.
                dd_memory_profiler_configure_for_testing(DD_MEMORY_TEST_HOOKS_SUCCEED)
                receive(context: context(), on: profiler)
                receive(context: context(sessionID: UUID()), on: profiler)
                drain()

                XCTAssertEqual(profiler.state, .failed)
                XCTAssertFalse(dd_memory_profiler_is_running())
                XCTAssertEqual(diagnostics.captures_count, 0)
            }
        }
    }

    func testNativeFailureDuringRestartDoesNotRetryOnEveryContext() {
        for failure in [DD_MEMORY_TEST_SWIFT_HOOK_FAILS, DD_MEMORY_TEST_OBJC_HOOK_FAILS] {
            dd_memory_profiler_configure_for_testing(DD_MEMORY_TEST_HOOKS_SUCCEED)
            do {
                let profiler = makeProfiler()
                receive(context: context(consent: .notGranted), on: profiler)
                drain()
                XCTAssertEqual(profiler.state, .stopped)

                dd_memory_profiler_configure_for_testing(failure)
                receive(context: context(sessionID: UUID()), on: profiler)
                drain()
                XCTAssertEqual(profiler.state, .failed)
                XCTAssertFalse(dd_memory_profiler_is_running())
                XCTAssertFalse(dd_swift_alloc_hook_diagnostics().is_enabled)
                XCTAssertFalse(dd_objc_alloc_hook_diagnostics().is_enabled)

                dd_memory_profiler_configure_for_testing(DD_MEMORY_TEST_HOOKS_SUCCEED)
                receive(context: context(), on: profiler)
                receive(context: context(sessionID: UUID()), on: profiler)
                profiler.captureWindow()
                drain()
                XCTAssertEqual(profiler.state, .failed)
                XCTAssertFalse(dd_memory_profiler_is_running())
                XCTAssertEqual(diagnostics.captures_count, 0)
            }
        }
    }

    func testCaptureFailureDropsWindowAndStopsHooks() {
        let profiler = makeRuntimeProfiler()
        receive(context: context(), on: profiler)
        drain()
        dd_memory_profiler_fail_next_capture_for_testing()
        profiler.captureWindow()
        drain()

        XCTAssertEqual(profiler.state, .failed)
        XCTAssertFalse(dd_memory_profiler_is_running())
        XCTAssertEqual(diagnostics.captures_count, 1)
        XCTAssertEqual(diagnostics.last_status, DD_MEMORY_CAPTURE_FAILED)

        receive(context: context(), on: profiler)
        profiler.captureWindow()
        drain()
        XCTAssertEqual(diagnostics.captures_count, 1)
        XCTAssertFalse(dd_memory_profiler_is_running())
    }

    func testBackgroundClosesForegroundWindowOnceWhileRecordingContinues() {
        let profiler = makeRuntimeProfiler()
        receive(context: context(), on: profiler)
        drain()
        record()
        receive(context: context(state: .background), on: profiler)
        receive(context: context(state: .background), on: profiler)
        profiler.captureWindow()
        drain()

        XCTAssertEqual(profiler.state, .emissionSuspended)
        XCTAssertEqual(diagnostics.captures_count, 1)
        XCTAssertEqual(diagnostics.ready_count, 1)
        XCTAssertTrue(dd_memory_profiler_is_running())
        XCTAssertFalse(dd_memory_profiler_is_paused())

        record(address: 0x20000, size: 8)
        receive(context: context(), on: profiler)
        profiler.captureWindow()
        drain()

        XCTAssertEqual(profiler.state, .running)
        XCTAssertEqual(diagnostics.captures_count, 2)
        XCTAssertEqual(diagnostics.alloc_space, 8)
        XCTAssertEqual(diagnostics.inuse_space, 24)
    }

    func testLowPowerAndBatterySuspendEmissionWhileRecordingContinues() {
        for blocker in ["low-power", "battery"] {
            dd_memory_profiler_configure_for_testing(DD_MEMORY_TEST_HOOKS_SUCCEED)
            do {
                let profiler = makeProfiler()
                receive(context: context(), on: profiler)
                drain()
                record()
                receive(context: context(
                    lowPower: blocker == "low-power",
                    battery: blocker == "battery" ? .mockWith(state: .unplugged, level: 0.05) : nil
                ), on: profiler)
                profiler.captureWindow()
                drain()
                XCTAssertEqual(profiler.state, .emissionSuspended, blocker)
                XCTAssertEqual(diagnostics.captures_count, 1, blocker)
                XCTAssertTrue(dd_memory_profiler_is_running(), blocker)
                XCTAssertFalse(dd_memory_profiler_is_paused(), blocker)

                record(address: 0x20000, size: 8)
                dd_memory_profiler_remove_for_testing(UnsafeRawPointer(bitPattern: 0x10000))
                receive(context: context(), on: profiler)
                drain()
                XCTAssertEqual(profiler.state, .running, blocker)
                XCTAssertEqual(diagnostics.captures_count, 1, blocker)
                profiler.captureWindow()
                drain()
                XCTAssertEqual(diagnostics.alloc_space, 8, blocker)
                XCTAssertEqual(diagnostics.inuse_space, 8, blocker)
            }
        }
    }

    func testInactiveTransitionDoesNotRearmBackgroundEmission() {
        let profiler = makeRuntimeProfiler()
        receive(context: context(), on: profiler)
        receive(context: context(state: .background), on: profiler)
        receive(context: context(state: .inactive), on: profiler)
        profiler.captureWindow()
        receive(context: context(state: .background), on: profiler)
        profiler.captureWindow()
        drain()

        XCTAssertEqual(profiler.state, .emissionSuspended)
        XCTAssertEqual(diagnostics.captures_count, 1)
        XCTAssertTrue(dd_memory_profiler_is_running())

        receive(context: context(), on: profiler)
        profiler.captureWindow()
        drain()
        XCTAssertEqual(profiler.state, .running)
        XCTAssertEqual(diagnostics.captures_count, 2)
    }

    func testFirstActiveContextMakesInactiveWindowEligibleForCapture() {
        let profiler = makeRuntimeProfiler()
        receive(context: context(state: .inactive), on: profiler)
        drain()
        XCTAssertEqual(profiler.state, .running)
        record()
        profiler.captureWindow()
        drain()
        XCTAssertEqual(diagnostics.captures_count, 0)

        receive(context: context(), on: profiler)
        profiler.captureWindow()
        drain()

        XCTAssertEqual(profiler.state, .running)
        XCTAssertEqual(diagnostics.captures_count, 1)
        XCTAssertEqual(diagnostics.alloc_space, 16)
    }

    func testFirstForegroundWindowRetainsBackgroundRecordingDuration() {
        let profiler = makeRuntimeProfiler()
        receive(context: context(), on: profiler)
        drain()
        record(size: 16)
        receive(context: context(state: .background), on: profiler)
        drain()
        let foreground = diagnostics
        XCTAssertEqual(foreground.captures_count, 1)
        XCTAssertEqual(foreground.last_status, DD_MEMORY_CAPTURE_READY)
        XCTAssertEqual(foreground.alloc_space, 16)
        XCTAssertEqual(foreground.inuse_space, 16)
        let backgroundOrigin = dd_memory_profiler_window_start_time_nanos()
        XCTAssertEqual(backgroundOrigin, foreground.time_nanos + foreground.duration_nanos)
        record(address: 0x20000, size: 24)
        dd_memory_profiler_remove_for_testing(UnsafeRawPointer(bitPattern: 0x10000))
        profiler.captureWindow()
        drain()
        XCTAssertEqual(diagnostics.captures_count, foreground.captures_count)
        XCTAssertTrue(dd_memory_profiler_is_running())
        XCTAssertFalse(dd_memory_profiler_is_paused())
        XCTAssertEqual(dd_memory_profiler_window_start_time_nanos(), backgroundOrigin)

        receive(context: context(), on: profiler)
        drain()
        XCTAssertEqual(dd_memory_profiler_window_start_time_nanos(), backgroundOrigin)
        profiler.captureWindow()
        drain()

        XCTAssertEqual(diagnostics.captures_count, 2)
        XCTAssertEqual(diagnostics.last_status, DD_MEMORY_CAPTURE_READY)
        XCTAssertEqual(diagnostics.time_nanos, backgroundOrigin)
        XCTAssertGreaterThan(diagnostics.duration_nanos, 0)
        XCTAssertEqual(dd_memory_profiler_window_start_time_nanos(), backgroundOrigin + diagnostics.duration_nanos)
        XCTAssertEqual(diagnostics.alloc_space, 24)
        XCTAssertEqual(diagnostics.inuse_space, 24)
    }

    func testForegroundResumeWaitsForExplicitCapture() {
        let dateProvider = DateProviderMock()
        let profiler = makeRuntimeProfiler(dateProvider: dateProvider)
        receive(context: context(), on: profiler)
        receive(context: context(state: .background), on: profiler)
        drain()
        dateProvider.now.addTimeInterval(7_200)
        receive(context: context(), on: profiler)
        drain()

        XCTAssertEqual(profiler.state, .running)
        XCTAssertEqual(diagnostics.captures_count, 1)
        profiler.captureWindow()
        drain()
        XCTAssertEqual(diagnostics.captures_count, 2)
    }

    func testBackgroundOnlyLaunchIsNotEmittedAndRecordingContinues() {
        let profiler = makeProfiler()
        receive(context: context(state: .background), on: profiler)
        receiveTTID(on: profiler)
        profiler.captureWindow()
        drain()

        XCTAssertEqual(profiler.state, .emissionSuspended)
        XCTAssertEqual(diagnostics.captures_count, 1)
        XCTAssertTrue(dd_memory_profiler_is_running())
        XCTAssertFalse(dd_memory_profiler_is_paused())
    }

    func testSessionBoundaryClosesDeltaAndInvalidatesPreviousLaunchWindow() {
        let profiler = makeProfiler()
        receive(context: context(viewID: "prior-view"), on: profiler)
        record(size: 16)
        receive(context: context(sessionID: UUID(), viewID: "new-view"), on: profiler)
        drain()

        XCTAssertEqual(diagnostics.captures_count, 1)
        XCTAssertEqual(diagnostics.alloc_space, 16)
        XCTAssertEqual(diagnostics.inuse_space, 16)
        record(address: 0x20000, size: 8)
        receiveTTID(on: profiler)
        receiveTTID(on: profiler)
        drain()
        XCTAssertEqual(diagnostics.captures_count, 1, "TTID must not emit a partial launch from the new session")
        profiler.captureWindow()
        drain()

        XCTAssertEqual(diagnostics.captures_count, 2)
        XCTAssertEqual(diagnostics.alloc_space, 8)
        XCTAssertEqual(diagnostics.inuse_space, 24)
        XCTAssertEqual(profiler.state, .running)
    }

    func testSampledOutSessionRetainsEarlierSurvivorsAndIsolatesAllocationDelta() {
        let profiler = makeRuntimeProfiler()
        receive(context: context(), on: profiler)
        drain()
        record(size: 16)
        queue.suspend()
        receive(context: context(), on: profiler)
        let sampledOutSession = UUID()
        receive(context: context(sessionID: sampledOutSession, sampleRate: 0), on: profiler)
        XCTAssertEqual(profilingSamplerProvider.memory.sampled, false)
        queue.resume()
        drain()

        XCTAssertEqual(diagnostics.captures_count, 1, "Queued session A must retain its sampled-in decision")
        XCTAssertEqual(diagnostics.alloc_space, 16)
        XCTAssertEqual(profiler.state, .running)
        XCTAssertTrue(dd_memory_profiler_is_running())
        record(address: 0x20000, size: 8)
        record(address: 0x30000, size: 4)
        dd_memory_profiler_remove_for_testing(UnsafeRawPointer(bitPattern: 0x30000))
        profiler.captureWindow()
        drain()
        XCTAssertEqual(diagnostics.captures_count, 1)

        receive(context: context(sessionID: UUID()), on: profiler)
        drain()
        XCTAssertEqual(diagnostics.captures_count, 2)
        XCTAssertEqual(diagnostics.alloc_space, 12)
        XCTAssertEqual(diagnostics.inuse_space, 24)
        let origin = dd_memory_profiler_window_start_time_nanos()

        record(address: 0x40000, size: 2)
        profiler.captureWindow()
        drain()
        XCTAssertEqual(diagnostics.captures_count, 3)
        XCTAssertEqual(diagnostics.time_nanos, origin)
        XCTAssertEqual(diagnostics.alloc_space, 2)
        XCTAssertEqual(diagnostics.inuse_space, 26)
    }

    func testSessionBoundaryDiscardsBackgroundDeltaBeforeRecordingNextSession() {
        let nextSession = UUID()
        let profiler = makeRuntimeProfiler()
        receive(context: context(), on: profiler)
        receive(context: context(state: .background), on: profiler)
        drain()
        record(size: 16)
        receive(context: context(sessionID: nextSession, state: .background), on: profiler)
        profiler.captureWindow()
        drain()

        XCTAssertEqual(profiler.state, .emissionSuspended)
        XCTAssertEqual(diagnostics.captures_count, 2)
        XCTAssertEqual(diagnostics.alloc_space, 16)
        XCTAssertEqual(diagnostics.inuse_space, 16)
        let nextOrigin = dd_memory_profiler_window_start_time_nanos()

        record(address: 0x20000, size: 8)
        receive(context: context(sessionID: nextSession), on: profiler)
        profiler.captureWindow()
        drain()

        XCTAssertEqual(diagnostics.captures_count, 3)
        XCTAssertEqual(diagnostics.time_nanos, nextOrigin)
        XCTAssertEqual(diagnostics.alloc_space, 8)
        XCTAssertEqual(diagnostics.inuse_space, 24)
    }

    func testNewBackgroundSessionDoesNotInheritPriorSessionForegroundEligibility() {
        let nextSession = UUID()
        let profiler = makeRuntimeProfiler()
        receive(context: context(), on: profiler)
        drain()
        record()
        receive(context: context(sessionID: nextSession, state: .background), on: profiler)
        profiler.captureWindow()
        drain()

        XCTAssertEqual(profiler.state, .emissionSuspended)
        XCTAssertEqual(diagnostics.captures_count, 1, "The prior session must be the only window closed")
        XCTAssertEqual(diagnostics.alloc_space, 16)
        receive(context: context(sessionID: nextSession), on: profiler)
        profiler.captureWindow()
        drain()
        XCTAssertEqual(diagnostics.captures_count, 2)
        XCTAssertEqual(diagnostics.inuse_space, 16)
    }

    func testSessionSampleOutWhileEmissionSuspendedKeepsRecording() {
        let profiler = makeRuntimeProfiler()
        receive(context: context(), on: profiler)
        receive(context: context(state: .background), on: profiler)
        drain()
        record()
        receive(context: context(sessionID: UUID(), sampleRate: 0, state: .background), on: profiler)
        drain()

        XCTAssertEqual(profiler.state, .emissionSuspended)
        XCTAssertTrue(dd_memory_profiler_is_running())
        XCTAssertEqual(diagnostics.captures_count, 2)
        XCTAssertEqual(diagnostics.alloc_space, 16)
    }

    func testSampledInSessionRetainsBackgroundLiveSetFromSampledOutSession() {
        let profiler = makeRuntimeProfiler()
        receive(context: context(sampleRate: 0, state: .background), on: profiler)
        drain()
        XCTAssertEqual(profiler.state, .emissionSuspended)
        XCTAssertTrue(dd_memory_profiler_is_running())
        record(size: 16)

        let nextSession = UUID()
        receive(context: context(sessionID: nextSession, state: .background), on: profiler)
        profiler.captureWindow()
        drain()

        XCTAssertEqual(profiler.state, .emissionSuspended)
        XCTAssertTrue(dd_memory_profiler_is_running())
        XCTAssertEqual(diagnostics.captures_count, 1)
        XCTAssertEqual(diagnostics.alloc_space, 16)
        record(address: 0x20000, size: 8)
        receive(context: context(sessionID: nextSession), on: profiler)
        profiler.captureWindow()
        drain()
        XCTAssertEqual(diagnostics.captures_count, 2)
        XCTAssertEqual(diagnostics.alloc_space, 8)
        XCTAssertEqual(diagnostics.inuse_space, 24)
    }

    func testRUMGapKeepsLiveObjectsAndIsolatesUnattributedAllocations() {
        let profiler = makeRuntimeProfiler()
        receive(context: context(), on: profiler)
        drain()
        record(size: 16)
        receive(context: context(hasRUM: false), on: profiler)
        profiler.captureWindow()
        receive(context: context(hasRUM: false), on: profiler)
        drain()

        XCTAssertEqual(profiler.state, .waiting)
        XCTAssertTrue(dd_memory_profiler_is_running())
        XCTAssertEqual(diagnostics.captures_count, 1)
        XCTAssertEqual(diagnostics.alloc_space, 16)
        record(address: 0x20000, size: 8)

        receive(context: context(), on: profiler)
        drain()
        XCTAssertEqual(profiler.state, .running)
        XCTAssertEqual(diagnostics.captures_count, 2)
        XCTAssertEqual(diagnostics.alloc_space, 8)
        XCTAssertEqual(diagnostics.inuse_space, 24)
        let origin = dd_memory_profiler_window_start_time_nanos()

        record(address: 0x30000, size: 4)
        profiler.captureWindow()
        drain()
        XCTAssertEqual(diagnostics.captures_count, 3)
        XCTAssertEqual(diagnostics.time_nanos, origin)
        XCTAssertEqual(diagnostics.alloc_space, 4)
        XCTAssertEqual(diagnostics.inuse_space, 28)
    }

    func testConsentRevocationClearsLiveSetAndRecoveryRecordsSampledOutSession() {
        for consent in [TrackingConsent.pending, .granted] {
            dd_memory_profiler_configure_for_testing(DD_MEMORY_TEST_HOOKS_SUCCEED)
            do {
                let profiler = makeProfiler()
                receive(context: context(), on: profiler)
                drain()
                record(size: 16)
                receive(context: context(consent: .notGranted), on: profiler)
                drain()
                XCTAssertEqual(profiler.state, .stopped)
                XCTAssertFalse(dd_memory_profiler_is_running())
                XCTAssertEqual(diagnostics.captures_count, 0)

                receive(context: context(sampleRate: 0, consent: consent), on: profiler)
                drain()
                XCTAssertEqual(profiler.state, .running)
                XCTAssertTrue(dd_memory_profiler_is_running())
                record(address: 0x20000, size: 8)
                profiler.captureWindow()
                drain()
                XCTAssertEqual(diagnostics.captures_count, 0)

                receive(context: context(sessionID: UUID(), consent: consent), on: profiler)
                drain()
                XCTAssertEqual(diagnostics.captures_count, 1)
                XCTAssertEqual(diagnostics.alloc_space, 8)
                XCTAssertEqual(diagnostics.inuse_space, 8)
                record(address: 0x30000, size: 4)
                profiler.captureWindow()
                drain()
                XCTAssertEqual(profiler.state, .running)
                XCTAssertEqual(diagnostics.alloc_space, 4)
                XCTAssertEqual(diagnostics.inuse_space, 12)
            }
        }
    }

    func testConsentRevocationWhileEmissionSuspendedStopsRecordingWithoutCapture() {
        let profiler = makeRuntimeProfiler()
        receive(context: context(), on: profiler)
        receive(context: context(state: .background), on: profiler)
        receive(context: context(consent: .notGranted, state: .background), on: profiler)
        profiler.captureWindow()
        drain()

        XCTAssertEqual(profiler.state, .stopped)
        XCTAssertFalse(dd_memory_profiler_is_running())
        XCTAssertEqual(diagnostics.captures_count, 1)
    }

    func testPendingOrGrantedConsentRestartsBackgroundRecordingAfterRevocation() {
        for consent in [TrackingConsent.pending, .granted] {
            dd_memory_profiler_configure_for_testing(DD_MEMORY_TEST_HOOKS_SUCCEED)
            do {
                let profiler = makeProfiler()
                receive(context: context(state: .background), on: profiler)
                receive(context: context(consent: .notGranted, state: .background), on: profiler)
                drain()
                XCTAssertEqual(profiler.state, .stopped)
                XCTAssertFalse(dd_memory_profiler_is_running())

                receive(context: context(consent: consent, state: .background), on: profiler)
                profiler.captureWindow()
                drain()

                XCTAssertEqual(profiler.state, .emissionSuspended)
                XCTAssertTrue(dd_memory_profiler_is_running())
                XCTAssertFalse(dd_memory_profiler_is_paused())
                XCTAssertEqual(diagnostics.captures_count, 0)
                record()
                receive(context: context(consent: consent), on: profiler)
                profiler.captureWindow()
                drain()
                XCTAssertEqual(diagnostics.alloc_space, 16)
            }
        }
    }

    func testAdoptionKeepsNativeLaunchOriginAndTTIDCapturesOnlyOnce() {
        XCTAssertTrue(dd_memory_profiler_start())
        let launchOrigin = dd_memory_profiler_window_start_time_nanos()
        record()
        let profiler = makeProfiler()
        XCTAssertEqual(dd_memory_profiler_window_start_time_nanos(), launchOrigin)
        receive(context: context(), on: profiler)
        receiveTTID(on: profiler)
        receiveTTID(on: profiler)
        drain()

        XCTAssertEqual(diagnostics.captures_count, 1)
        XCTAssertEqual(diagnostics.time_nanos, launchOrigin)
        XCTAssertEqual(diagnostics.alloc_space, 16)
    }

    func testTTIDBeforeSessionDecisionClosesAtTTIDWithoutRecaptureAfterDecision() {
        let profiler = makeProfiler()
        record()
        receiveTTID(on: profiler)
        drain()
        let launch = diagnostics
        XCTAssertEqual(launch.captures_count, 1)
        XCTAssertEqual(launch.last_status, DD_MEMORY_CAPTURE_READY)

        receive(context: context(), on: profiler)
        drain()
        XCTAssertEqual(diagnostics.captures_count, 1)
        XCTAssertEqual(diagnostics.time_nanos, launch.time_nanos)
        XCTAssertEqual(diagnostics.duration_nanos, launch.duration_nanos)
        XCTAssertEqual(profiler.state, .running)
    }

    func testTTIDCaptureFailureBeforeSessionDecisionStopsRecordingWithoutRetry() {
        let profiler = makeProfiler()
        record()
        dd_memory_profiler_fail_next_capture_for_testing()
        receiveTTID(on: profiler)
        drain()

        XCTAssertEqual(profiler.state, .failed)
        XCTAssertFalse(dd_memory_profiler_is_running())
        XCTAssertEqual(diagnostics.captures_count, 1)
        XCTAssertEqual(diagnostics.last_status, DD_MEMORY_CAPTURE_FAILED)

        receive(context: context(), on: profiler)
        receiveTTID(on: profiler)
        profiler.captureWindow()
        drain()
        XCTAssertEqual(profiler.state, .failed)
        XCTAssertFalse(dd_memory_profiler_is_running())
        XCTAssertEqual(diagnostics.captures_count, 1)
    }

    func testIdleTTIDBeforeSessionDecisionIsNotRecaptured() {
        let profiler = makeProfiler()
        receiveTTID(on: profiler)
        drain()
        XCTAssertEqual(diagnostics.captures_count, 1)
        XCTAssertEqual(diagnostics.last_status, DD_MEMORY_CAPTURE_IDLE)
        XCTAssertEqual(profiler.state, .waiting)

        record()
        receiveTTID(on: profiler)
        receive(context: context(), on: profiler)
        receiveTTID(on: profiler)
        drain()
        XCTAssertEqual(profiler.state, .running)
        XCTAssertEqual(diagnostics.captures_count, 1)

        profiler.captureWindow()
        drain()
        XCTAssertEqual(diagnostics.captures_count, 2)
        XCTAssertEqual(diagnostics.last_status, DD_MEMORY_CAPTURE_READY)
        XCTAssertEqual(diagnostics.alloc_space, 16)
        XCTAssertEqual(diagnostics.inuse_space, 16)
    }

    func testPendingLaunchResolvesBeforeClosingBackgroundWindow() {
        let profiler = makeProfiler()
        record()
        receiveTTID(on: profiler)
        drain()
        let nextOrigin = dd_memory_profiler_window_start_time_nanos()
        receive(context: context(state: .background, hadForeground: true), on: profiler)
        drain()

        XCTAssertEqual(diagnostics.captures_count, 2)
        XCTAssertEqual(diagnostics.time_nanos, nextOrigin)
        XCTAssertEqual(diagnostics.alloc_space, 0)
        XCTAssertEqual(diagnostics.inuse_space, 16)
        XCTAssertEqual(profiler.state, .emissionSuspended)
    }

    func testPendingLaunchKeepsHistoricalForegroundEligibility() {
        let profiler = makeProfiler()
        let launchOrigin = dd_memory_profiler_window_start_time_nanos()
        record()
        let backgroundDate = Date()
        receiveTTID(on: profiler)
        drain()
        let firstContext: DatadogContext = .mockWith(
            applicationStateHistory: .mockWith(
                initialState: .active,
                date: Date(timeIntervalSince1970: Double(launchOrigin) / 1_000_000_000 - 1),
                transitions: [(state: .background, date: backgroundDate)]
            ),
            batteryStatus: nil,
            additionalContext: [RUMCoreContext.mockWith(sessionID: sessionID)]
        )
        receive(context: firstContext, on: profiler)
        drain()

        XCTAssertEqual(diagnostics.captures_count, 2, "Historical foreground time qualifies the closing continuous window")
        XCTAssertEqual(profiler.state, .emissionSuspended)
    }

    func testPendingLaunchIsDiscardedWhenSessionIsSampledOut() {
        let profiler = makeProfiler()
        record()
        receiveTTID(on: profiler)
        receive(context: context(sampleRate: 0), on: profiler)
        drain()

        XCTAssertEqual(diagnostics.captures_count, 1)
        XCTAssertEqual(profiler.state, .running)
        XCTAssertTrue(dd_memory_profiler_is_running())
        receive(context: context(sessionID: UUID()), on: profiler)
        profiler.captureWindow()
        drain()
        XCTAssertEqual(diagnostics.inuse_space, 16)
        XCTAssertEqual(diagnostics.alloc_space, 0)
    }

    func testWindowRequestWhileAwaitingFirstSessionKeepsRecording() {
        let profiler = makeProfiler()
        let origin = dd_memory_profiler_window_start_time_nanos()
        record()
        profiler.captureWindow()
        receive(context: context(hasRUM: false), on: profiler)
        drain()

        XCTAssertEqual(profiler.state, .waiting)
        XCTAssertTrue(dd_memory_profiler_is_running())
        XCTAssertEqual(dd_memory_profiler_window_start_time_nanos(), origin)
        XCTAssertEqual(diagnostics.captures_count, 0)
    }

    func testBackgroundKeepsLaunchOpenUntilFirstSessionDecision() {
        let profiler = makeProfiler()
        receive(context: context(state: .background, hasRUM: false), on: profiler)
        profiler.captureWindow()
        receive(context: context(hasRUM: false), on: profiler)
        profiler.captureWindow()
        drain()

        XCTAssertEqual(profiler.state, .waiting)
        XCTAssertTrue(dd_memory_profiler_is_running())
        XCTAssertFalse(dd_memory_profiler_is_paused())
        XCTAssertEqual(diagnostics.captures_count, 0)
    }

    func testLowPowerKeepsLaunchOpenUntilFirstSessionDecision() {
        let profiler = makeProfiler()
        receive(context: context(lowPower: true, hasRUM: false), on: profiler)
        profiler.captureWindow()
        drain()

        XCTAssertEqual(profiler.state, .emissionSuspended)
        XCTAssertTrue(dd_memory_profiler_is_running())
        XCTAssertFalse(dd_memory_profiler_is_paused())
        XCTAssertEqual(diagnostics.captures_count, 0)
    }

    func testConsentRecoveryWithoutRUMRestartsRecordingBeforeSessionDecision() {
        let profiler = makeProfiler()
        record(size: 16)
        receive(context: context(consent: .notGranted, state: .background, hasRUM: false), on: profiler)
        drain()
        XCTAssertEqual(profiler.state, .stopped)
        XCTAssertFalse(dd_memory_profiler_is_running())

        receive(context: context(consent: .pending, state: .background, hasRUM: false), on: profiler)
        profiler.captureWindow()
        drain()
        XCTAssertTrue(dd_memory_profiler_is_running())
        XCTAssertEqual(profiler.state, .emissionSuspended)
        record(address: 0x20000, size: 8)
        receive(context: context(consent: .pending, state: .background, hasRUM: false), on: profiler)
        drain()
        XCTAssertEqual(diagnostics.captures_count, 0)

        receive(context: context(), on: profiler)
        drain()
        XCTAssertEqual(profiler.state, .running)
        XCTAssertTrue(dd_memory_profiler_is_running())
        XCTAssertEqual(diagnostics.captures_count, 1)
        XCTAssertEqual(diagnostics.alloc_space, 8)
        XCTAssertEqual(diagnostics.inuse_space, 8)
        record(address: 0x30000, size: 4)
        profiler.captureWindow()
        drain()
        XCTAssertEqual(diagnostics.captures_count, 2)
        XCTAssertEqual(diagnostics.alloc_space, 4)
        XCTAssertEqual(diagnostics.inuse_space, 12)
    }

    func testWindowRequestDoesNotRecapturePendingLaunchAfterBlockedConditions() {
        let profiler = makeProfiler()
        record()
        receiveTTID(on: profiler)
        receive(context: context(lowPower: true, hasRUM: false), on: profiler)
        profiler.captureWindow()
        drain()

        XCTAssertEqual(profiler.state, .emissionSuspended)
        XCTAssertTrue(dd_memory_profiler_is_running())
        XCTAssertEqual(diagnostics.captures_count, 1)
        let launch = diagnostics

        receive(context: context(), on: profiler)
        drain()
        XCTAssertEqual(profiler.state, .running)
        XCTAssertEqual(diagnostics.captures_count, 1)
        XCTAssertEqual(diagnostics.time_nanos, launch.time_nanos)
        profiler.captureWindow()
        drain()
        XCTAssertEqual(diagnostics.captures_count, 2)
        XCTAssertEqual(diagnostics.inuse_space, 16)
    }

    func testRuntimeBlockerRecoveryBeforeTTIDKeepsWholeLaunchWindow() {
        let profiler = makeProfiler()
        let launchOrigin = dd_memory_profiler_window_start_time_nanos()
        record()
        receive(context: context(lowPower: true, hasRUM: false), on: profiler)
        drain()
        XCTAssertEqual(profiler.state, .emissionSuspended)
        XCTAssertEqual(diagnostics.captures_count, 0)
        XCTAssertEqual(dd_memory_profiler_window_start_time_nanos(), launchOrigin)

        record(address: 0x20000, size: 8)
        receive(context: context(), on: profiler)
        receiveTTID(on: profiler)
        receiveTTID(on: profiler)
        drain()
        XCTAssertEqual(diagnostics.captures_count, 1)
        XCTAssertEqual(diagnostics.time_nanos, launchOrigin)
        XCTAssertEqual(diagnostics.alloc_space, 24)
        XCTAssertEqual(diagnostics.inuse_space, 24)
        let continuousOrigin = dd_memory_profiler_window_start_time_nanos()
        profiler.captureWindow()
        drain()

        XCTAssertEqual(profiler.state, .running)
        XCTAssertEqual(diagnostics.captures_count, 2)
        XCTAssertEqual(diagnostics.time_nanos, continuousOrigin)
        XCTAssertEqual(diagnostics.alloc_space, 0)
        XCTAssertEqual(diagnostics.inuse_space, 24)
    }

    func testRuntimeBlockerDoesNotRecapturePendingLaunchAfterConditionsRecover() {
        let profiler = makeProfiler()
        record()
        receiveTTID(on: profiler)
        receive(context: context(lowPower: true, hasRUM: false), on: profiler)
        receive(context: context(hasRUM: false), on: profiler)
        drain()

        XCTAssertEqual(profiler.state, .waiting)
        XCTAssertEqual(diagnostics.captures_count, 1)
        let launch = diagnostics
        receive(context: context(), on: profiler)
        receiveTTID(on: profiler)
        receiveTTID(on: profiler)
        drain()
        XCTAssertEqual(profiler.state, .running)
        XCTAssertEqual(diagnostics.captures_count, 1)
        XCTAssertEqual(diagnostics.time_nanos, launch.time_nanos)
        XCTAssertEqual(diagnostics.alloc_space, 16)
    }

    func testTTIDDuringUnresolvedRuntimeBlockerCapturesLaunchOnceWhileWaitingForSession() {
        let profiler = makeProfiler()
        receive(context: context(lowPower: true, hasRUM: false), on: profiler)
        drain()
        record()
        receiveTTID(on: profiler)
        drain()

        XCTAssertEqual(profiler.state, .emissionSuspended)
        XCTAssertEqual(diagnostics.captures_count, 1)
        XCTAssertEqual(diagnostics.last_status, DD_MEMORY_CAPTURE_READY)
        XCTAssertEqual(diagnostics.alloc_space, 16)

        receive(context: context(lowPower: true), on: profiler)
        profiler.captureWindow()
        drain()
        XCTAssertEqual(profiler.state, .emissionSuspended)
        XCTAssertEqual(diagnostics.captures_count, 1)
        XCTAssertTrue(dd_memory_profiler_is_running())

        receive(context: context(), on: profiler)
        receiveTTID(on: profiler)
        receiveTTID(on: profiler)
        drain()
        XCTAssertEqual(diagnostics.captures_count, 1)
        profiler.captureWindow()
        drain()
        XCTAssertEqual(diagnostics.captures_count, 2)
        XCTAssertEqual(diagnostics.alloc_space, 0)
        XCTAssertEqual(diagnostics.inuse_space, 16)
    }

    func testConcurrentContextAndWindowRequestsShareOneNativeQueue() {
        let profiler = makeRuntimeProfiler()
        let sessionID = sessionID
        receive(context: context(), on: profiler)
        drain()
        DispatchQueue.concurrentPerform(iterations: 64) { index in
            let activeContext: DatadogContext = .mockWith(
                applicationStateHistory: .mockAppInForeground(),
                batteryStatus: nil,
                additionalContext: [RUMCoreContext.mockWith(sessionID: sessionID)]
            )
            record(address: UInt(0x10000 + index * 0x100), size: 16)
            receive(context: activeContext, on: profiler)
            profiler.captureWindow()
        }
        drain()

        XCTAssertEqual(diagnostics.captures_count, 64)
        XCTAssertGreaterThanOrEqual(diagnostics.ready_count, 1)
        XCTAssertEqual(diagnostics.inuse_objects, 64)
        XCTAssertEqual(diagnostics.inuse_space, 1_024)
        XCTAssertEqual(profiler.state, .running)
    }

    func testOrderlyTerminationFlushesAndDoesNotRestart() {
        let profiler = makeRuntimeProfiler()
        receive(context: context(), on: profiler)
        drain()
        record()
        profiler.flushAndStop()
        XCTAssertEqual(profiler.state, .shutDown)
        XCTAssertFalse(dd_memory_profiler_is_running())
        XCTAssertEqual(diagnostics.captures_count, 1)
        XCTAssertEqual(diagnostics.alloc_space, 16)

        receive(context: context(), on: profiler)
        profiler.captureWindow()
        profiler.flushAndStop()
        drain()
        XCTAssertEqual(profiler.state, .shutDown)
        XCTAssertEqual(diagnostics.captures_count, 1)
    }

    func testTerminationNotificationFlushesSynchronously() {
        let center = NotificationCenter()
        let profiler = makeRuntimeProfiler(notificationCenter: center)
        receive(context: context(), on: profiler)
        drain()
        record()
        center.post(name: ApplicationNotifications.willTerminate, object: nil)

        XCTAssertEqual(profiler.state, .shutDown)
        XCTAssertFalse(dd_memory_profiler_is_running())
        XCTAssertEqual(diagnostics.captures_count, 1)
        XCTAssertEqual(diagnostics.alloc_space, 16)
    }

    func testTerminationNotificationOnProfilerQueueFlushesSynchronously() {
        let center = NotificationCenter()
        let profiler = makeRuntimeProfiler(notificationCenter: center)
        receive(context: context(), on: profiler)
        drain()
        record()
        let completed = expectation(description: "Termination completes on the profiler queue")

        queue.async {
            center.post(name: ApplicationNotifications.willTerminate, object: nil)

            XCTAssertEqual(profiler.state, .shutDown)
            XCTAssertFalse(dd_memory_profiler_is_running())
            let capture = dd_memory_profiler_capture_diagnostics_for_testing()
            XCTAssertEqual(capture.captures_count, 1)
            XCTAssertEqual(capture.alloc_space, 16)
            completed.fulfill()
        }

        wait(for: [completed], timeout: 5)
    }

    func testTerminationCaptureFailureStillPermanentlyShutsDown() {
        let profiler = makeRuntimeProfiler()
        receive(context: context(), on: profiler)
        drain()
        record()
        dd_memory_profiler_fail_next_capture_for_testing()
        profiler.flushAndStop()

        XCTAssertEqual(profiler.state, .shutDown)
        XCTAssertFalse(dd_memory_profiler_is_running())
        XCTAssertEqual(diagnostics.last_status, DD_MEMORY_CAPTURE_FAILED)

        receive(context: context(sessionID: UUID()), on: profiler)
        receiveTTID(on: profiler)
        profiler.captureWindow()
        profiler.flushAndStop()
        drain()

        XCTAssertEqual(profiler.state, .shutDown)
        XCTAssertFalse(dd_memory_profiler_is_running())
        XCTAssertEqual(diagnostics.captures_count, 1)
    }

    func testDeinitializationStopsWithoutFlushing() {
        let center = NotificationCenter()
        var profiler: MemoryProfiler? = makeProfiler(notificationCenter: center)
        weak var releasedProfiler = profiler
        receive(context: context(), on: profiler)
        drain()
        record()
        profiler = nil

        XCTAssertNil(releasedProfiler)
        XCTAssertFalse(dd_memory_profiler_is_running())
        XCTAssertEqual(diagnostics.captures_count, 0)

        XCTAssertTrue(dd_memory_profiler_start())
        record()
        center.post(name: ApplicationNotifications.willTerminate, object: nil)

        XCTAssertTrue(dd_memory_profiler_is_running())
        XCTAssertEqual(diagnostics.captures_count, 0)
    }

    func testInitializationAndDeinitializationOnProfilerQueueStopWithoutFlushing() {
        let queue = queue
        let samplerProvider = profilingSamplerProvider
        let completed = expectation(description: "Profiler is released on its queue")

        queue.async {
            var profiler: MemoryProfiler? = MemoryProfiler(
                profilingSamplerProvider: samplerProvider,
                queue: queue
            )
            XCTAssertEqual(profiler?.state, .waiting)
            var sample = dd_memory_live_sample_t()
            sample.address = UnsafeRawPointer(bitPattern: 0x10000)
            sample.size = 16
            sample.weight = 1
            dd_memory_profiler_record_for_testing(&sample)
            profiler = nil

            XCTAssertFalse(dd_memory_profiler_is_running())
            XCTAssertEqual(dd_memory_profiler_capture_diagnostics_for_testing().captures_count, 0)
            completed.fulfill()
        }

        wait(for: [completed], timeout: 5)
    }

    private var diagnostics: dd_memory_profiler_test_capture_diagnostics_t {
        dd_memory_profiler_capture_diagnostics_for_testing()
    }

    private func makeRuntimeProfiler(
        memorySampleRate: SampleRate = 100,
        dateProvider: DateProvider = SystemDateProvider(),
        notificationCenter: NotificationCenter = NotificationCenter()
    ) -> MemoryProfiler {
        dd_memory_profiler_configure_for_testing(DD_MEMORY_TEST_HOOKS_SUCCEED)
        return makeProfiler(
            memorySampleRate: memorySampleRate,
            dateProvider: dateProvider,
            notificationCenter: notificationCenter
        )
    }

    private func makeProfiler(
        memorySampleRate: SampleRate = 100,
        dateProvider: DateProvider = SystemDateProvider(),
        notificationCenter: NotificationCenter = NotificationCenter()
    ) -> MemoryProfiler {
        profilingSamplerProvider = ProfilingSamplerProvider(
            continuousSampleRate: 0,
            memorySampleRate: memorySampleRate
        )
        return MemoryProfiler(
            profilingSamplerProvider: profilingSamplerProvider,
            queue: queue,
            dateProvider: dateProvider,
            notificationCenter: notificationCenter
        )
    }

    private func context(
        sessionID: UUID? = nil,
        sampleRate: SampleRate = 100,
        consent: TrackingConsent = .pending,
        state: AppState = .active,
        lowPower: Bool = false,
        battery: BatteryStatus? = nil,
        viewID: String = "view",
        hasRUM: Bool = true,
        hadForeground: Bool = false
    ) -> DatadogContext {
        let history: AppStateHistory = hadForeground
            ? .mockWith(initialState: .active, date: Date().addingTimeInterval(-1), transitions: [(state: state, date: Date())])
            : .mockWith(initialState: state, date: Date())
        return .mockWith(
            trackingConsent: consent,
            applicationStateHistory: history,
            batteryStatus: battery,
            isLowPowerModeEnabled: lowPower,
            additionalContext: hasRUM ? [
                RUMCoreContext.mockWith(sessionID: sessionID ?? self.sessionID, sessionSampleRate: sampleRate, viewID: viewID)
            ] : []
        )
    }

    private func receive(context: DatadogContext, on profiler: MemoryProfiler?) {
        guard let profiler else {
            return
        }
        let receiver = CombinedFeatureMessageReceiver([
            ProfilingContextMessageReceiver(profilingSamplerProvider: profilingSamplerProvider),
            profiler
        ])
        _ = receiver.receive(message: .context(context), from: core)
    }

    private func receiveTTID(on profiler: MemoryProfiler) {
        _ = profiler.receive(
            message: .payload(TTIDMessage(attributes: [:], ttid: .mockWith(stepType: nil))),
            from: core
        )
    }

    private func record(address: UInt = 0x10000, size: UInt64 = 16, weight: Double = 1) {
        var sample = dd_memory_live_sample_t()
        sample.address = UnsafeRawPointer(bitPattern: address)
        sample.size = size
        sample.weight = weight
        dd_memory_profiler_record_for_testing(&sample)
    }

    private func drain() {
        queue.sync {}
    }
}

#endif
