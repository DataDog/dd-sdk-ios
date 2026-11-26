/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if !os(watchOS) && !os(macOS)

import XCTest
// swiftlint:disable duplicate_imports
import DatadogMachProfiler.Pprof
import DatadogMachProfiler.Testing
// swiftlint:enable duplicate_imports
import DatadogInternal
import TestUtilities
@testable import DatadogProfiling

final class MemoryProfilerTests: XCTestCase {
    private let queue = DispatchQueue(label: "test.memory-profiler")
    private let core = PassthroughCoreMock()
    private let telemetry = TelemetryMock()
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
        let swiftDiagnostics = dd_swift_alloc_hook_diagnostics()
        let objcDiagnostics = dd_objc_alloc_hook_diagnostics()
        XCTAssertFalse(swiftDiagnostics.is_enabled)
        XCTAssertFalse(objcDiagnostics.is_enabled)

        withExtendedLifetime((NSObject(), ProfilingSamplerProvider(continuousSampleRate: 0))) {}
        record(address: 0x30000, size: 32)
        profiler.captureWindow()
        drain()

        XCTAssertEqual(diagnostics.captures_count, 0)
        XCTAssertEqual(dd_swift_alloc_hook_diagnostics().allocations, swiftDiagnostics.allocations)
        XCTAssertEqual(dd_objc_alloc_hook_diagnostics().allocations, objcDiagnostics.allocations)
        XCTAssertTrue(core.events.isEmpty)
        XCTAssertTrue(core.metadata.isEmpty)
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

    func testSampledOutSessionsDoNotRetainRUMEventAttributes() {
        final class Attribute: Encodable {}

        for (rumRate, memoryRate): (SampleRate, SampleRate) in [(0, 100), (100, 1)] {
            let profiler = makeRuntimeProfiler(memorySampleRate: memoryRate)
            receive(context: context(
                sessionID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                sampleRate: rumRate
            ), on: profiler)
            drain()
            XCTAssertEqual(profilingSamplerProvider.memory.sampled, false)

            var attribute: Attribute? = Attribute()
            weak var retainedAttribute = attribute
            let hang = DurationEvent(id: "hang", type: .error, start: 0, duration: 1)
            let warning = DurationEvent(id: "warning", type: .error, start: 0, duration: 0)
            _ = profiler.receive(message: .payload(AppHangMessage(attributes: ["attribute": attribute!], hang: hang)), from: core)
            _ = profiler.receive(message: .payload(MemoryWarningMessage(attributes: ["attribute": attribute!], warning: warning)), from: core)
            attribute = nil
            drain()

            XCTAssertNil(retainedAttribute)
            XCTAssertEqual(profiler.state, .running)
            XCTAssertTrue(dd_memory_profiler_is_running())
            XCTAssertTrue(core.events.isEmpty)
            withExtendedLifetime(profiler) {}
        }
    }

