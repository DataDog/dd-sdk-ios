/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if !os(watchOS)

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
        profiler.captureAppLaunch()
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

    func testMemorySamplingDoesNotRequireCPUProfilingDecision() {
        let profiler = makeProfiler()
        receive(context: context(), on: profiler)
        record(size: 16, weight: 2)
        profiler.captureWindow()
        drain()

        XCTAssertEqual(profilingSamplerProvider.continuousProfilingSampled, false)
        XCTAssertEqual(profiler.state, .running)
        XCTAssertEqual(diagnostics.ready_count, 1)
        XCTAssertEqual(diagnostics.alloc_space, 32)
        XCTAssertEqual(diagnostics.inuse_space, 32)
    }

    func testSampledOutSessionDropsWindowAndRestartsCleanlyForNextSession() {
        let profiler = makeProfiler()
        record(size: 16)
        receive(context: context(sampleRate: 0), on: profiler)
        drain()
        XCTAssertEqual(profiler.state, .stopped)
        XCTAssertFalse(dd_memory_profiler_is_running())
        XCTAssertEqual(diagnostics.captures_count, 0)

        receive(context: context(sessionID: UUID()), on: profiler)
        drain()
        record(address: 0x20000, size: 8)
        profiler.captureWindow()
        drain()
        XCTAssertEqual(profiler.state, .running)
        XCTAssertEqual(diagnostics.alloc_space, 8)
        XCTAssertEqual(diagnostics.inuse_space, 8)
    }

    func testMemorySamplerCanRejectAnOtherwiseSampledRUMSession() {
        let profiler = makeProfiler(memorySampleRate: 1)
        receive(context: context(sessionID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!), on: profiler)
        profiler.captureWindow()
        drain()

        XCTAssertEqual(profiler.state, .stopped)
        XCTAssertFalse(dd_memory_profiler_is_running())
        XCTAssertEqual(diagnostics.captures_count, 0)
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
        let profiler = makeProfiler()
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
                receive(context: context(sampleRate: 0), on: profiler)
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
        let profiler = makeProfiler()
        receive(context: context(), on: profiler)
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
        let profiler = makeProfiler()
        receive(context: context(), on: profiler)
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
        let profiler = makeProfiler()
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

    func testFirstForegroundWindowRetainsBackgroundRecordingDuration() {
        let profiler = makeProfiler()
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
        let profiler = makeProfiler(dateProvider: dateProvider)
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

    func testBackgroundOnlyLaunchDoesNotCloseRequestedWindows() {
        let profiler = makeProfiler()
        receive(context: context(state: .background), on: profiler)
        profiler.captureAppLaunch()
        profiler.captureWindow()
        drain()

        XCTAssertEqual(profiler.state, .emissionSuspended)
        XCTAssertEqual(diagnostics.captures_count, 0)
        XCTAssertTrue(dd_memory_profiler_is_running())
        XCTAssertFalse(dd_memory_profiler_is_paused())
    }

    func testSampledSessionBoundaryClosesDeltaAndKeepsLiveObjects() {
        let profiler = makeProfiler()
        receive(context: context(viewID: "prior-view"), on: profiler)
        record(size: 16)
        receive(context: context(sessionID: UUID(), viewID: "new-view"), on: profiler)
        drain()

        XCTAssertEqual(diagnostics.captures_count, 1)
        XCTAssertEqual(diagnostics.alloc_space, 16)
        XCTAssertEqual(diagnostics.inuse_space, 16)
        record(address: 0x20000, size: 8)
        profiler.captureWindow()
        drain()

        XCTAssertEqual(diagnostics.captures_count, 2)
        XCTAssertEqual(diagnostics.alloc_space, 8)
        XCTAssertEqual(diagnostics.inuse_space, 24)
        XCTAssertEqual(profiler.state, .running)
    }

    func testSessionSampleOutFlushesPriorSessionThenResetsLiveObjects() {
        let profiler = makeProfiler()
        record()
        queue.suspend()
        receive(context: context(), on: profiler)
        receive(context: context(sessionID: UUID(), sampleRate: 0), on: profiler)
        XCTAssertEqual(profilingSamplerProvider.memoryProfilingSampled, false)
        queue.resume()
        drain()

        XCTAssertEqual(diagnostics.captures_count, 1, "Queued session A must retain its sampled-in decision")
        XCTAssertEqual(diagnostics.alloc_space, 16)
        XCTAssertEqual(profiler.state, .stopped)
        XCTAssertFalse(dd_memory_profiler_is_running())

        receive(context: context(sessionID: UUID()), on: profiler)
        profiler.captureWindow()
        drain()
        XCTAssertEqual(diagnostics.last_status, DD_MEMORY_CAPTURE_IDLE)
        XCTAssertEqual(diagnostics.inuse_space, 0)
    }

    func testSessionBoundaryDiscardsBackgroundDeltaBeforeRecordingNextSession() {
        let nextSession = UUID()
        let profiler = makeProfiler()
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
        let profiler = makeProfiler()
        receive(context: context(), on: profiler)
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

    func testSessionSampleOutWhileEmissionSuspendedStopsRecording() {
        let profiler = makeProfiler()
        receive(context: context(), on: profiler)
        receive(context: context(state: .background), on: profiler)
        drain()
        record()
        receive(context: context(sessionID: UUID(), sampleRate: 0, state: .background), on: profiler)
        drain()

        XCTAssertEqual(profiler.state, .stopped)
        XCTAssertFalse(dd_memory_profiler_is_running())
        XCTAssertEqual(diagnostics.captures_count, 2)
        XCTAssertEqual(diagnostics.alloc_space, 16)
    }

    func testSampledInSessionRestartsBackgroundRecordingAfterSampledOutSession() {
        let profiler = makeProfiler()
        receive(context: context(sampleRate: 0, state: .background), on: profiler)
        drain()
        XCTAssertEqual(profiler.state, .stopped)
        XCTAssertFalse(dd_memory_profiler_is_running())

        let nextSession = UUID()
        receive(context: context(sessionID: nextSession, state: .background), on: profiler)
        profiler.captureWindow()
        drain()

        XCTAssertEqual(profiler.state, .emissionSuspended)
        XCTAssertTrue(dd_memory_profiler_is_running())
        XCTAssertEqual(diagnostics.captures_count, 0)
        record()
        receive(context: context(sessionID: nextSession), on: profiler)
        profiler.captureWindow()
        drain()
        XCTAssertEqual(diagnostics.alloc_space, 16)
    }

    func testLossOfRUMClosesPriorSessionAndDoesNotResumeInitialRecording() {
        let profiler = makeProfiler()
        receive(context: context(), on: profiler)
        record()
        receive(context: context(hasRUM: false), on: profiler)
        profiler.captureWindow()
        receive(context: context(hasRUM: false), on: profiler)
        drain()

        XCTAssertEqual(profiler.state, .stopped)
        XCTAssertFalse(dd_memory_profiler_is_running())
        XCTAssertEqual(diagnostics.captures_count, 1)
        XCTAssertEqual(diagnostics.alloc_space, 16)
    }

    func testConsentRevocationDiscardsAndPendingOrGrantedCanRestart() {
        for consent in [TrackingConsent.pending, .granted] {
            dd_memory_profiler_configure_for_testing(DD_MEMORY_TEST_HOOKS_SUCCEED)
            do {
                let profiler = makeProfiler()
                receive(context: context(), on: profiler)
                record(size: 16)
                receive(context: context(consent: .notGranted), on: profiler)
                drain()
                XCTAssertEqual(profiler.state, .stopped)
                XCTAssertFalse(dd_memory_profiler_is_running())
                XCTAssertEqual(diagnostics.captures_count, 0)

                receive(context: context(consent: consent), on: profiler)
                drain()
                record(address: 0x20000, size: 8)
                profiler.captureWindow()
                drain()
                XCTAssertEqual(profiler.state, .running)
                XCTAssertEqual(diagnostics.alloc_space, 8)
                XCTAssertEqual(diagnostics.inuse_space, 8)
            }
        }
    }

    func testConsentRevocationWhileEmissionSuspendedStopsRecordingWithoutCapture() {
        let profiler = makeProfiler()
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
        profiler.captureAppLaunch()
        profiler.captureAppLaunch()
        drain()

        XCTAssertEqual(diagnostics.captures_count, 1)
        XCTAssertEqual(diagnostics.time_nanos, launchOrigin)
        XCTAssertEqual(diagnostics.alloc_space, 16)
    }

    func testTTIDBeforeSessionDecisionClosesAtTTIDWithoutRecaptureAfterDecision() {
        let profiler = makeProfiler()
        record()
        profiler.captureAppLaunch()
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
        profiler.captureAppLaunch()
        drain()

        XCTAssertEqual(profiler.state, .failed)
        XCTAssertFalse(dd_memory_profiler_is_running())
        XCTAssertEqual(diagnostics.captures_count, 1)
        XCTAssertEqual(diagnostics.last_status, DD_MEMORY_CAPTURE_FAILED)

        receive(context: context(), on: profiler)
        profiler.captureAppLaunch()
        profiler.captureWindow()
        drain()
        XCTAssertEqual(profiler.state, .failed)
        XCTAssertFalse(dd_memory_profiler_is_running())
        XCTAssertEqual(diagnostics.captures_count, 1)
    }

    func testIdleTTIDBeforeSessionDecisionIsNotRecaptured() {
        let profiler = makeProfiler()
        profiler.captureAppLaunch()
        drain()
        XCTAssertEqual(diagnostics.captures_count, 1)
        XCTAssertEqual(diagnostics.last_status, DD_MEMORY_CAPTURE_IDLE)
        XCTAssertEqual(profiler.state, .waiting)

        record()
        profiler.captureAppLaunch()
        receive(context: context(), on: profiler)
        profiler.captureAppLaunch()
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
        profiler.captureAppLaunch()
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

    func testPendingLaunchRetainsForegroundHistoryFromBeforeTTID() {
        let profiler = makeProfiler()
        let launchOrigin = dd_memory_profiler_window_start_time_nanos()
        record()
        let backgroundDate = Date()
        profiler.captureAppLaunch()
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

        XCTAssertEqual(diagnostics.captures_count, 2, "The pending launch establishes historical foreground eligibility")
        XCTAssertEqual(profiler.state, .emissionSuspended)
    }

    func testPendingLaunchIsDiscardedWhenSessionIsSampledOut() {
        let profiler = makeProfiler()
        record()
        profiler.captureAppLaunch()
        receive(context: context(sampleRate: 0), on: profiler)
        drain()

        XCTAssertEqual(diagnostics.captures_count, 1)
        XCTAssertEqual(profiler.state, .stopped)
        XCTAssertFalse(dd_memory_profiler_is_running())
        receive(context: context(sessionID: UUID()), on: profiler)
        profiler.captureWindow()
        drain()
        XCTAssertEqual(diagnostics.inuse_space, 0)
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

    func testBackgroundKeepsRecordingUntilFirstSessionDecision() {
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

    func testLowPowerKeepsRecordingUntilFirstSessionDecision() {
        let profiler = makeProfiler()
        receive(context: context(lowPower: true, hasRUM: false), on: profiler)
        profiler.captureWindow()
        drain()

        XCTAssertEqual(profiler.state, .emissionSuspended)
        XCTAssertTrue(dd_memory_profiler_is_running())
        XCTAssertFalse(dd_memory_profiler_is_paused())
        XCTAssertEqual(diagnostics.captures_count, 0)
    }

    func testConsentRecoveryWithoutRUMInBackgroundRestartsRecording() {
        let profiler = makeProfiler()
        receive(context: context(consent: .notGranted, state: .background, hasRUM: false), on: profiler)
        drain()
        XCTAssertEqual(profiler.state, .stopped)
        XCTAssertFalse(dd_memory_profiler_is_running())

        receive(context: context(consent: .pending, state: .background, hasRUM: false), on: profiler)
        profiler.captureWindow()
        drain()
        XCTAssertTrue(dd_memory_profiler_is_running())
        XCTAssertFalse(dd_memory_profiler_is_paused())
        XCTAssertEqual(profiler.state, .emissionSuspended)
        receive(context: context(consent: .pending, state: .background, hasRUM: false), on: profiler)
        drain()
        XCTAssertEqual(profiler.state, .emissionSuspended)
        XCTAssertTrue(dd_memory_profiler_is_running())
        XCTAssertEqual(diagnostics.captures_count, 0)
    }

    func testWindowRequestPreservesPendingTTIDUntilFirstSessionDecision() {
        let profiler = makeProfiler()
        record()
        profiler.captureAppLaunch()
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

    func testRuntimeBlockerPreservesUncorrelatedLaunchWindowUntilSessionDecision() {
        let profiler = makeProfiler()
        let launchOrigin = dd_memory_profiler_window_start_time_nanos()
        record()
        receive(context: context(lowPower: true, hasRUM: false), on: profiler)
        drain()
        XCTAssertEqual(profiler.state, .emissionSuspended)
        XCTAssertEqual(diagnostics.captures_count, 0)

        receive(context: context(), on: profiler)
        profiler.captureWindow()
        drain()

        XCTAssertEqual(profiler.state, .running)
        XCTAssertEqual(diagnostics.captures_count, 1)
        XCTAssertEqual(diagnostics.time_nanos, launchOrigin)
        XCTAssertEqual(diagnostics.alloc_space, 16)
    }

    func testRuntimeBlockerPreservesPendingTTIDUntilSessionDecision() {
        let profiler = makeProfiler()
        record()
        profiler.captureAppLaunch()
        receive(context: context(lowPower: true, hasRUM: false), on: profiler)
        receive(context: context(hasRUM: false), on: profiler)
        drain()

        XCTAssertEqual(profiler.state, .waiting)
        XCTAssertEqual(diagnostics.captures_count, 1)
        let launch = diagnostics
        receive(context: context(), on: profiler)
        drain()
        XCTAssertEqual(profiler.state, .running)
        XCTAssertEqual(diagnostics.captures_count, 1)
        XCTAssertEqual(diagnostics.time_nanos, launch.time_nanos)
        XCTAssertEqual(diagnostics.alloc_space, 16)
    }

    func testTTIDDuringUnresolvedRuntimeBlockerClosesLaunchWithoutRecapture() {
        let profiler = makeProfiler()
        receive(context: context(lowPower: true, hasRUM: false), on: profiler)
        record()
        profiler.captureAppLaunch()
        drain()

        XCTAssertEqual(profiler.state, .emissionSuspended)
        XCTAssertEqual(diagnostics.captures_count, 1)
        XCTAssertEqual(diagnostics.alloc_space, 16)

        receive(context: context(lowPower: true), on: profiler)
        profiler.captureWindow()
        drain()
        XCTAssertEqual(profiler.state, .emissionSuspended)
        XCTAssertEqual(diagnostics.captures_count, 1)
        XCTAssertTrue(dd_memory_profiler_is_running())
    }

    func testConcurrentContextAndWindowRequestsShareOneNativeQueue() {
        let profiler = makeProfiler()
        let sessionID = sessionID
        receive(context: context(), on: profiler)
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

    func testOrderlyTerminationFlushesAndSDKTeardownDrops() {
        do {
            let profiler = makeProfiler()
            receive(context: context(), on: profiler)
            record()
            profiler.flushAndStop()
            XCTAssertEqual(profiler.state, .shutDown)
            XCTAssertFalse(dd_memory_profiler_is_running())
            XCTAssertEqual(diagnostics.captures_count, 1)
            XCTAssertEqual(diagnostics.alloc_space, 16)

            receive(context: context(), on: profiler)
            profiler.captureWindow()
            drain()
            XCTAssertEqual(profiler.state, .shutDown)
            XCTAssertEqual(diagnostics.captures_count, 1)
        }

        dd_memory_profiler_configure_for_testing(DD_MEMORY_TEST_HOOKS_SUCCEED)
        let other = makeProfiler()
        receive(context: context(), on: other)
        record()
        other.stop()
        XCTAssertEqual(other.state, .shutDown)
        XCTAssertFalse(dd_memory_profiler_is_running())
        XCTAssertEqual(diagnostics.captures_count, 0)
    }

    func testTerminationNotificationFlushesSynchronously() {
        let center = NotificationCenter()
        let profiler = makeProfiler(notificationCenter: center)
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
        let profiler = makeProfiler(notificationCenter: center)
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
        let profiler = makeProfiler()
        receive(context: context(), on: profiler)
        drain()
        record()
        dd_memory_profiler_fail_next_capture_for_testing()
        profiler.flushAndStop()

        XCTAssertEqual(profiler.state, .shutDown)
        XCTAssertFalse(dd_memory_profiler_is_running())
        XCTAssertEqual(diagnostics.last_status, DD_MEMORY_CAPTURE_FAILED)

        receive(context: context(sessionID: UUID()), on: profiler)
        profiler.captureAppLaunch()
        profiler.captureWindow()
        profiler.flushAndStop()
        profiler.stop()
        drain()

        XCTAssertEqual(profiler.state, .shutDown)
        XCTAssertFalse(dd_memory_profiler_is_running())
        XCTAssertEqual(diagnostics.captures_count, 1)
    }

    func testDeinitializationStopsWithoutFlushing() {
        var profiler: MemoryProfiler? = makeProfiler()
        receive(context: context(), on: profiler)
        drain()
        record()
        profiler = nil

        XCTAssertFalse(dd_memory_profiler_is_running())
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

    private func makeProfiler(
        memorySampleRate: SampleRate = 100,
        dateProvider: DateProvider = SystemDateProvider(),
        notificationCenter: NotificationCenter = NotificationCenter()
    ) -> MemoryProfiler {
        profilingSamplerProvider = ProfilingSamplerProvider(continuousSampleRate: 0, memorySampleRate: memorySampleRate)
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