    func testPendingRUMEventAttributesAreReleasedWhenFirstSessionSamplesOut() {
        final class Attribute: Encodable {}

        let profiler = makeProfiler()
        XCTAssertEqual(profiler.state, .waiting)
        var attribute: Attribute? = Attribute()
        weak var retainedAttribute = attribute
        let hang = DurationEvent(id: "pending-hang", type: .error, start: 0, duration: 1)
        _ = profiler.receive(message: .payload(AppHangMessage(attributes: ["attribute": attribute!], hang: hang)), from: core)
        attribute = nil
        drain()
        XCTAssertNotNil(retainedAttribute)

        receive(context: context(sampleRate: 0), on: profiler)
        drain()

        XCTAssertNil(retainedAttribute)
        XCTAssertTrue(dd_memory_profiler_is_running())
        XCTAssertEqual(diagnostics.captures_count, 0)
        withExtendedLifetime(profiler) {}
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

    func testSuspendedEmissionSkipsRUMEventsAndResumesBufferingAfterRecovery() throws {
        final class Attribute: Encodable {}

        for blocker in ["background", "low-power", "battery"] {
            let profiler = makeRuntimeProfiler()
            receive(context: context(), on: profiler)
            drain()
            record()
            let hang = DurationEvent(id: "foreground-hang", type: .error, start: Date().timeIntervalSince1970.dd.toInt64Nanoseconds, duration: 0)
            _ = profiler.receive(message: .payload(AppHangMessage(attributes: [:], hang: hang)), from: core)
            receive(context: context(
                state: blocker == "background" ? .background : .active,
                lowPower: blocker == "low-power",
                battery: blocker == "battery" ? .mockWith(state: .unplugged, level: 0.05) : nil
            ), on: profiler)
            drain()
            XCTAssertEqual(profiler.state, .emissionSuspended, blocker)
            let writesBeforeRecovery = core.events.count
            let closing = try XCTUnwrap(core.metadata.last as? ProfileAttachments)
            let closingEvents = try XCTUnwrap(JSONSerialization.jsonObject(with: closing.rumEvents) as? [[String: Any]])
            XCTAssertEqual(closingEvents.compactMap { $0["id"] as? String }, [hang.id], blocker)

            record(address: 0x20000, size: 8)
            dd_memory_profiler_remove_for_testing(UnsafeRawPointer(bitPattern: 0x10000))
            var attribute: Attribute? = Attribute()
            weak var retainedAttribute = attribute
            let skippedHang = DurationEvent(id: "suspended-hang", type: .error, start: Date().timeIntervalSince1970.dd.toInt64Nanoseconds, duration: 0)
            let skippedWarning = DurationEvent(id: "suspended-warning", type: .error, start: skippedHang.start, duration: 0)
            _ = profiler.receive(message: .payload(AppHangMessage(attributes: ["attribute": attribute!], hang: skippedHang)), from: core)
            _ = profiler.receive(message: .payload(MemoryWarningMessage(attributes: ["attribute": attribute!], warning: skippedWarning)), from: core)
            attribute = nil
            drain()
            XCTAssertNil(retainedAttribute, blocker)
            XCTAssertTrue(dd_memory_profiler_is_running(), blocker)
            XCTAssertEqual(core.events.count, writesBeforeRecovery, blocker)

            receive(context: context(), on: profiler)
            let resumed = DurationEvent(id: "resumed-warning", type: .error, start: Date().timeIntervalSince1970.dd.toInt64Nanoseconds, duration: 0)
            _ = profiler.receive(message: .payload(MemoryWarningMessage(attributes: [:], warning: resumed)), from: core)
            profiler.captureWindow()
            drain()
            XCTAssertEqual(core.events.count, writesBeforeRecovery + 1, blocker)
            XCTAssertEqual(diagnostics.alloc_space, 8, blocker)
            XCTAssertEqual(diagnostics.inuse_space, 8, blocker)
            let attachments = try XCTUnwrap(core.metadata.last as? ProfileAttachments)
            let events = try XCTUnwrap(JSONSerialization.jsonObject(with: attachments.rumEvents) as? [[String: Any]])
            XCTAssertEqual(events.compactMap { $0["id"] as? String }, [resumed.id], blocker)
            withExtendedLifetime(profiler) {}
        }
    }

    func testSuspensionReleasesUnresolvedRuntimeCorrelations() {
        final class Attribute: Encodable {}

        let profiler = makeRuntimeProfiler()
        receive(context: context(hasRUM: false), on: profiler)
        drain()
        var attribute: Attribute? = Attribute()
        weak var retainedAttribute = attribute
        let warning = DurationEvent(id: "pending-warning", type: .error, start: 0, duration: 0)
        _ = profiler.receive(message: .payload(MemoryWarningMessage(attributes: ["attribute": attribute!], warning: warning)), from: core)
        attribute = nil
        drain()
        XCTAssertNotNil(retainedAttribute)

        receive(context: context(lowPower: true, hasRUM: false), on: profiler)
        drain()

        XCTAssertEqual(profiler.state, .emissionSuspended)
        XCTAssertNil(retainedAttribute)
        XCTAssertTrue(dd_memory_profiler_is_running())
        withExtendedLifetime(profiler) {}
    }

    func testSuspendedLaunchKeepsCorrelationsUntilTTIDOnly() throws {
        final class Attribute: Encodable {}

        let profiler = makeProfiler()
        receive(context: context(lowPower: true, hasRUM: false), on: profiler)
        drain()
        record()
        let hang = DurationEvent(id: "launch-hang", type: .error, start: Date().timeIntervalSince1970.dd.toInt64Nanoseconds, duration: 0)
        _ = profiler.receive(message: .payload(AppHangMessage(attributes: [:], hang: hang)), from: core)
        receiveTTID(on: profiler)
        drain()
        XCTAssertTrue(core.events.isEmpty)
        receive(context: context(lowPower: true), on: profiler)
        drain()
        let attachments = try XCTUnwrap(core.metadata.first as? ProfileAttachments)
        let events = try XCTUnwrap(JSONSerialization.jsonObject(with: attachments.rumEvents) as? [[String: Any]])
        XCTAssertEqual(events.compactMap { $0["id"] as? String }.first, hang.id)
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(profiler.state, .emissionSuspended)

        var attribute: Attribute? = Attribute()
        weak var retainedAttribute = attribute
        _ = profiler.receive(message: .payload(AppHangMessage(attributes: ["attribute": attribute!], hang: hang)), from: core)
        attribute = nil
        drain()
        XCTAssertNil(retainedAttribute)
        withExtendedLifetime(profiler) {}
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

    func testMissingRUMBeyondFormerSamplingCutoffPreservesLaunchAndLiveObjects() {
        let origin = dd_memory_profiler_window_start_time_nanos()
        record(size: 16)
        let clock = MemoryProfilerMonotonicClockMock()
        let profiler = makeProfiler(dateProvider: DateProviderMock(now: Date().addingTimeInterval(61)), monotonicClock: clock)
        clock.elapsedTime = 61
        drain()

        for index in 0..<3 {
            receive(context: context(state: .background, viewID: "unrelated-\(index)", hasRUM: false), on: profiler)
        }
        drain()

        XCTAssertEqual(profiler.state, .emissionSuspended)
        XCTAssertTrue(dd_memory_profiler_is_running())
        XCTAssertEqual(dd_memory_profiler_window_start_time_nanos(), origin)
        XCTAssertEqual(diagnostics.captures_count, 0)
        XCTAssertTrue(core.events.isEmpty)

        record(address: 0x20000, size: 8)
        receiveTTID(on: profiler)
        drain()
        XCTAssertEqual(diagnostics.ready_count, 1)
        XCTAssertEqual(diagnostics.time_nanos, origin)
        XCTAssertEqual(diagnostics.alloc_space, 24)
        XCTAssertEqual(diagnostics.inuse_space, 24)
        XCTAssertTrue(core.events.isEmpty)

        receive(context: context(), on: profiler)
        drain()
        XCTAssertEqual(profiler.state, .running)
        XCTAssertTrue(dd_memory_profiler_is_running())
        XCTAssertEqual(diagnostics.captures_count, 1)
        XCTAssertEqual(core.events.count, 1)
        withExtendedLifetime(profiler) {}
    }

    func testConsentRecoveryWithoutRUMBeyondFormerSamplingCutoffKeepsLiveObjects() {
        let clock = MemoryProfilerMonotonicClockMock()
        let profiler = makeProfiler(dateProvider: DateProviderMock(now: Date().addingTimeInterval(61)), monotonicClock: clock)
        clock.elapsedTime = 61
        drain()
        receive(context: context(consent: .notGranted, state: .background, hasRUM: false), on: profiler)
        drain()
        XCTAssertFalse(dd_memory_profiler_is_running())

        receive(context: context(consent: .pending, state: .background, hasRUM: false), on: profiler)
        drain()
        let origin = dd_memory_profiler_window_start_time_nanos()
        record(size: 16)
        receive(context: context(consent: .granted, state: .background, lowPower: true, hasRUM: false), on: profiler)
        drain()

        XCTAssertEqual(profiler.state, .emissionSuspended)
        XCTAssertTrue(dd_memory_profiler_is_running())
        XCTAssertEqual(dd_memory_profiler_window_start_time_nanos(), origin)
        XCTAssertEqual(diagnostics.captures_count, 0)
        XCTAssertTrue(core.events.isEmpty)

        receive(context: context(), on: profiler)
        drain()
        XCTAssertEqual(diagnostics.ready_count, 1)
        XCTAssertEqual(diagnostics.inuse_space, 16)
        XCTAssertTrue(core.events.isEmpty)

        record(address: 0x20000, size: 8)
        let warning = DurationEvent(id: "recovered-warning", type: .error, start: Date().timeIntervalSince1970.dd.toInt64Nanoseconds, duration: 0)
        _ = profiler.receive(message: .payload(MemoryWarningMessage(attributes: [:], warning: warning)), from: core)
        profiler.captureWindow()
        drain()
        XCTAssertEqual(diagnostics.ready_count, 2)
        XCTAssertEqual(diagnostics.alloc_space, 8)
        XCTAssertEqual(diagnostics.inuse_space, 24)
        XCTAssertEqual(core.events.count, 1)
        withExtendedLifetime(profiler) {}
    }

    func testTimerClosesPeriodicWindow() {
        let profiler = makeRuntimeProfiler(profilingInterval: 0.02)
        receive(context: context(), on: profiler)
        drain()
        record()
        let captured = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in dd_memory_profiler_capture_diagnostics_for_testing().ready_count > 0 },
            object: nil
        )
        wait(for: [captured], timeout: 3)
        profiler.flushAndStop()

        XCTAssertEqual(profiler.state, .shutDown)
        XCTAssertFalse(dd_memory_profiler_is_running())
        XCTAssertGreaterThanOrEqual(diagnostics.ready_count, 1)
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
        let writer = ProfileWriter(featureScope: core)
        let scheduler = ProfilingScheduler(writer: writer)
        let completed = expectation(description: "Profiler is released on its queue")

        queue.async {
            var profiler: MemoryProfiler? = MemoryProfiler(
                profilingSamplerProvider: samplerProvider,
                writer: writer,
                scheduler: scheduler,
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

    func testPeriodicCaptureBeforeTTIDPreservesLaunchWindow() {
        let profiler = makeProfiler()
        let origin = dd_memory_profiler_window_start_time_nanos()
        receive(context: context(), on: profiler)
        drain()
        record(size: 16)
        let completed = expectation(description: "Periodic launch capture skipped")
        completed.assertForOverFulfill = true

        profiler.captureSnapshot(scheduledFor: .now()) { snapshot in
            XCTAssertNil(snapshot)
            completed.fulfill()
        }
        wait(for: [completed], timeout: 2)
        drain()

        XCTAssertTrue(dd_memory_profiler_is_running())
        XCTAssertEqual(dd_memory_profiler_window_start_time_nanos(), origin)
        XCTAssertEqual(diagnostics.captures_count, 0)
        XCTAssertTrue(core.events.isEmpty)

        receiveTTID(on: profiler)
        drain()
        XCTAssertEqual(diagnostics.captures_count, 1)
        XCTAssertEqual(diagnostics.time_nanos, origin)
        XCTAssertEqual(diagnostics.alloc_space, 16)
        withExtendedLifetime(profiler) {}
    }

    func testSharedTimerPreservesLaunchThenCapturesAfterTTIDWithoutContextUpdate() {
        let profiler = makeProfiler(profilingInterval: 0.02)
        let origin = dd_memory_profiler_window_start_time_nanos()
        let launchWritten = expectation(description: "Launch profile written at TTID")
        let periodicWritten = expectation(description: "Next periodic window written without another context")
        let writes = ReadWriteLock<Int>(wrappedValue: 0)
        core.onEventWriteContext = { _ in
            var count = 0
            writes.mutate { $0 += 1; count = $0 }
            if count == 1 { launchWritten.fulfill() }
            if count == 2 { periodicWritten.fulfill() }
        }
        receive(context: context(), on: profiler)
        drain()
        record(size: 16)
        let ticksElapsed = expectation(description: "Several shared ticks pass before TTID")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) { ticksElapsed.fulfill() }
        wait(for: [ticksElapsed], timeout: 2)
        drain()

        XCTAssertEqual(diagnostics.captures_count, 0)
        XCTAssertEqual(dd_memory_profiler_window_start_time_nanos(), origin)
        XCTAssertTrue(core.events.isEmpty)

        receiveTTID(on: profiler)
        wait(for: [launchWritten], timeout: 2)
        drain()
        record(address: 0x20000, size: 8)
        let warning = DurationEvent(id: "after-ttid", type: .error, start: Date().timeIntervalSince1970.dd.toInt64Nanoseconds, duration: 0)
        _ = profiler.receive(message: .payload(MemoryWarningMessage(attributes: [:], warning: warning)), from: core)
        wait(for: [periodicWritten], timeout: 3)

        XCTAssertEqual(core.events.count, 2)
        XCTAssertGreaterThanOrEqual(diagnostics.ready_count, 2)
        XCTAssertEqual(diagnostics.inuse_space, 24)
        XCTAssertTrue(dd_memory_profiler_is_running())
        profiler.flushAndStop()
        withExtendedLifetime(profiler) {}
    }

    func testSharedTimerFallsBackWithoutTTIDAndRetainsLiveObjectsAfterLateTTID() throws {
        let dateProvider = DateProviderMock(now: Date())
        let clock = MemoryProfilerMonotonicClockMock()
        let profiler = makeProfiler(profilingInterval: 0.02, dateProvider: dateProvider, monotonicClock: clock)
        let origin = dd_memory_profiler_window_start_time_nanos()
        let firstWritten = expectation(description: "Missing TTID falls back on shared tick")
        let secondWritten = expectation(description: "Next periodic profile retains earlier live objects")
        let writes = ReadWriteLock<Int>(wrappedValue: 0)
        core.onEventWriteContext = { _ in
            var count = 0
            writes.mutate { $0 += 1; count = $0 }
            if count == 1 { firstWritten.fulfill() }
            if count == 2 { secondWritten.fulfill() }
        }
        receive(context: context(), on: profiler)
        drain()
        record(size: 16)
        let firstWarning = DurationEvent(
            id: "fallback-warning",
            type: .error,
            start: Date().timeIntervalSince1970.dd.toInt64Nanoseconds,
            duration: 0
        )
        _ = profiler.receive(message: .payload(MemoryWarningMessage(attributes: [:], warning: firstWarning)), from: core)
        let ticksElapsed = expectation(description: "Shared ticks preserve launch before timeout")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) { ticksElapsed.fulfill() }
        wait(for: [ticksElapsed], timeout: 2)
        drain()
        XCTAssertEqual(diagnostics.captures_count, 0)
        XCTAssertEqual(dd_memory_profiler_window_start_time_nanos(), origin)
        XCTAssertTrue(core.events.isEmpty)

        clock.elapsedTime = 61
        wait(for: [firstWritten], timeout: 3)
        record(address: 0x20000, size: 8)
        receiveTTID(on: profiler)
        let secondWarning = DurationEvent(
            id: "after-fallback",
            type: .error,
            start: Date().timeIntervalSince1970.dd.toInt64Nanoseconds,
            duration: 0
        )
        _ = profiler.receive(message: .payload(MemoryWarningMessage(attributes: [:], warning: secondWarning)), from: core)
        wait(for: [secondWritten], timeout: 3)

        XCTAssertEqual(core.events.count, 2)
        XCTAssertTrue(core.events(ofType: ProfileEvent.self).allSatisfy { $0.tags.contains("operation:trigger") })
        let attachments = core.metadata(ofType: ProfileAttachments.self)
        XCTAssertEqual(attachments.count, 2)
        for (attachment, warning) in zip(attachments, [firstWarning, secondWarning]) {
            let events = try XCTUnwrap(JSONSerialization.jsonObject(with: attachment.rumEvents) as? [[String: Any]])
            XCTAssertEqual(events.compactMap { $0["id"] as? String }, [warning.id])
        }
        XCTAssertEqual(diagnostics.inuse_space, 24)
        XCTAssertTrue(dd_memory_profiler_is_running())
        profiler.flushAndStop()
        withExtendedLifetime(profiler) {}
    }

    func testLaunchFallbackAtSixtySecondsSkipsUncorrelatedWriteAndIgnoresLateTTID() {
        let origin = dd_memory_profiler_window_start_time_nanos()
        let launchDate = Date(timeIntervalSince1970: Double(origin) / 1_000_000_000)
        let dateProvider = DateProviderMock(now: launchDate)
        let clock = MemoryProfilerMonotonicClockMock()
        let profiler = makeProfiler(dateProvider: dateProvider, monotonicClock: clock)
        var profileContext = context()
        profileContext.serverTimeOffset = 120
        receive(context: profileContext, on: profiler)
        drain()
        record(size: 16)
        clock.elapsedTime = 59
        dateProvider.now = launchDate.addingTimeInterval(3_600)
        profiler.captureWindow()
        drain()
        XCTAssertEqual(diagnostics.captures_count, 0)
        XCTAssertEqual(dd_memory_profiler_window_start_time_nanos(), origin)

        clock.elapsedTime = 60
        dateProvider.now = launchDate.addingTimeInterval(-3_600)
        profiler.captureWindow()
        drain()
        XCTAssertEqual(diagnostics.captures_count, 1)
        XCTAssertEqual(diagnostics.time_nanos, origin)
        XCTAssertEqual(diagnostics.inuse_space, 16)
        XCTAssertTrue(core.events.isEmpty)
        XCTAssertTrue(core.metadata.isEmpty)
        XCTAssertTrue(dd_memory_profiler_is_running())

        let nextOrigin = dd_memory_profiler_window_start_time_nanos()
        record(address: 0x20000, size: 8)
        receiveTTID(on: profiler)
        drain()
        XCTAssertEqual(diagnostics.captures_count, 1)
        XCTAssertEqual(dd_memory_profiler_window_start_time_nanos(), nextOrigin)
        XCTAssertTrue(core.events.isEmpty)

        let warning = DurationEvent(
            id: "after-late-ttid",
            type: .error,
            start: Date().addingTimeInterval(120).timeIntervalSince1970.dd.toInt64Nanoseconds,
            duration: 0
        )
        _ = profiler.receive(message: .payload(MemoryWarningMessage(attributes: [:], warning: warning)), from: core)
        profiler.captureWindow()
        drain()
        XCTAssertEqual(diagnostics.captures_count, 2)
        XCTAssertEqual(diagnostics.alloc_space, 8)
        XCTAssertEqual(diagnostics.inuse_space, 24)
        XCTAssertEqual(core.events.count, 1)
        XCTAssertTrue(core.events(ofType: ProfileEvent.self).first?.tags.contains("operation:trigger") == true)
        withExtendedLifetime(profiler) {}
    }

    func testForwardClockBeforeProfilerInitializationDoesNotExpireLaunch() throws {
        let origin = dd_memory_profiler_window_start_time_nanos()
        record(size: 16)
        let dateProvider = DateProviderMock(
            now: Date(timeIntervalSince1970: Double(origin) / 1_000_000_000).addingTimeInterval(3_600)
        )
        let clock = MemoryProfilerMonotonicClockMock()
        let profiler = makeProfiler(profilingInterval: 0.02, dateProvider: dateProvider, monotonicClock: clock)
        let unexpectedWrite = invertedExpectation(description: "Wall-clock correction does not expire the launch")
        core.onEventWriteContext = { _ in unexpectedWrite.fulfill() }
        receive(context: context(), on: profiler)
        let warning = DurationEvent(id: "late-enable", type: .error, start: Date().timeIntervalSince1970.dd.toInt64Nanoseconds, duration: 0)
        _ = profiler.receive(message: .payload(MemoryWarningMessage(attributes: [:], warning: warning)), from: core)
        wait(for: [unexpectedWrite], timeout: 0.1)
        drain()
        XCTAssertEqual(diagnostics.captures_count, 0)
        XCTAssertEqual(dd_memory_profiler_window_start_time_nanos(), origin)
        XCTAssertTrue(core.events.isEmpty)

        let written = expectation(description: "Elapsed launch grace expires on a shared tick")
        core.onEventWriteContext = { _ in written.fulfill() }
        clock.elapsedTime = 61
        wait(for: [written], timeout: 3)

        let event = try XCTUnwrap(core.events.first as? ProfileEvent)
        XCTAssertEqual(core.events.count, 1)
        XCTAssertEqual(event.start.timeIntervalSince1970, Double(origin) / 1_000_000_000, accuracy: 0.000001)
        XCTAssertTrue(event.tags.contains("operation:trigger"))
        XCTAssertEqual(diagnostics.inuse_space, 16)
        XCTAssertTrue(dd_memory_profiler_is_running())
        profiler.flushAndStop()
        withExtendedLifetime(profiler) {}
    }

    func testBackwardClockBeforeProfilerInitializationPreservesNativeLaunchAge() {
        let origin = dd_memory_profiler_window_start_time_nanos()
        let nativeAge = Double(dd_memory_profiler_window_age_nanos()) / 1_000_000_000
        XCTAssertGreaterThan(nativeAge, 0)
        XCTAssertLessThan(nativeAge, ProfilingScheduler.Constants.profilingInterval)
        let dateProvider = DateProviderMock(
            now: Date(timeIntervalSince1970: Double(origin) / 1_000_000_000).addingTimeInterval(-3_600)
        )
        let clock = MemoryProfilerMonotonicClockMock()
        let profiler = makeProfiler(dateProvider: dateProvider, monotonicClock: clock)
        receive(context: context(), on: profiler)
        drain()
        record(size: 16)

        profiler.captureWindow()
        drain()
        XCTAssertEqual(diagnostics.captures_count, 0)
        XCTAssertEqual(dd_memory_profiler_window_start_time_nanos(), origin)

        clock.elapsedTime = max(0, ProfilingScheduler.Constants.profilingInterval - nativeAge)
        profiler.captureWindow()
        drain()
        XCTAssertEqual(diagnostics.captures_count, 1)
        XCTAssertEqual(diagnostics.time_nanos, origin)
        XCTAssertEqual(diagnostics.inuse_space, 16)
        XCTAssertTrue(core.events.isEmpty)
        XCTAssertTrue(dd_memory_profiler_is_running())

        let nextOrigin = dd_memory_profiler_window_start_time_nanos()
        receiveTTID(on: profiler)
        drain()
        XCTAssertEqual(diagnostics.captures_count, 1)
        XCTAssertEqual(dd_memory_profiler_window_start_time_nanos(), nextOrigin)
        withExtendedLifetime(profiler) {}
    }

    func testExpiredLaunchFallbackRespectsAdmissionAndStaleTicks() {
        let suiteName = "MemoryProfilerTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        for blocker in ["missing-rum", "sampled-out", "suspended", "stale-tick"] {
            dd_memory_profiler_configure_for_testing(DD_MEMORY_TEST_HOOKS_SUCCEED)
            defaults.set(100, forKey: DD_PROFILING_MEMORY_SAMPLE_RATE_KEY)
            dd_memory_profiler_auto_start_for_testing(suiteName, false, false)
            do {
                let origin = dd_memory_profiler_window_start_time_nanos()
                let clock = MemoryProfilerMonotonicClockMock()
                let profiler = makeProfiler(monotonicClock: clock)
                clock.elapsedTime = 61
                let writtenBefore = core.events.count
                receive(context: context(
                    sampleRate: blocker == "sampled-out" ? 0 : 100,
                    lowPower: blocker == "suspended",
                    hasRUM: blocker != "missing-rum"
                ), on: profiler)
                drain()
                record(size: 16)
                let completed = expectation(description: "Expired launch blocked by \(blocker)")
                let scheduled = blocker == "stale-tick" ? DispatchTime(uptimeNanoseconds: 0) : .now()
                profiler.captureSnapshot(scheduledFor: scheduled) { snapshot in
                    XCTAssertNil(snapshot, blocker)
                    completed.fulfill()
                }
                wait(for: [completed], timeout: 2)
                if blocker != "stale-tick" {
                    profiler.captureWindow()
                }
                drain()
                XCTAssertEqual(diagnostics.captures_count, 0, blocker)
                XCTAssertEqual(dd_memory_profiler_window_start_time_nanos(), origin, blocker)
                XCTAssertEqual(core.events.count, writtenBefore, blocker)
                XCTAssertTrue(dd_memory_profiler_is_running(), blocker)

                receiveTTID(on: profiler)
                drain()
                XCTAssertEqual(diagnostics.captures_count, 1, blocker)
                XCTAssertEqual(diagnostics.time_nanos, origin, blocker)
                XCTAssertEqual(diagnostics.inuse_space, 16, blocker)
                withExtendedLifetime(profiler) {}
            }
        }
    }

    func testPeriodicCaptureReturnsOwnedHeapSnapshotWithoutWriting() throws {
        let profiler = makeRuntimeProfiler()
        var capturedContext = context(viewID: "captured-view")
        capturedContext.serverTimeOffset = 2
        receive(context: capturedContext, on: profiler)
        drain()
        record()
        let captured = ReadWriteLock<ProfileSnapshot?>(wrappedValue: nil)
        let completed = expectation(description: "Heap snapshot captured")
        completed.assertForOverFulfill = true
        profiler.captureSnapshot(scheduledFor: .now()) { snapshot in
            captured.wrappedValue = snapshot
            completed.fulfill()
        }
        wait(for: [completed], timeout: 2)
        drain()

        let snapshot = try XCTUnwrap(captured.wrappedValue)
        let start = diagnostics.time_nanos
        XCTAssertTrue(core.events.isEmpty)
        XCTAssertEqual(snapshot.attachment.filename, ProfileAttachments.Constants.heapPprofFilename)
        XCTAssertEqual(snapshot.rumContext?.sessionID, sessionID.uuidString.lowercased())
        XCTAssertEqual(snapshot.rumContext?.viewID, "captured-view")
        XCTAssertTrue(snapshot.rumEvents.isEmpty)

        record(address: 0x20000, size: 32)
        profiler.captureWindow()
        profiler.flushAndStop()

        let decoded = try XCTUnwrap(snapshot.attachment.data.withUnsafeBytes { bytes in
            perftools__profiles__profile__unpack(nil, bytes.count, bytes.bindMemory(to: UInt8.self).baseAddress)
        })
        defer { perftools__profiles__profile__free_unpacked(decoded, nil) }
        XCTAssertGreaterThan(decoded.pointee.n_sample, 0)
        XCTAssertEqual(decoded.pointee.n_sample_type, 4)
        XCTAssertEqual(decoded.pointee.time_nanos, start + 2_000_000_000)
        XCTAssertEqual(snapshot.start.timeIntervalSince1970, Double(decoded.pointee.time_nanos) / 1_000_000_000, accuracy: 0.000001)
        XCTAssertEqual(snapshot.end.timeIntervalSince(snapshot.start), Double(decoded.pointee.duration_nanos) / 1_000_000_000, accuracy: 0.000001)
        withExtendedLifetime(profiler) {}
    }

    func testIndependentCaptureCorrectsServerTimeAndOwnsSerializedBytes() throws {
        let profiler = makeRuntimeProfiler()
        var capturedContext = context(viewID: "captured-view")
        capturedContext.serverTimeOffset = 2
        receive(context: capturedContext, on: profiler)
        drain()
        let localStart = dd_memory_profiler_window_start_time_nanos()
        record()
        let warning = DurationEvent(
            id: "captured-warning",
            type: .error,
            start: Date().addingTimeInterval(2).timeIntervalSince1970.dd.toInt64Nanoseconds,
            duration: 0
        )
        _ = profiler.receive(message: .payload(MemoryWarningMessage(attributes: [:], warning: warning)), from: core)
        profiler.captureWindow()
        drain()

        let event = try XCTUnwrap(core.events.first as? ProfileEvent)
        let attachments = try XCTUnwrap(core.metadata.first as? ProfileAttachments)
        let attachment = try XCTUnwrap(attachments.pprofs.first)
        let events = try XCTUnwrap(JSONSerialization.jsonObject(with: attachments.rumEvents) as? [[String: Any]])
        XCTAssertEqual(core.events.count, 1)
        XCTAssertEqual(attachment.filename, ProfileAttachments.Constants.heapPprofFilename)
        XCTAssertEqual(events.compactMap { $0["id"] as? String }, [warning.id])
        XCTAssertEqual(event.additionalAttributes?[RUMCoreContext.IDs.viewID] as? [String], ["captured-view"])

        // A later serialization and native stop cannot invalidate the first attachment's bytes.
        var laterContext = context(viewID: "later-view")
        laterContext.serverTimeOffset = 5
        receive(context: laterContext, on: profiler)
        record(address: 0x20000, size: 32)
        profiler.captureWindow()
        drain()
        profiler.flushAndStop()

        let decoded = try XCTUnwrap(attachment.data.withUnsafeBytes { bytes in
            perftools__profiles__profile__unpack(nil, bytes.count, bytes.bindMemory(to: UInt8.self).baseAddress)
        })
        defer { perftools__profiles__profile__free_unpacked(decoded, nil) }
        XCTAssertGreaterThan(decoded.pointee.n_sample, 0)
        XCTAssertEqual(decoded.pointee.n_sample_type, 4)
        XCTAssertEqual(decoded.pointee.time_nanos, localStart + 2_000_000_000)
        XCTAssertEqual(event.start.timeIntervalSince1970, Double(decoded.pointee.time_nanos) / 1_000_000_000, accuracy: 0.000001)
        XCTAssertEqual(event.end.timeIntervalSince(event.start), Double(decoded.pointee.duration_nanos) / 1_000_000_000, accuracy: 0.000001)
        XCTAssertFalse(dd_memory_profiler_is_running())
        withExtendedLifetime(profiler) {}
    }

    func testIndependentCaptureWithoutRUMEventsDoesNotWrite() {
        let profiler = makeRuntimeProfiler()
        receive(context: context(viewID: "heap-view"), on: profiler)
        drain()
        record()
        profiler.captureWindow()
        drain()

        XCTAssertEqual(diagnostics.captures_count, 1)
        XCTAssertTrue(core.events.isEmpty)
        XCTAssertTrue(core.metadata.isEmpty)
        withExtendedLifetime(profiler) {}
    }

    func testLastFreeUploadsZeroSampleHeapWithRUMContext() throws {
        let profiler = makeRuntimeProfiler()
        var capturedContext = context(viewID: "empty-heap-view")
        capturedContext.serverTimeOffset = 2
        receive(context: capturedContext, on: profiler)
        drain()
        record()
        profiler.captureWindow()
        drain()
        XCTAssertEqual(diagnostics.sample_count, 1)
        XCTAssertTrue(core.events.isEmpty)

        let localStart = dd_memory_profiler_window_start_time_nanos()
        dd_memory_profiler_remove_for_testing(UnsafeRawPointer(bitPattern: 0x10000))
        let warning = DurationEvent(
            id: "last-free-warning",
            type: .error,
            start: Date().addingTimeInterval(2).timeIntervalSince1970.dd.toInt64Nanoseconds,
            duration: 0
        )
        _ = profiler.receive(message: .payload(MemoryWarningMessage(attributes: [:], warning: warning)), from: core)
        profiler.captureWindow()
        drain()

        XCTAssertEqual(diagnostics.ready_count, 2)
        XCTAssertEqual(diagnostics.sample_count, 0)
        XCTAssertEqual(core.events.count, 1)
        let event = try XCTUnwrap(core.events.first as? ProfileEvent)
        let attachments = try XCTUnwrap(core.metadata.first as? ProfileAttachments)
        let encoder = JSONEncoder.dd.default()
        let storedEvent = try Event(data: encoder.encode(event), metadata: encoder.encode(attachments))
        let multipart = MultipartBuilderSpy()
        _ = try RequestBuilder(multipartBuilder: multipart).request(for: [storedEvent], with: capturedContext, execution: .mockAny())
        XCTAssertEqual(multipart.formFiles.map(\.filename), ["event.json", "heap.pprof", "rum-mobile-events.json"])
        let heap = try XCTUnwrap(multipart.formFiles.first { $0.filename == "heap.pprof" })
        let decoded = try XCTUnwrap(heap.data.withUnsafeBytes { bytes in
            perftools__profiles__profile__unpack(nil, bytes.count, bytes.bindMemory(to: UInt8.self).baseAddress)
        })
        defer { perftools__profiles__profile__free_unpacked(decoded, nil) }
        XCTAssertEqual(decoded.pointee.n_sample, 0)
        XCTAssertEqual(decoded.pointee.n_location, 0)
        XCTAssertEqual(decoded.pointee.n_mapping, 0)
        XCTAssertEqual(decoded.pointee.n_sample_type, 4)
        XCTAssertEqual(decoded.pointee.time_nanos, localStart + 2_000_000_000)
        XCTAssertEqual(event.start.timeIntervalSince1970, Double(decoded.pointee.time_nanos) / 1_000_000_000, accuracy: 0.000001)
        XCTAssertEqual(event.end.timeIntervalSince(event.start), Double(decoded.pointee.duration_nanos) / 1_000_000_000, accuracy: 0.000001)
        let uploadedEvent = try XCTUnwrap(JSONSerialization.jsonObject(with: multipart.formFiles[0].data) as? [String: Any])
        let rum = try XCTUnwrap(capturedContext.additionalContext(ofType: RUMCoreContext.self))
        XCTAssertEqual(uploadedEvent[RUMCoreContext.IDs.applicationID] as? String, rum.applicationID)
        XCTAssertEqual(uploadedEvent[RUMCoreContext.IDs.sessionID] as? String, rum.sessionID)
        XCTAssertEqual(uploadedEvent[RUMCoreContext.IDs.viewID] as? [String], ["empty-heap-view"])
        XCTAssertEqual(uploadedEvent[RUMCoreContext.IDs.errorID] as? [String], [warning.id])
        let rumEvents = try XCTUnwrap(JSONSerialization.jsonObject(with: multipart.formFiles[2].data) as? [[String: Any]])
        XCTAssertEqual(rumEvents.compactMap { $0["id"] as? String }, [warning.id])
        for file in multipart.formFiles {
            let attachment = XCTAttachment(data: file.data, uniformTypeIdentifier: "public.data")
            attachment.name = file.filename
            attachment.lifetime = .keepAlways
            add(attachment)
        }

        profiler.captureWindow()
        drain()
        XCTAssertEqual(diagnostics.ready_count, 2)
        XCTAssertEqual(core.events.count, 1)

        withExtendedLifetime(profiler) {}
    }

    func testOldPeriodicTickDoesNotCloseWindowAfterSessionChange() throws {
        let profiler = makeRuntimeProfiler()
        receive(context: context(), on: profiler)
        drain()
        record()
        let hang = DurationEvent(id: "old-session", type: .error, start: Date().timeIntervalSince1970.dd.toInt64Nanoseconds, duration: 0)
        _ = profiler.receive(message: .payload(AppHangMessage(attributes: [:], hang: hang)), from: core)
        let previousTick = DispatchTime.now()
        receive(context: context(sessionID: UUID()), on: profiler)
        let completed = expectation(description: "Stale heap snapshot completed")
        completed.assertForOverFulfill = true
        profiler.captureSnapshot(scheduledFor: previousTick) { snapshot in
            XCTAssertNil(snapshot)
            completed.fulfill()
        }
        wait(for: [completed], timeout: 2)
        drain()

        XCTAssertEqual(diagnostics.captures_count, 1)
        XCTAssertEqual(core.events.count, 1)
        let oldSessionEvent = try XCTUnwrap(core.events.first as? ProfileEvent)
        XCTAssertEqual(oldSessionEvent.additionalAttributes?[RUMCoreContext.IDs.sessionID] as? String, sessionID.uuidString.lowercased())

        withExtendedLifetime(profiler) {}
    }

    func testPendingLaunchWritesCapturedTTIDWithHeapAttachment() throws {
        let profiler = makeProfiler()
        record()
        let beforeTTID = Vital.mockWith(id: "before-ttid", name: "before", stepType: nil, date: Date())
        _ = profiler.receive(message: .payload(OperationMessage(attributes: [:], operation: beforeTTID)), from: core)
        let hang = DurationEvent(id: "launch-hang", type: .error, start: Date().timeIntervalSince1970.dd.toInt64Nanoseconds, duration: 0)
        _ = profiler.receive(message: .payload(AppHangMessage(attributes: [:], hang: hang)), from: core)
        let vital = Vital.mockWith(stepType: nil)
        _ = profiler.receive(message: .payload(TTIDMessage(attributes: [:], ttid: vital)), from: core)
        drain()
        XCTAssertTrue(core.events.isEmpty)
        let afterTTID = Vital.mockWith(id: "after-ttid", name: "after", stepType: nil, date: Date())
        _ = profiler.receive(message: .payload(OperationMessage(attributes: [:], operation: afterTTID)), from: core)
        let warning = DurationEvent(id: "next-warning", type: .error, start: Date().timeIntervalSince1970.dd.toInt64Nanoseconds, duration: 0)
        _ = profiler.receive(message: .payload(MemoryWarningMessage(attributes: [:], warning: warning)), from: core)
        receive(context: context(), on: profiler)
        drain()

        let event = try XCTUnwrap(core.events.first as? ProfileEvent)
        let metadata = try XCTUnwrap(core.metadata.first as? ProfileAttachments)
        let rumData = metadata.rumEvents
        let rumEvents = try XCTUnwrap(JSONSerialization.jsonObject(with: rumData) as? [[String: Any]])
        XCTAssertEqual(core.events.count, 1)
        XCTAssertEqual(metadata.pprofs.map(\.filename), [ProfileAttachments.Constants.heapPprofFilename])
        XCTAssertEqual(rumEvents.compactMap { $0["id"] as? String }, [hang.id, vital.id])
        XCTAssertEqual(event.additionalAttributes?[RUMCoreContext.IDs.vitalID] as? [String], [vital.id])
        XCTAssertEqual(event.additionalAttributes?[RUMCoreContext.IDs.errorID] as? [String], [hang.id])
        XCTAssertEqual(event.additionalAttributes?[RUMCoreContext.IDs.longTaskID] as? [String], [])
        XCTAssertEqual(diagnostics.captures_count, 1)

        record(address: 0x20000)
        profiler.captureWindow()
        drain()
        let next = try XCTUnwrap(core.metadata.last as? ProfileAttachments)
        let nextEvents = try XCTUnwrap(JSONSerialization.jsonObject(with: next.rumEvents) as? [[String: Any]])
        XCTAssertEqual(core.events.count, 2)
        XCTAssertEqual(nextEvents.compactMap { $0["id"] as? String }, [warning.id])
        withExtendedLifetime(profiler) {}
    }

    func testPendingLaunchPreservesSerializedTimeAndLocalForegroundHistory() throws {
        let profiler = makeProfiler()
        let localStart = dd_memory_profiler_window_start_time_nanos()
        record()
        let vital = Vital.mockWith(stepType: nil, date: Date(), serverTimeOffset: 2)
        _ = profiler.receive(message: .payload(TTIDMessage(
            attributes: [RUMCoreContext.IDs.viewID: ["launch-view"]],
            ttid: vital
        )), from: core)
        drain()
        XCTAssertTrue(core.events.isEmpty)

        var firstContext = context(state: .background, viewID: "later-view", hadForeground: true)
        firstContext.serverTimeOffset = 5
        receive(context: firstContext, on: profiler)
        drain()

        let event = try XCTUnwrap(core.events.first as? ProfileEvent)
        let attachments = try XCTUnwrap(core.metadata.first as? ProfileAttachments)
        let pprof = try XCTUnwrap(attachments.pprofs.first?.data)
        let decoded = try XCTUnwrap(pprof.withUnsafeBytes { bytes in
            perftools__profiles__profile__unpack(nil, bytes.count, bytes.bindMemory(to: UInt8.self).baseAddress)
        })
        defer { perftools__profiles__profile__free_unpacked(decoded, nil) }
        XCTAssertEqual(core.events.count, 1)
        XCTAssertEqual(decoded.pointee.time_nanos, localStart + 2_000_000_000)
        XCTAssertEqual(event.start.timeIntervalSince1970, Double(decoded.pointee.time_nanos) / 1_000_000_000, accuracy: 0.000001)
        XCTAssertEqual(event.additionalAttributes?[RUMCoreContext.IDs.viewID] as? [String], ["launch-view"])
        XCTAssertEqual(event.additionalAttributes?[RUMCoreContext.IDs.sessionID] as? String, sessionID.uuidString.lowercased())
        withExtendedLifetime(profiler) {}
    }

    func testTriggeredHeapCaptureIgnoresLongTaskEventsAndAttributes() throws {
        let profiler = makeRuntimeProfiler()
        receive(context: context(), on: profiler)
        drain()
        record()
        let now = Date()
        let start = Vital.mockWith(id: "operation", name: "load", operationKey: "load", stepType: .start, date: now)
        let hang = DurationEvent(id: "hang", type: .error, start: now.timeIntervalSince1970.dd.toInt64Nanoseconds, duration: 0)
        let oldTask = DurationEvent(id: "old-task", type: .longTask, start: 0, duration: 1)
        let task = DurationEvent(id: "task", type: .longTask, start: now.timeIntervalSince1970.dd.toInt64Nanoseconds, duration: 0)
        for message: Any in [
            OperationMessage(attributes: [:], operation: start),
            LongTaskMessage(
                attributes: [RUMCoreContext.IDs.viewID: ["old-task-view"], RUMCoreContext.IDs.viewName: ["Old Task View"]],
                longTask: oldTask
            ),
            LongTaskMessage(
                attributes: [RUMCoreContext.IDs.viewID: ["task-view"], RUMCoreContext.IDs.viewName: ["Task View"], "task.attribute": "ignored"],
                longTask: task
            ),
            AppHangMessage(
                attributes: [RUMCoreContext.IDs.viewID: ["hang-view"], RUMCoreContext.IDs.viewName: ["Hang View"]],
                hang: hang
            )
        ] {
            XCTAssertFalse(profiler.receive(message: .payload(message), from: core))
        }
        profiler.captureWindow()
        drain()

        let attachments = try XCTUnwrap(core.metadata.first as? ProfileAttachments)
        let events = try XCTUnwrap(JSONSerialization.jsonObject(with: attachments.rumEvents) as? [[String: Any]])
        let event = try XCTUnwrap(core.events.first as? ProfileEvent)
        XCTAssertEqual(events.compactMap { $0["id"] as? String }, [hang.id])
        XCTAssertEqual(attachments.pprofs.map(\.filename), [ProfileAttachments.Constants.heapPprofFilename])
        XCTAssertEqual(event.additionalAttributes?[RUMCoreContext.IDs.sessionID] as? String, sessionID.uuidString.lowercased())
        XCTAssertNil(event.additionalAttributes?[RUMCoreContext.IDs.vitalID])
        XCTAssertEqual(event.additionalAttributes?[RUMCoreContext.IDs.errorID] as? [String], [hang.id])
        XCTAssertEqual(event.additionalAttributes?[RUMCoreContext.IDs.longTaskID] as? [String], [])
        XCTAssertEqual(event.additionalAttributes?[RUMCoreContext.IDs.viewID] as? [String], ["hang-view"])
        XCTAssertEqual(event.additionalAttributes?[RUMCoreContext.IDs.viewName] as? [String], ["Hang View"])
        XCTAssertNil(event.additionalAttributes?["task.attribute"])
        XCTAssertTrue(event.tags.contains("operation:trigger"))

        record(address: 0x20000)
        profiler.captureWindow()
        drain()
        XCTAssertEqual(diagnostics.captures_count, 2)
        XCTAssertEqual(core.events.count, 1)
        XCTAssertEqual(core.metadata.count, 1)
        withExtendedLifetime(profiler) {}
    }

    func testPeriodicCaptureCompletesAfterProducerIsReleased() {
        var profiler: MemoryProfiler? = makeRuntimeProfiler()
        receive(context: context(), on: profiler)
        drain()
        let blockerEntered = expectation(description: "Profiler queue blocked")
        let releaseQueue = DispatchSemaphore(value: 0)
        queue.async {
            blockerEntered.fulfill()
            releaseQueue.wait()
        }
        wait(for: [blockerEntered], timeout: 2)
        let completed = expectation(description: "Released heap producer completes")
        completed.assertForOverFulfill = true
        profiler?.captureSnapshot(scheduledFor: .now()) { snapshot in
            XCTAssertNil(snapshot)
            completed.fulfill()
        }
        profiler = nil
        releaseQueue.signal()
        wait(for: [completed], timeout: 2)
        drain()
    }

    func testTelemetryReportsWindowEncodingIdleAndOrderlyStopWithoutDoubleCounting() throws {
        let profiler = makeRuntimeProfiler()
        receive(context: context(), on: profiler)
        drain()
        record()
        profiler.captureWindow()
        profiler.captureWindow()
        drain()
        profiler.flushAndStop()
        profiler.flushAndStop()

        let windows = memoryMetrics
        XCTAssertEqual(windows.map(\.captureResult), [.encoded, .idle, .idle])
        XCTAssertGreaterThan(windows[0].payloadBytes, 0)
        XCTAssertGreaterThan(windows[0].encoderStorageBytes, 0)
        XCTAssertGreaterThan(windows[0].recorderStorageBytes, 0)
        XCTAssertEqual(windows[0].recordedAllocations, 1)
        XCTAssertEqual(windows[1].recordedAllocations, 0)
        XCTAssertEqual(memoryMetrics.reduce(0) { $0 + $1.recordedAllocations }, 1)
    }

    func testNewOwnerDoesNotReportCountersFromThePreviousSDKLifetime() {
        let first = makeProfiler()
        receive(context: context(), on: first)
        drain()
        record()
        first.captureWindow()
        drain()
        first.flushAndStop()

        let second = makeProfiler()
        receive(context: context(), on: second)
        drain()
        record()
        second.captureWindow()
        drain()
        second.flushAndStop()

        XCTAssertEqual(memoryMetrics.reduce(0) { $0 + $1.sampledAllocations }, 2)
        withExtendedLifetime((first, second)) {}
    }

    func testTelemetryReportsBothInterceptionFailuresAsMetrics() throws {
        for failure in [DD_MEMORY_TEST_SWIFT_HOOK_FAILS, DD_MEMORY_TEST_OBJC_HOOK_FAILS] {
            dd_memory_profiler_configure_for_testing(failure)
            let profiler = makeProfiler()
            receive(context: context(), on: profiler)
            receive(context: context(), on: profiler)
            drain()
            let metric = try XCTUnwrap(memoryMetrics.last { $0.captureResult == .startFailed })
            XCTAssertEqual(profiler.state, .failed)
            if failure == DD_MEMORY_TEST_SWIFT_HOOK_FAILS {
                XCTAssertEqual(metric.swiftInstallResult, Int32(DD_SWIFT_ALLOC_HOOK_FAILED_REBIND.rawValue))
                XCTAssertEqual(metric.objcInstallResult, -1)
            } else {
                XCTAssertEqual(metric.objcInstallResult, Int32(DD_OBJC_ALLOC_HOOK_FAILED_INSTALL.rawValue))
            }
        }
        XCTAssertEqual(memoryMetrics.filter { $0.captureResult == .startFailed }.count, 2)
        XCTAssertEqual(telemetry.messages.compactMap(\.asMetric).count, telemetry.messages.count)
    }

    func testTelemetryPreservesCaptureFailureThroughNativeStop() throws {
        let profiler = makeRuntimeProfiler()
        receive(context: context(), on: profiler)
        drain()
        dd_memory_profiler_fail_next_capture_for_testing()
        profiler.captureWindow()
        drain()

        XCTAssertEqual(memoryMetrics.last?.captureResult, .captureFailed)
        XCTAssertEqual(profiler.state, .failed)
        XCTAssertEqual(memoryMetrics.count, 1)
    }

    func testTelemetryEncodesTheFinalFreeInsteadOfSkippingAnEmptyLiveSet() throws {
        let profiler = makeRuntimeProfiler()
        receive(context: context(), on: profiler)
        drain()
        record()
        profiler.captureWindow()
        drain()
        dd_memory_profiler_remove_for_testing(UnsafeRawPointer(bitPattern: 0x10000))
        profiler.captureWindow()
        drain()

        let windows = memoryMetrics
        XCTAssertEqual(windows.map(\.captureResult), [.encoded, .encoded])
        XCTAssertEqual(windows[1].liveOccupancy, 0)
        XCTAssertGreaterThan(windows[1].payloadBytes, 0)
        XCTAssertGreaterThan(windows[1].tombstones, 0)
    }

    func testTelemetryReportsDiscardedSampledOutWindow() {
        let profiler = makeRuntimeProfiler()
        receive(context: context(sampleRate: 0), on: profiler)
        drain()
        record()
        receive(context: context(sessionID: UUID(), sampleRate: 0), on: profiler)
        drain()

        let window = memoryMetrics.last
        XCTAssertEqual(window?.captureResult, .discarded)
        XCTAssertEqual(window?.sampledAllocations, 1)
        XCTAssertEqual(window?.payloadBytes, 0)
        XCTAssertTrue(dd_memory_profiler_is_running())
        withExtendedLifetime(profiler) {}
    }

    func testTelemetryReportsInvalidCaptureTime() {
        let profiler = makeRuntimeProfiler()
        var invalidContext = context()
        invalidContext.serverTimeOffset = -Date().timeIntervalSince1970 - 10
        receive(context: invalidContext, on: profiler)
        drain()
        record()
        profiler.captureWindow()
        drain()

        XCTAssertEqual(memoryMetrics.last?.captureResult, .invalidTime)
        XCTAssertEqual(memoryMetrics.last?.payloadBytes, 0)
        withExtendedLifetime(profiler) {}
    }

    func testTelemetryReportsAllocationLogOverflowAndWindowReset() throws {
        let profiler = makeRuntimeProfiler()
        receive(context: context(), on: profiler)
        drain()
        let capacity = Int(DD_MEMORY_ALLOCATION_WINDOW_CAPACITY)
        for _ in 0..<capacity {
            record()
            dd_memory_profiler_remove_for_testing(UnsafeRawPointer(bitPattern: 0x10000))
        }
        record(address: 0x20000)
        profiler.captureWindow()
        profiler.captureWindow()
        drain()

        let windows = memoryMetrics
        XCTAssertEqual(windows[0].droppedAllocRecords, 1)
        XCTAssertEqual(windows[0].droppedSamples, 0)
        XCTAssertEqual(windows[0].recordedAllocations, UInt64(capacity))
        XCTAssertEqual(windows[1].droppedAllocRecords, 0)
        XCTAssertEqual(windows[1].recordedAllocations, 0)
    }

    func testTelemetryReportsLiveTableOverflowWithoutRepeatingDrops() throws {
        let profiler = makeRuntimeProfiler()
        receive(context: context(), on: profiler)
        drain()
        // Fill all home buckets exactly once before asking the full table to admit another sample.
        var buckets = Set<Int>()
        var candidate: UInt = 0x10000
        while buckets.count < Int(DD_MEMORY_LIVE_SET_CAPACITY) {
            let bucket = dd_memory_live_set_bucket(UnsafeRawPointer(bitPattern: candidate))
            if buckets.insert(bucket).inserted {
                record(address: candidate)
            }
            candidate += 0x10
        }
        record(address: candidate)
        profiler.captureWindow()
        drain()
        record(address: candidate + 0x10)
        profiler.captureWindow()
        drain()

        let windows = memoryMetrics
        XCTAssertEqual(windows[0].droppedSamples, 1)
        XCTAssertEqual(windows[0].peakLiveOccupancy, UInt64(DD_MEMORY_LIVE_SET_CAPACITY))
        XCTAssertEqual(windows[0].maxProbeLength, UInt64(DD_MEMORY_LIVE_SET_MAX_PROBE))
        XCTAssertGreaterThan(windows[0].averageProbeLength, 0)
        XCTAssertEqual(windows[1].droppedSamples, 1)
    }

    func testTelemetryPayloadExcludesCapturedDataAndCustomerAttributes() throws {
        let profiler = makeRuntimeProfiler()
        receive(context: context(), on: profiler)
        drain()
        "PrivateCustomerClass".withCString { name in
            var sample = dd_memory_live_sample_t()
            sample.address = UnsafeRawPointer(bitPattern: 0x123456ab)
            sample.size = 16
            sample.weight = 1
            sample.class_name = name
            sample.frames.0 = 0xdeadbeef
            sample.frame_count = 1
            dd_memory_profiler_record_for_testing(&sample)
        }
        _ = profiler.receive(message: .payload(MemoryWarningMessage(
            attributes: ["private.attribute": "PrivateCustomerValue"],
            warning: .init(id: "PrivateCustomerEvent", type: .error, start: 0, duration: 0)
        )), from: core)
        profiler.captureWindow()
        drain()
        profiler.flushAndStop()

        for metric in memoryMetrics {
            let data = try JSONEncoder().encode(metric)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertEqual(json["capture_result"] as? String, metric.captureResult.rawValue)
            XCTAssertNil(json["outcome"])
            XCTAssertTrue(json.filter { $0.key != "capture_result" }.values.allSatisfy { $0 is NSNumber })
            let text = String(decoding: data, as: UTF8.self)
            for forbidden in ["PrivateCustomer", "private.attribute", "123456ab", "deadbeef", "3735928559", sessionID.uuidString.lowercased()] {
                XCTAssertFalse(text.contains(forbidden), text)
            }
        }
        XCTAssertFalse(memoryMetrics.isEmpty)
    }

    func testAppHangAndMemoryWarningBurstTriggersOneHeapOnlyCapture() throws {
        let profiler = makeRuntimeProfiler()
        receive(context: context(), on: profiler)
        drain()
        record(size: 16)
        let written = expectation(description: "Coalesced event heap written without a periodic tick")
        core.onEventWriteContext = { _ in written.fulfill() }
        let timestamp = Date().timeIntervalSince1970.dd.toInt64Nanoseconds
        let hang = DurationEvent(id: "trigger-hang", type: .error, start: timestamp, duration: 0)
        let warning = DurationEvent(id: "trigger-warning", type: .error, start: timestamp, duration: 0)

        XCTAssertFalse(profiler.receive(message: .payload(AppHangMessage(attributes: [:], hang: hang)), from: core))
        XCTAssertFalse(profiler.receive(message: .payload(MemoryWarningMessage(attributes: [:], warning: warning)), from: core))
        wait(for: [written], timeout: 5)
        drain(after: MemoryProfiler.Constants.eventCaptureDelay + 0.1)

        XCTAssertEqual(diagnostics.captures_count, 1)
        XCTAssertEqual(diagnostics.alloc_space, 16)
        XCTAssertEqual(diagnostics.inuse_space, 16)
        XCTAssertEqual(core.events.count, 1)
        XCTAssertEqual(try rumEventIDs(), [hang.id, warning.id])
        let attachments = try XCTUnwrap(core.metadata.first as? ProfileAttachments)
        XCTAssertEqual(attachments.pprofs.map(\.filename), [ProfileAttachments.Constants.heapPprofFilename])
        let event = try XCTUnwrap(core.events.first as? ProfileEvent)
        XCTAssertEqual(event.additionalAttributes?[RUMCoreContext.IDs.errorID] as? [String], [hang.id, warning.id])
        XCTAssertTrue(event.tags.contains("operation:trigger"))
        withExtendedLifetime(profiler) {}
    }

    func testTTFDAfterTTIDTriggersANewCaptureAndRetainsLaunchSurvivors() throws {
        let profiler = makeProfiler()
        receive(context: context(), on: profiler)
        drain()
        record(size: 16)
        receiveTTID(on: profiler)
        drain()
        XCTAssertEqual(diagnostics.captures_count, 1)
        let launch = try XCTUnwrap(core.events.first as? ProfileEvent)
        XCTAssertTrue(launch.tags.contains("operation:application_launch"))
        record(address: 0x20000, size: 8)
        let written = expectation(description: "TTFD heap written")
        core.onEventWriteContext = { _ in written.fulfill() }
        let ttfd = Vital.mockWith(id: "ttfd", name: "time_to_full_display", stepType: nil, date: Date())

        XCTAssertFalse(profiler.receive(message: .payload(OperationMessage(attributes: [:], operation: ttfd)), from: core))
        wait(for: [written], timeout: 5)
        drain()

        XCTAssertEqual(core.events.count, 2)
        XCTAssertEqual(diagnostics.captures_count, 2)
        XCTAssertEqual(diagnostics.alloc_space, 8)
        XCTAssertEqual(diagnostics.inuse_space, 24)
        XCTAssertEqual(try rumEventIDs(at: 1), [ttfd.id])
        let event = try XCTUnwrap(core.events.last as? ProfileEvent)
        XCTAssertEqual(event.additionalAttributes?[RUMCoreContext.IDs.vitalID] as? [String], [ttfd.id])
        XCTAssertEqual(event.additionalAttributes?[RUMCoreContext.IDs.vitalLabel] as? [String], [ttfd.name])
        XCTAssertTrue(event.tags.contains("operation:trigger"))
        withExtendedLifetime(profiler) {}
    }

    func testTTFDBeforeTTIDJoinsLaunchCaptureWithoutClosingItEarly() throws {
        let profiler = makeProfiler()
        receive(context: context(), on: profiler)
        drain()
        let origin = dd_memory_profiler_window_start_time_nanos()
        record(size: 16)
        let ttfd = Vital.mockWith(id: "early-ttfd", name: "time_to_full_display", stepType: nil, date: Date())
        _ = profiler.receive(message: .payload(OperationMessage(attributes: [:], operation: ttfd)), from: core)
        drain(after: MemoryProfiler.Constants.eventCaptureDelay + 0.1)

        XCTAssertEqual(diagnostics.captures_count, 0)
        XCTAssertEqual(dd_memory_profiler_window_start_time_nanos(), origin)
        XCTAssertTrue(core.events.isEmpty)

        let ttid = Vital.mockWith(id: "ttid", name: "time_to_initial_display", stepType: nil, date: Date())
        _ = profiler.receive(message: .payload(TTIDMessage(attributes: [:], ttid: ttid)), from: core)
        drain(after: MemoryProfiler.Constants.eventCaptureDelay + 0.1)

        XCTAssertEqual(diagnostics.captures_count, 1)
        XCTAssertEqual(diagnostics.time_nanos, origin)
        XCTAssertEqual(diagnostics.alloc_space, 16)
        XCTAssertEqual(core.events.count, 1)
        XCTAssertEqual(try rumEventIDs(), [ttfd.id, ttid.id])
        withExtendedLifetime(profiler) {}
    }

    func testTTFDWhileLaunchAwaitsFirstRUMDecisionCapturesAfterDecision() throws {
        let profiler = makeProfiler()
        record(size: 16)
        receiveTTID(on: profiler)
        drain()
        XCTAssertTrue(core.events.isEmpty)
        XCTAssertEqual(diagnostics.captures_count, 1)
        record(address: 0x20000, size: 8)
        let ttfd = Vital.mockWith(id: "pending-ttfd", name: "time_to_full_display", stepType: nil, date: Date())
        _ = profiler.receive(message: .payload(OperationMessage(attributes: [:], operation: ttfd)), from: core)
        drain()
        let written = expectation(description: "Pending launch and TTFD heaps written")
        written.expectedFulfillmentCount = 2
        core.onEventWriteContext = { _ in written.fulfill() }

        receive(context: context(), on: profiler)
        wait(for: [written], timeout: 5)
        drain()

        XCTAssertEqual(core.events.count, 2)
        XCTAssertEqual(diagnostics.captures_count, 2)
        XCTAssertEqual(diagnostics.alloc_space, 8)
        XCTAssertEqual(diagnostics.inuse_space, 24)
        XCTAssertEqual(try rumEventIDs(at: 1), [ttfd.id])
        withExtendedLifetime(profiler) {}
    }

    func testLongTasksDoNotTriggerOrCorrelateHeapCaptures() throws {
        let profiler = makeRuntimeProfiler()
        receive(context: context(), on: profiler)
        drain()
        record()
        let now = Date()
        let task = DurationEvent(id: "periodic-long-task", type: .longTask, start: now.timeIntervalSince1970.dd.toInt64Nanoseconds, duration: 0)
        let oldTask = DurationEvent(id: "outside-window", type: .longTask, start: 0, duration: 1)
        let unrelated = Vital.mockWith(name: "custom-vital", stepType: nil, date: now)
        let step = Vital.mockWith(name: "time_to_full_display", stepType: .start, date: now)
        for message: Any in [
            LongTaskMessage(attributes: [RUMCoreContext.IDs.viewID: ["task-view"], "task.attribute": "ignored"], longTask: task),
            LongTaskMessage(attributes: [RUMCoreContext.IDs.viewID: ["old-task-view"]], longTask: oldTask),
            OperationMessage(attributes: [:], operation: unrelated),
            OperationMessage(attributes: [:], operation: step)
        ] {
            XCTAssertFalse(profiler.receive(message: .payload(message), from: core))
        }
        drain(after: MemoryProfiler.Constants.eventCaptureDelay + 0.1)

        XCTAssertEqual(diagnostics.captures_count, 0)
        XCTAssertTrue(core.events.isEmpty)

        let captured = ReadWriteLock<ProfileSnapshot?>(wrappedValue: nil)
        let completed = expectation(description: "Periodic heap snapshot carries no long-task correlations")
        profiler.captureSnapshot(scheduledFor: .now()) { snapshot in
            captured.wrappedValue = snapshot
            completed.fulfill()
        }
        wait(for: [completed], timeout: 2)
        drain()
        XCTAssertEqual(diagnostics.captures_count, 1)
        XCTAssertTrue(core.events.isEmpty)
        let snapshot = try XCTUnwrap(captured.wrappedValue)
        XCTAssertTrue(snapshot.rumEvents.isEmpty)
        XCTAssertTrue(snapshot.attributes.isEmpty)
        ProfileWriter(featureScope: core).write([snapshot], operation: .continuousProfiling)
        XCTAssertTrue(core.events.isEmpty)
        XCTAssertTrue(core.metadata.isEmpty)
        withExtendedLifetime(profiler) {}
    }

    func testDelayedMemoryWarningKeepsTriggerCorrelationOutsideCurrentWindow() throws {
        let profiler = makeRuntimeProfiler()
        receive(context: context(), on: profiler)
        drain()
        record(size: 16)
        let warningTime = Date().timeIntervalSince1970.dd.toInt64Nanoseconds
        profiler.captureWindow()
        drain()
        XCTAssertTrue(core.events.isEmpty)
        XCTAssertGreaterThanOrEqual(dd_memory_profiler_window_start_time_nanos(), warningTime)
        record(address: 0x20000, size: 8)
        let warning = DurationEvent(id: "delivered-late", type: .error, start: warningTime - 1, duration: 0)

        _ = profiler.receive(message: .payload(MemoryWarningMessage(attributes: [:], warning: warning)), from: core)
        profiler.captureWindow()
        drain()

        XCTAssertEqual(core.events.count, 1)
        XCTAssertEqual(try rumEventIDs(), [warning.id])
        XCTAssertEqual(diagnostics.alloc_space, 8)
        XCTAssertEqual(diagnostics.inuse_space, 24)
        withExtendedLifetime(profiler) {}
    }

    func testPeriodicCaptureWritesPendingTriggersSeparatelyAndCancelsEventTimer() throws {
        let profiler = makeRuntimeProfiler()
        receive(context: context(), on: profiler)
        drain()
        record()
        let warning = DurationEvent(id: "periodic-warning", type: .error, start: Date().timeIntervalSince1970.dd.toInt64Nanoseconds, duration: 0)
        let task = DurationEvent(id: "periodic-task", type: .longTask, start: warning.start, duration: 0)
        _ = profiler.receive(message: .payload(LongTaskMessage(attributes: [RUMCoreContext.IDs.viewID: ["task-view"]], longTask: task)), from: core)
        _ = profiler.receive(message: .payload(MemoryWarningMessage(attributes: [RUMCoreContext.IDs.viewID: ["warning-view"]], warning: warning)), from: core)
        let completed = expectation(description: "Heap writes independently of periodic CPU capture")

        profiler.captureSnapshot(scheduledFor: .now()) { snapshot in
            XCTAssertNil(snapshot)
            completed.fulfill()
        }
        wait(for: [completed], timeout: 2)
        drain(after: MemoryProfiler.Constants.eventCaptureDelay + 0.1)

        XCTAssertEqual(diagnostics.captures_count, 1)
        XCTAssertEqual(core.events.count, 1)
        XCTAssertEqual(try rumEventIDs(), [warning.id])
        let event = try XCTUnwrap(core.events.first as? ProfileEvent)
        XCTAssertEqual(event.additionalAttributes?[RUMCoreContext.IDs.errorID] as? [String], [warning.id])
        XCTAssertEqual(event.additionalAttributes?[RUMCoreContext.IDs.longTaskID] as? [String], [])
        XCTAssertEqual(event.additionalAttributes?[RUMCoreContext.IDs.viewID] as? [String], ["warning-view"])
        XCTAssertTrue(event.tags.contains("operation:trigger"))
        withExtendedLifetime(profiler) {}
    }

    func testMemoryWarningUploadsUnchangedLiveHeapWithoutRepeatingAllocations() throws {
        let profiler = makeRuntimeProfiler()
        receive(context: context(), on: profiler)
        drain()
        record(size: 16)
        profiler.captureWindow()
        drain()
        XCTAssertTrue(core.events.isEmpty)
        let warning = DurationEvent(id: "unchanged-heap-warning", type: .error, start: Date().timeIntervalSince1970.dd.toInt64Nanoseconds, duration: 0)

        _ = profiler.receive(message: .payload(MemoryWarningMessage(attributes: [:], warning: warning)), from: core)
        profiler.captureWindow()
        drain()

        XCTAssertEqual(diagnostics.captures_count, 2)
        XCTAssertEqual(diagnostics.last_status, DD_MEMORY_CAPTURE_IDLE)
        XCTAssertEqual(diagnostics.alloc_space, 0)
        XCTAssertEqual(diagnostics.inuse_space, 16)
        XCTAssertEqual(core.events.count, 1)
        XCTAssertEqual(try rumEventIDs(), [warning.id])
        withExtendedLifetime(profiler) {}
    }

    func testConsentRevocationCancelsPendingEventCaptureWithoutWriting() {
        let profiler = makeRuntimeProfiler()
        receive(context: context(), on: profiler)
        drain()
        record()
        let warning = DurationEvent(id: "revoked-warning", type: .error, start: Date().timeIntervalSince1970.dd.toInt64Nanoseconds, duration: 0)
        _ = profiler.receive(message: .payload(MemoryWarningMessage(attributes: [:], warning: warning)), from: core)
        receive(context: context(consent: .notGranted), on: profiler)
        drain(after: MemoryProfiler.Constants.eventCaptureDelay + 0.1)

        XCTAssertEqual(profiler.state, .stopped)
        XCTAssertFalse(dd_memory_profiler_is_running())
        XCTAssertEqual(diagnostics.captures_count, 0)
        XCTAssertTrue(core.events.isEmpty)
        withExtendedLifetime(profiler) {}
    }

    func testSessionChangeFlushesOldTriggerAndCancelsItsPendingCapture() throws {
        let profiler = makeRuntimeProfiler()
        receive(context: context(), on: profiler)
        drain()
        record(size: 16)
        let warning = DurationEvent(id: "old-session-warning", type: .error, start: Date().timeIntervalSince1970.dd.toInt64Nanoseconds, duration: 0)
        _ = profiler.receive(message: .payload(MemoryWarningMessage(attributes: [:], warning: warning)), from: core)
        let nextSessionID = UUID()
        receive(context: context(sessionID: nextSessionID), on: profiler)
        drain()
        record(address: 0x20000, size: 8)
        let nextWarning = DurationEvent(id: "next-session-warning", type: .error, start: Date().timeIntervalSince1970.dd.toInt64Nanoseconds, duration: 0)
        drain(after: MemoryProfiler.Constants.eventCaptureDelay + 0.1)

        XCTAssertEqual(diagnostics.captures_count, 1)
        XCTAssertEqual(core.events.count, 1)
        XCTAssertEqual(try rumEventIDs(), [warning.id])
        let oldEvent = try XCTUnwrap(core.events.first as? ProfileEvent)
        XCTAssertEqual(oldEvent.additionalAttributes?[RUMCoreContext.IDs.sessionID] as? String, sessionID.uuidString.lowercased())

        _ = profiler.receive(message: .payload(MemoryWarningMessage(attributes: [:], warning: nextWarning)), from: core)
        profiler.captureWindow()
        drain()
        XCTAssertEqual(try rumEventIDs(at: 1), [nextWarning.id])
        XCTAssertEqual(diagnostics.alloc_space, 8)
        XCTAssertEqual(diagnostics.inuse_space, 24)
        let newEvent = try XCTUnwrap(core.events.last as? ProfileEvent)
        XCTAssertEqual(newEvent.additionalAttributes?[RUMCoreContext.IDs.sessionID] as? String, nextSessionID.uuidString.lowercased())
        withExtendedLifetime(profiler) {}
    }

    func testSamplingOutFlushesOldTriggerAndRejectsFurtherTriggers() throws {
        let profiler = makeRuntimeProfiler()
        receive(context: context(), on: profiler)
        drain()
        record()
        let warning = DurationEvent(id: "admitted-warning", type: .error, start: Date().timeIntervalSince1970.dd.toInt64Nanoseconds, duration: 0)
        _ = profiler.receive(message: .payload(MemoryWarningMessage(attributes: [:], warning: warning)), from: core)
        receive(context: context(sampleRate: 0), on: profiler)
        drain()
        record(address: 0x20000)
        _ = profiler.receive(message: .payload(MemoryWarningMessage(attributes: [:], warning: warning)), from: core)
        drain(after: MemoryProfiler.Constants.eventCaptureDelay + 0.1)

        XCTAssertEqual(diagnostics.captures_count, 1)
        XCTAssertEqual(core.events.count, 1)
        XCTAssertEqual(try rumEventIDs(), [warning.id])
        XCTAssertTrue(dd_memory_profiler_is_running())
        withExtendedLifetime(profiler) {}
    }

    func testCoalescedTriggersPreserveAllViewsAndLatestOtherAttributes() throws {
        let profiler = makeRuntimeProfiler()
        receive(context: context(), on: profiler)
        drain()
        record()
        let timestamp = Date().timeIntervalSince1970.dd.toInt64Nanoseconds
        let hang = DurationEvent(id: "hang-view", type: .error, start: timestamp, duration: 0)
        let warning = DurationEvent(id: "warning-view", type: .error, start: timestamp, duration: 0)
        _ = profiler.receive(message: .payload(AppHangMessage(
            attributes: [
                RUMCoreContext.IDs.viewID: ["view-a"],
                RUMCoreContext.IDs.viewName: ["View A"],
                "custom": "first",
                "previous.only": "discarded"
            ],
            hang: hang
        )), from: core)
        _ = profiler.receive(message: .payload(MemoryWarningMessage(
            attributes: [
                RUMCoreContext.IDs.viewID: ["view-b", "view-a"],
                RUMCoreContext.IDs.viewName: ["View B", "View A"],
                "custom": "latest"
            ],
            warning: warning
        )), from: core)
        profiler.captureWindow()
        drain()

        let event = try XCTUnwrap(core.events.first as? ProfileEvent)
        let viewIDs = try XCTUnwrap(event.additionalAttributes?[RUMCoreContext.IDs.viewID] as? [String])
        let viewNames = try XCTUnwrap(event.additionalAttributes?[RUMCoreContext.IDs.viewName] as? [String])
        XCTAssertEqual(Set(viewIDs), ["view-a", "view-b"])
        XCTAssertEqual(viewIDs.count, 2)
        XCTAssertEqual(Set(viewNames), ["View A", "View B"])
        XCTAssertEqual(viewNames.count, 2)
        XCTAssertEqual(event.additionalAttributes?["custom"] as? String, "latest")
        XCTAssertNil(event.additionalAttributes?["previous.only"])
        XCTAssertEqual(try rumEventIDs(), [hang.id, warning.id])
        XCTAssertEqual(diagnostics.captures_count, 1)
        withExtendedLifetime(profiler) {}
    }

    func testTTFDWithoutViewPreservesCoalescedHangView() throws {
        let profiler = makeRuntimeProfiler()
        receive(context: context(viewID: "current-view"), on: profiler)
        drain()
        record()
        let hang = DurationEvent(id: "view-hang", type: .error, start: Date().timeIntervalSince1970.dd.toInt64Nanoseconds, duration: 0)
        _ = profiler.receive(message: .payload(AppHangMessage(
            attributes: [RUMCoreContext.IDs.viewID: ["hang-view"], RUMCoreContext.IDs.viewName: ["Hang View"]],
            hang: hang
        )), from: core)
        let ttfd = Vital.mockWith(id: "no-view-ttfd", name: "time_to_full_display", stepType: nil, date: Date())
        _ = profiler.receive(message: .payload(OperationMessage(attributes: [:], operation: ttfd)), from: core)
        profiler.captureWindow()
        drain()

        let event = try XCTUnwrap(core.events.first as? ProfileEvent)
        XCTAssertEqual(event.additionalAttributes?[RUMCoreContext.IDs.viewID] as? [String], ["hang-view"])
        XCTAssertEqual(event.additionalAttributes?[RUMCoreContext.IDs.viewName] as? [String], ["Hang View"])
        XCTAssertEqual(try rumEventIDs(), [hang.id, ttfd.id])
        withExtendedLifetime(profiler) {}
    }

    func testTTIDPreservesViewsFromEarlierLaunchTriggers() throws {
        let profiler = makeProfiler()
        receive(context: context(), on: profiler)
        drain()
        record()
        let hang = DurationEvent(id: "launch-hang", type: .error, start: Date().timeIntervalSince1970.dd.toInt64Nanoseconds, duration: 0)
        _ = profiler.receive(message: .payload(AppHangMessage(
            attributes: [
                RUMCoreContext.IDs.viewID: ["hang-view"],
                RUMCoreContext.IDs.viewName: ["Hang View"],
                "custom": "hang",
                "hang.only": "preserved"
            ],
            hang: hang
        )), from: core)
        let ttid = Vital.mockWith(id: "launch-ttid", stepType: nil, date: Date())
        _ = profiler.receive(message: .payload(TTIDMessage(
            attributes: [RUMCoreContext.IDs.viewID: ["ttid-view"], RUMCoreContext.IDs.viewName: ["TTID View"], "custom": "ttid"],
            ttid: ttid
        )), from: core)
        drain()

        let event = try XCTUnwrap(core.events.first as? ProfileEvent)
        let viewIDs = try XCTUnwrap(event.additionalAttributes?[RUMCoreContext.IDs.viewID] as? [String])
        let viewNames = try XCTUnwrap(event.additionalAttributes?[RUMCoreContext.IDs.viewName] as? [String])
        XCTAssertEqual(Set(viewIDs), ["hang-view", "ttid-view"])
        XCTAssertEqual(Set(viewNames), ["Hang View", "TTID View"])
        XCTAssertEqual(event.additionalAttributes?["custom"] as? String, "ttid")
        XCTAssertEqual(event.additionalAttributes?["hang.only"] as? String, "preserved")
        XCTAssertEqual(try rumEventIDs(), [hang.id, ttid.id])
        XCTAssertEqual(diagnostics.captures_count, 1)
        withExtendedLifetime(profiler) {}
    }

    func testSpacedTriggersCaptureSeparateWindowsWithoutRepeatingAllocations() throws {
        let profiler = makeRuntimeProfiler()
        receive(context: context(), on: profiler)
        drain()
        let written = expectation(description: "Each spaced trigger writes a heap profile")
        written.expectedFulfillmentCount = 3
        written.assertForOverFulfill = true
        let captures = ReadWriteLock<[dd_memory_profiler_test_capture_diagnostics_t]>(wrappedValue: [])
        core.onEventWriteContext = { _ in
            captures.mutate { $0.append(self.diagnostics) }
            written.fulfill()
        }
        defer { core.onEventWriteContext = nil }
        let start = DispatchTime.now()
        let spacing = MemoryProfiler.Constants.eventCaptureDelay + 0.5
        let sizes: [UInt64] = [16, 8, 4]
        for index in sizes.indices {
            queue.asyncAfter(deadline: start + Double(index) * spacing) {
                self.record(address: 0x10000 + UInt(index) * 0x10000, size: sizes[index])
                let warning = DurationEvent(
                    id: "spaced-warning-\(index)",
                    type: .error,
                    start: Date().timeIntervalSince1970.dd.toInt64Nanoseconds,
                    duration: 0
                )
                _ = profiler.receive(message: .payload(MemoryWarningMessage(attributes: [:], warning: warning)), from: self.core)
            }
        }
        wait(for: [written], timeout: 8)
        drain()

        XCTAssertEqual(core.events.count, 3)
        XCTAssertEqual(diagnostics.captures_count, 3)
        XCTAssertEqual(captures.wrappedValue.map(\.alloc_space), [16, 8, 4])
        XCTAssertEqual(captures.wrappedValue.map(\.inuse_space), [16, 24, 28])
        for index in sizes.indices {
            XCTAssertEqual(try rumEventIDs(at: index), ["spaced-warning-\(index)"])
        }
        withExtendedLifetime(profiler) {}
    }

    func testTriggerAfterLaunchDeadlineCapturesWithoutWaitingForPeriodicTick() throws {
        let clock = MemoryProfilerMonotonicClockMock()
        let profiler = makeProfiler(monotonicClock: clock)
        receive(context: context(), on: profiler)
        drain()
        record()
        let hang = DurationEvent(id: "buffered-launch-hang", type: .error, start: Date().timeIntervalSince1970.dd.toInt64Nanoseconds, duration: 0)
        _ = profiler.receive(message: .payload(AppHangMessage(attributes: [:], hang: hang)), from: core)
        drain()
        XCTAssertEqual(diagnostics.captures_count, 0)
        let written = expectation(description: "Expired launch is captured on the event deadline")
        core.onEventWriteContext = { _ in written.fulfill() }
        defer { core.onEventWriteContext = nil }
        clock.elapsedTime = ProfilingScheduler.Constants.profilingInterval + 1
        let warning = DurationEvent(id: "post-deadline-warning", type: .error, start: Date().timeIntervalSince1970.dd.toInt64Nanoseconds, duration: 0)

        _ = profiler.receive(message: .payload(MemoryWarningMessage(attributes: [:], warning: warning)), from: core)
        wait(for: [written], timeout: 5)
        drain()

        XCTAssertEqual(diagnostics.captures_count, 1)
        XCTAssertEqual(core.events.count, 1)
        XCTAssertEqual(try rumEventIDs(), [hang.id, warning.id])
        receiveTTID(on: profiler)
        drain()
        XCTAssertEqual(diagnostics.captures_count, 1)
        withExtendedLifetime(profiler) {}
    }

    func testColdMemoryWarningCapturePerformanceWithFullLiveSetAndDeepStacks() {
        let options = XCTMeasureOptions()
        options.invocationOptions = [.manuallyStart, .manuallyStop]

        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()], options: options) {
            autoreleasepool {
                dd_memory_profiler_configure_for_testing(DD_MEMORY_TEST_HOOKS_SUCCEED)
                // Each iteration owns its output so retained mock uploads do not accumulate.
                let performanceCore = PassthroughCoreMock()
                let writer = ProfileWriter(featureScope: performanceCore)
                let profiler = MemoryProfiler(
                    profilingSamplerProvider: ProfilingSamplerProvider(continuousSampleRate: 0, memorySampleRate: 100),
                    writer: writer,
                    scheduler: ProfilingScheduler(writer: writer, profilingInterval: 3_600),
                    queue: queue,
                    notificationCenter: NotificationCenter()
                )
                defer { profiler.flushAndStop() }
                _ = profiler.receive(message: .context(context()), from: performanceCore)
                drain()
                let capacity = Int(DD_MEMORY_LIVE_SET_CAPACITY)
                let frameCount = Int(DD_MEMORY_LIVE_SET_MAX_FRAMES)
                let sharedFrames = 49
                let uniqueFrames = frameCount - sharedFrames
                var buckets = Set<Int>()
                var candidate: UInt = 0x10000
                while buckets.count < capacity {
                    let address = UnsafeRawPointer(bitPattern: candidate)
                    let bucket = dd_memory_live_set_bucket(address)
                    if buckets.insert(bucket).inserted {
                        let index = buckets.count - 1
                        var sample = dd_memory_live_sample_t()
                        sample.address = address
                        sample.size = 64
                        sample.weight = 1
                        withUnsafeMutableBytes(of: &sample.frames) { bytes in
                            let frames = bytes.bindMemory(to: UInt64.self)
                            for frame in 0..<frameCount {
                                frames[frame] = frame < sharedFrames
                                    ? UInt64(0x100000 + frame * 16)
                                    : UInt64(0x200000 + (index * uniqueFrames + frame - sharedFrames) * 16)
                            }
                        }
                        sample.frame_count = UInt32(frameCount)
                        dd_memory_profiler_record_for_testing(&sample)
                    }
                    candidate += 0x10
                }
                // Include the first encoder allocation, near the live-set and unique-location limits.
                XCTAssertEqual(diagnostics.captures_count, 0)
                let warning = DurationEvent(id: "performance-warning", type: .error, start: Date().timeIntervalSince1970.dd.toInt64Nanoseconds, duration: 0)

                startMeasuring()
                _ = profiler.receive(message: .payload(MemoryWarningMessage(attributes: [:], warning: warning)), from: performanceCore)
                profiler.captureWindow()
                drain()
                stopMeasuring()

                XCTAssertEqual(performanceCore.events.count, 1)
                XCTAssertEqual(diagnostics.alloc_space, Double(capacity * 64))
                XCTAssertEqual(diagnostics.inuse_space, Double(capacity * 64))
                XCTAssertEqual(diagnostics.inuse_objects, Double(capacity))
                XCTAssertEqual(diagnostics.sample_count, UInt64(capacity))
                let attachments = performanceCore.metadata.first as? ProfileAttachments
                let payload = attachments?.pprofs.first?.data ?? Data()
                XCTAssertFalse(payload.isEmpty)
                XCTAssertLessThanOrEqual(payload.count, Int(ProfilerFeature.Constants.maxObjectSize))
                let decoded = payload.withUnsafeBytes { bytes in
                    perftools__profiles__profile__unpack(nil, bytes.count, bytes.bindMemory(to: UInt8.self).baseAddress)
                }
                XCTAssertNotNil(decoded)
                if let decoded {
                    defer { perftools__profiles__profile__free_unpacked(decoded, nil) }
                    XCTAssertEqual(Int(decoded.pointee.n_sample), capacity)
                    XCTAssertEqual(Int(decoded.pointee.n_location), sharedFrames + capacity * uniqueFrames)
                }
            }
        }
    }

    private func rumEventIDs(at index: Int = 0) throws -> [String] {
        let attachments = try XCTUnwrap(core.metadata.dropFirst(index).first as? ProfileAttachments)
        let events = try XCTUnwrap(JSONSerialization.jsonObject(with: attachments.rumEvents) as? [[String: Any]])
        return events.compactMap { $0["id"] as? String }
    }

    private var memoryMetrics: [MemoryDiagnostics] {
        telemetry.messages.compactMap {
            ($0.asMetric?.attributes[ProfilingDiagnostics.Constants.diagnosticsKey] as? ProfilingDiagnostics)?.memory
        }
    }

    private var diagnostics: dd_memory_profiler_test_capture_diagnostics_t {
        dd_memory_profiler_capture_diagnostics_for_testing()
    }

    private func makeRuntimeProfiler(
        memorySampleRate: SampleRate = 100,
        profilingInterval: TimeInterval = 3_600,
        dateProvider: DateProvider = SystemDateProvider(),
        notificationCenter: NotificationCenter = NotificationCenter()
    ) -> MemoryProfiler {
        dd_memory_profiler_configure_for_testing(DD_MEMORY_TEST_HOOKS_SUCCEED)
        return makeProfiler(
            memorySampleRate: memorySampleRate,
            profilingInterval: profilingInterval,
            dateProvider: dateProvider,
            notificationCenter: notificationCenter
        )
    }

    private func makeProfiler(
        memorySampleRate: SampleRate = 100,
        profilingInterval: TimeInterval = 3_600,
        dateProvider: DateProvider = SystemDateProvider(),
        monotonicClock: MonotonicClock = SystemMonotonicClock(),
        notificationCenter: NotificationCenter = NotificationCenter()
    ) -> MemoryProfiler {
        profilingSamplerProvider = ProfilingSamplerProvider(
            continuousSampleRate: 0,
            memorySampleRate: memorySampleRate
        )
        let telemetryController = ProfilingTelemetryController(sampleRate: 100, telemetry: telemetry)
        let writer = ProfileWriter(featureScope: core, telemetryController: telemetryController)
        return MemoryProfiler(
            profilingSamplerProvider: profilingSamplerProvider,
            writer: writer,
            scheduler: ProfilingScheduler(writer: writer, profilingInterval: profilingInterval),
            telemetryController: telemetryController,
            queue: queue,
            dateProvider: dateProvider,
            monotonicClock: monotonicClock,
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

    private func drain(after interval: TimeInterval) {
        let completed = expectation(description: "Profiler queue passes pending event capture deadline")
        queue.asyncAfter(deadline: .now() + interval) { completed.fulfill() }
        wait(for: [completed], timeout: interval + 2)
        drain()
    }
}

private final class MemoryProfilerMonotonicClockMock: MonotonicClock {
    @ReadWriteLock
    var elapsedTime: TimeInterval = 0
}

#endif
