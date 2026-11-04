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
/// decision (independent of continuous CPU profiling), keeps recording in the background because
/// allocation interception is passive, and can emit a heap-only `ProfileEvent` when no CPU profile
/// is produced.
///
/// Recording and emission are gated separately. Recording stops only for terminal reasons (consent
/// revoked, sampled out, install failure, quota rejection), all of which correctly clear the sample
/// table. Uploading stays bound by `ProfilingConditions`, so no window ever ships with a silent gap
/// in its sampling.
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
        // Start with a background context so the CPU profiler doesn't auto-start at init. Memory
        // records in the background, so tests that need it off must use a terminal reason
        // (unconfigured, consent revoked, quota) rather than app state.
        core = PassthroughCoreMock(context: .mockWith(applicationStateHistory: .mockAppInBackground()))
        dd_profiler_stop()
        dd_profiler_destroy()
        // Ensure the memory interception paths are clean at test start.
        dd_memory_profiler_stop()
        dd_memory_test_reset()
    }

    override func tearDown() {
        // Always stop the memory interception — process-global, must not leak into other tests.
        dd_memory_profiler_stop()
        dd_memory_test_reset()
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

        enterForeground()

        XCTAssertTrue(dd_memory_profiler_is_running(), "Memory profiling must run when configured + foreground")
        withExtendedLifetime(profiler) {}
    }

    func testDisabledMemoryProfilingDoesNotRetainWarningCorrelationOrAttributes() {
        let memoryProfiler = MemoryProfiler(
            core: core,
            profilingSamplerProvider: ProfilingSamplerProvider(continuousSampleRate: .maxSampleRate),
            quotaChecker: ProfilingQuotaCheckerMock(),
            telemetryController: ProfilingTelemetryController(),
            profilingConditions: ProfilingConditions(),
            dateProvider: DateProviderMock()
        )
        memoryProfiler.update(attributes: [RUMCoreContext.IDs.sessionID: "cpu-only-session"])
        memoryProfiler.record(vital: .mockAny())
        memoryProfiler.record(hang: DurationEvent(id: "hang", type: .error, start: 0, duration: 10))
        memoryProfiler.record(longTask: DurationEvent(id: "task", type: .longTask, start: 0, duration: 10))
        memoryProfiler.record(warning: DurationEvent(id: "warning", type: .error, start: 0, duration: 0))

        XCTAssertFalse(memoryProfiler.isRecording)
        XCTAssertTrue(memoryProfiler.attributes.isEmpty)
        XCTAssertTrue(memoryProfiler.pendingWarnings.isEmpty)
    }

    func testMemoryProfilingDoesNotRun_whenNotConfigured() {
        let provider = makeSamplerProvider(memorySampleRate: 0)
        let profiler = makeProfiler(profilingSamplerProvider: provider)
        connectMessageReceiver(to: profiler, profilingSamplerProvider: provider)

        enterForeground()

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

        enterForeground()

        XCTAssertTrue(dd_memory_profiler_is_running(), "Memory must run even with continuous CPU profiling off")
        XCTAssertNotEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_RUNNING, "CPU profiler must NOT be running")
        withExtendedLifetime(profiler) {}
    }

    /// Option B independent EMISSION, now gated on a RUM event of interest: with continuous off and
    /// memory on, a window that carries a RUM event (here a long task) flushes a heap-only
    /// `ProfileEvent` (no `profile.pprof`, a `heap.pprof`) that also carries the correlated event.
    func testMemoryEmitsHeapOnlyProfile_whenContinuousOff_andRUMEventOfInterest() throws {
        let dateProvider = DateProviderMock()
        let profiler = makeForegroundHeapOnlyProfiler(dateProvider: dateProvider)
        XCTAssertNotEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_RUNNING, "CPU profiler must be off")

        let longTask = DurationEvent(id: .mockRandom(), type: .longTask, start: 0, duration: 100)

        // A live sampled allocation, so the heap snapshot is non-empty this window.
        try withSampledObject {
            // A RUM event of interest this window — the gate that now authorizes heap emission.
            _ = profiler.receive(
                message: .payload(LongTaskMessage(attributes: mockRandomAttributes(), longTask: longTask)),
                from: core
            )
            flushQueue()

            // Background transition triggers sendProfile() — the flush that closes this window.
            enterBackground(at: dateProvider.now)

            let event = try XCTUnwrap(core.events.first as? ProfileEvent, "a ProfileEvent must be written")
            let metadata = try XCTUnwrap(core.metadata.first as? ProfileAttachments)
            XCTAssertNil(metadata.pprof, "heap-only event must carry no CPU profile.pprof")
            XCTAssertNotNil(metadata.heapPprof, "heap-only event must carry heap.pprof")
            XCTAssertTrue(event.attachments.contains(ProfileAttachments.Constants.heapFilename))
            XCTAssertFalse(event.attachments.contains(ProfileAttachments.Constants.pprofFilename))
            // The heap-only event now carries the correlated long task (previously an empty timeline).
            XCTAssertEqual(event.additionalAttributes?[RUMCoreContext.IDs.longTaskID] as? [String], [longTask.id])
        }
        withExtendedLifetime(profiler) {}
    }

    /// Memory profiling is continuous: a window emits its heap whether or not any RUM event landed
    /// in it. Correlation enriches a heap profile, it does not authorize one — allocation data from
    /// an uncorrelated window is still real, and withholding it would leave holes in a curve that is
    /// meant to be unbroken. This mirrors the Go profiler, which uploads a delta every period.
    func testMemoryEmitsHeapProfile_withNoRUMEventAtAll() throws {
        let dateProvider = DateProviderMock()
        let profiler = makeForegroundHeapOnlyProfiler(dateProvider: dateProvider)

        try withSampledObject {
            // No vital, no hang, no long task — just a live allocation.
            enterBackground(at: dateProvider.now)

            XCTAssertEqual(heapAttachmentCount, 1, "an uncorrelated window must still emit its heap")
            let metadata = try XCTUnwrap(core.metadata.first as? ProfileAttachments)
            XCTAssertNil(metadata.pprof, "heap-only event must carry no CPU profile.pprof")
            XCTAssertNotNil(metadata.heapPprof)
        }
        withExtendedLifetime(profiler) {}
    }

    /// The one thing that does suppress emission is having nothing to report: `captureHeapPprof`
    /// returns nil when neither the live set nor the alloc window holds a sample, so an idle app
    /// uploads nothing. A skipped window must not block the next one.
    func testMemorySkipsWindowWithNoSamples_thenEmitsWhenAllocationsAppear() throws {
        let dateProvider = DateProviderMock()
        let profiler = makeForegroundHeapOnlyProfiler(dateProvider: dateProvider)

        // Window 1: nothing sampled at all.
        enterBackground(at: dateProvider.now)
        XCTAssertEqual(heapAttachmentCount, 0, "a window with no samples must not emit")

        enterForeground()

        // Window 2: a live allocation is enough on its own.
        try withSampledObject {
            enterBackground(at: dateProvider.now)

            XCTAssertEqual(heapAttachmentCount, 1, "the window with samples emits")
            let metadata = try XCTUnwrap(core.metadata.first as? ProfileAttachments)
            XCTAssertNotNil(metadata.heapPprof)
        }
        withExtendedLifetime(profiler) {}
    }

    /// Memory keeps its own correlation, so an operation step cannot strip it.
    ///
    /// In a memory-only session `isCustomProfiling` is always true and the native profiler always
    /// `.stopped`, so every `updateProfilerState` call — which an operation `.start` triggers —
    /// runs `cleanUpState(preservingOngoingOperations: false)` and clears the CPU machine's vitals,
    /// hangs and long tasks. Reading those for the heap event meant a long task recorded before the
    /// operation vanished from the profile. Memory's copy survives because only a heap emission
    /// clears it.
    func testMemoryCorrelationSurvivesCustomProfilingCleanup() throws {
        let dateProvider = DateProviderMock()
        let profiler = makeForegroundHeapOnlyProfiler(dateProvider: dateProvider)

        try withSampledObject {
            // A long task, then an operation start whose updateProfilerState wipes the CPU state.
            sendLongTask(to: profiler)
            _ = profiler.receive(
                message: .payload(OperationMessage(
                    attributes: mockRandomAttributes(),
                    operation: .mockWith(stepType: .start, date: dateProvider.now)
                )),
                from: core
            )
            flushQueue()

            enterBackground(at: dateProvider.now)

            XCTAssertEqual(heapAttachmentCount, 1, "the heap profile must still be emitted")
            let event = try XCTUnwrap(core.events(ofType: ProfileEvent.self).last)
            XCTAssertNotNil(
                event.additionalAttributes?[RUMCoreContext.IDs.longTaskID],
                "the long task recorded before the operation step must still correlate"
            )
            XCTAssertNotNil(
                event.additionalAttributes?[RUMCoreContext.IDs.vitalID],
                "the operation vital itself must correlate too"
            )
        }
        withExtendedLifetime(profiler) {}
    }

    // MARK: - Background: passive recording continues

    /// Memory recording must survive a background round-trip. The CPU profiler stops in the
    /// background because its sampling thread actively burns CPU; allocation interception is
    /// passive — a Poisson-sampled table write on allocations the app makes anyway — so it keeps
    /// observing, and is never torn down and restarted.
    ///
    /// The session-generation assertion is the point of this test, not a proxy for it. A stop
    /// followed by a start creates a fresh native generation, which bumps the generation
    /// AND clears the sample table. An unchanged generation therefore proves no table-clearing
    /// restart happened, i.e. objects sampled before the app backgrounded are still in the live
    /// set — precisely the long-lived objects `inuse_*` exists to surface.
    func testMemoryProfilingKeepsRecordingAcrossBackground_andPreservesLiveSet() {
        let dateProvider = DateProviderMock()
        let provider = makeSamplerProvider(memorySampleRate: .maxSampleRate)
        let profiler = makeProfiler(profilingSamplerProvider: provider, dateProvider: dateProvider)
        connectMessageReceiver(to: profiler, profilingSamplerProvider: provider)

        enterForeground()
        XCTAssertTrue(dd_memory_profiler_is_running(), "Precondition: memory must run in foreground")

        // A long-lived sampled object, allocated while still in the foreground.
        withSampledObject {
            let generationBefore = dd_memory_test_session_generation()
            let liveBefore = dd_memory_test_live_count()
            XCTAssertGreaterThan(liveBefore, 0, "Precondition: the live set must hold the sampled object")

            enterBackground(at: dateProvider.now)

            XCTAssertTrue(dd_memory_profiler_is_running(), "Passive recording must continue in the background")
            XCTAssertEqual(
                dd_memory_test_session_generation(),
                generationBefore,
                "Backgrounding must not restart the session — a restart clears the sample table"
            )
            XCTAssertEqual(
                dd_memory_test_live_count(),
                liveBefore,
                "The live set must survive the background transition"
            )

            // Allocations made while backgrounded are recorded too — that is the point of staying on.
            withSampledObject {
                XCTAssertEqual(
                    dd_memory_test_live_count(),
                    liveBefore + 1,
                    "An allocation made in the background must be recorded"
                )

                // Foreground again — still the same session, still no clear.
                enterForeground()

                XCTAssertTrue(dd_memory_profiler_is_running())
                XCTAssertEqual(
                    dd_memory_test_session_generation(),
                    generationBefore,
                    "Returning to the foreground must not restart the session either"
                )
                XCTAssertEqual(
                    dd_memory_test_live_count(),
                    liveBefore + 1,
                    "Both the pre-background and the background allocation must still be live"
                )
            }
        }
        withExtendedLifetime(profiler) {}
    }

    // MARK: - Background: emission is bounded

    /// Recording continues in the background, but uploading must not. The flush triggered by the
    /// background transition itself is legitimate — it closes out the foreground window and carries
    /// its heap — but a further context update arriving while ALREADY backgrounded must not emit
    /// again. Without that bound, every background context update would re-upload the same live set
    /// as a fresh profile and double-count the memory in the product.
    func testMemoryDoesNotReEmit_whenContextUpdatesArriveWhileAlreadyBackgrounded() {
        let dateProvider = DateProviderMock()
        let profiler = makeForegroundHeapOnlyProfiler(dateProvider: dateProvider)

        withSampledObject {
            // A correlated RUM event, then the transition into background: this closes the
            // foreground window and must carry its heap.
            sendLongTask(to: profiler)
            enterBackground(at: dateProvider.now)

            XCTAssertEqual(heapAttachmentCount, 1, "the closing flush must emit the foreground window's heap")

            // Another correlated event and another context update, both while ALREADY backgrounded.
            // Recording keeps observing, but nothing further may be uploaded until the foreground.
            sendLongTask(to: profiler)
            enterBackground(at: dateProvider.now)

            XCTAssertEqual(
                heapAttachmentCount,
                1,
                "a context update arriving while already backgrounded must not re-emit the live set"
            )
            XCTAssertTrue(dd_memory_profiler_is_running(), "recording must still be on regardless")
        }
        withExtendedLifetime(profiler) {}
    }

    /// The bound must not be an adjacency test on app state. `background → inactive → background`
    /// is a real sequence — the user starts to foreground the app and abandons it — and `.inactive`
    /// is not a `ProfilingConditions` blocker, so comparing against the previous app state would
    /// treat the second `.background` update as a fresh closing flush and re-upload the live set.
    func testMemoryDoesNotReEmit_whenBackgroundIsInterruptedByInactive() {
        let dateProvider = DateProviderMock()
        let profiler = makeForegroundHeapOnlyProfiler(dateProvider: dateProvider)

        withSampledObject {
            sendLongTask(to: profiler)
            enterBackground(at: dateProvider.now)
            XCTAssertEqual(heapAttachmentCount, 1, "Precondition: the closing flush emits once")

            // The app becomes inactive without ever becoming active — still not foreground.
            core.context = .mockWith(applicationStateHistory: .mockWith(
                initialState: .active,
                date: dateProvider.now.addingTimeInterval(-2),
                transitions: [
                    (state: .background, date: dateProvider.now.addingTimeInterval(-1)),
                    (state: .inactive, date: dateProvider.now)
                ]
            ))
            flushQueue()

            // Back to background, with a new correlated event.
            sendLongTask(to: profiler)
            enterBackground(at: dateProvider.now)

            XCTAssertEqual(
                heapAttachmentCount,
                1,
                "an .inactive flicker must not re-arm the closing flush"
            )
        }
        withExtendedLifetime(profiler) {}
    }

    /// Returning to the foreground DOES re-arm emission: the latch is about not duplicating a live
    /// set while conditions are blocked, not about emitting only once per process.
    func testMemoryEmitsAgain_afterReturningToForeground() {
        let dateProvider = DateProviderMock()
        let profiler = makeForegroundHeapOnlyProfiler(dateProvider: dateProvider)

        withSampledObject {
            sendLongTask(to: profiler)
            enterBackground(at: dateProvider.now)
            XCTAssertEqual(heapAttachmentCount, 1, "Precondition: first closing flush emitted")

            // Genuine return to the foreground re-arms it.
            enterForeground()

            withSampledObject {
                sendLongTask(to: profiler)
                enterBackground(at: dateProvider.now)

                XCTAssertEqual(
                    heapAttachmentCount,
                    2,
                    "the next foreground window must emit its own heap"
                )
            }
        }
        withExtendedLifetime(profiler) {}
    }

    // MARK: - Tracking consent

    /// `.notGranted` must stop memory profiling outright — allocation observation is disabled, not just
    /// the CPU profiler stopped. Memory has its own lifecycle, so it needs its own consent gate.
    func testMemoryProfilingStopsOnConsentNotGranted_andResumesWhenGrantedAgain() {
        let provider = makeSamplerProvider(memorySampleRate: .maxSampleRate)
        let profiler = makeProfiler(profilingSamplerProvider: provider)
        connectMessageReceiver(to: profiler, profilingSamplerProvider: provider)

        // Granted + foreground → running.
        core.context = .mockWith(trackingConsent: .granted, applicationStateHistory: .mockAppInForeground())
        flushQueue()
        XCTAssertTrue(dd_memory_profiler_is_running(), "Precondition: memory must run when consent is granted")

        // Consent revoked → interception must stop, even though the app stays in the foreground.
        core.context = .mockWith(trackingConsent: .notGranted, applicationStateHistory: .mockAppInForeground())
        flushQueue()
        XCTAssertFalse(dd_memory_profiler_is_running(), "Memory profiling must stop when consent is .notGranted")

        // Consent granted again → resumed.
        core.context = .mockWith(trackingConsent: .granted, applicationStateHistory: .mockAppInForeground())
        flushQueue()
        XCTAssertTrue(dd_memory_profiler_is_running(), "Memory profiling must resume when consent is granted again")
        withExtendedLifetime(profiler) {}
    }

    /// Allocations must not be recorded once consent is revoked — proves the interception really is
    /// observing-off, not merely flagged as stopped.
    ///
    /// The "allocations ARE recorded" precondition matters: without it, a profiler that never
    /// started at all would satisfy the assertion for the wrong reason.
    func testMemoryProfilingRecordsNoAllocations_afterConsentRevoked() {
        let provider = makeSamplerProvider(memorySampleRate: .maxSampleRate)
        let profiler = makeProfiler(profilingSamplerProvider: provider)
        connectMessageReceiver(to: profiler, profilingSamplerProvider: provider)

        // Granted + foreground → running, and allocations ARE recorded.
        core.context = .mockWith(trackingConsent: .granted, applicationStateHistory: .mockAppInForeground())
        flushQueue()
        XCTAssertTrue(dd_memory_profiler_is_running(), "Precondition: memory profiling must be running")

        let baseline = dd_memory_test_live_count()
        dd_memory_test_force_next_sample()
        let recorded = ProdSwiftFixture()
        withExtendedLifetime(recorded) {
            XCTAssertEqual(
                dd_memory_test_live_count(),
                baseline + 1,
                "Precondition: allocations must be recorded while consent is granted"
            )
        }

        // Consent revoked → no further allocation may be recorded.
        core.context = .mockWith(trackingConsent: .notGranted, applicationStateHistory: .mockAppInForeground())
        flushQueue()

        let afterRevocation = dd_memory_test_live_count()
        dd_memory_test_force_next_sample()
        let ignored = ProdSwiftFixture()
        withExtendedLifetime(ignored) {
            XCTAssertEqual(
                dd_memory_test_live_count(),
                afterRevocation,
                "No allocation may be recorded once tracking consent is .notGranted"
            )
        }
        withExtendedLifetime(profiler) {}
    }

    /// Consent revocation must reach memory profiling even while the app is backgrounded. This is
    /// only a live path because recording now continues in the background: previously the app state
    /// alone had already stopped it. `handle(context:)` returns early on several backgrounded
    /// paths, so consent must be evaluated — and memory reconciled — regardless of those returns.
    func testConsentRevocationStopsRecording_whileBackgrounded() {
        let provider = makeSamplerProvider(memorySampleRate: .maxSampleRate)
        let profiler = makeProfiler(profilingSamplerProvider: provider)
        connectMessageReceiver(to: profiler, profilingSamplerProvider: provider)

        core.context = .mockWith(trackingConsent: .granted, applicationStateHistory: .mockAppInBackground())
        flushQueue()
        XCTAssertTrue(dd_memory_profiler_is_running(), "Precondition: recording runs in the background")

        core.context = .mockWith(trackingConsent: .notGranted, applicationStateHistory: .mockAppInBackground())
        flushQueue()

        XCTAssertFalse(
            dd_memory_profiler_is_running(),
            "Revoking consent must stop recording even though the app never returns to the foreground"
        )

        // And nothing further may be recorded.
        let afterRevocation = dd_memory_test_live_count()
        dd_memory_test_force_next_sample()
        let ignored = ProdSwiftFixture()
        withExtendedLifetime(ignored) {
            XCTAssertEqual(
                dd_memory_test_live_count(),
                afterRevocation,
                "No allocation may be recorded in the background once consent is .notGranted"
            )
        }
        withExtendedLifetime(profiler) {}
    }

    /// `.pending` is fail-open for memory, matching the CPU profiler: only `.notGranted` disables
    /// collection. Data written while pending is held by core and resolved on the consent decision.
    func testMemoryProfilingRuns_whenConsentPending() {
        let provider = makeSamplerProvider(memorySampleRate: .maxSampleRate)
        let profiler = makeProfiler(profilingSamplerProvider: provider)
        connectMessageReceiver(to: profiler, profilingSamplerProvider: provider)

        core.context = .mockWith(trackingConsent: .pending, applicationStateHistory: .mockAppInForeground())
        flushQueue()

        XCTAssertTrue(dd_memory_profiler_is_running(), "Memory profiling must keep running while consent is .pending")
        withExtendedLifetime(profiler) {}
    }

    // MARK: - Terminal stops still clear

    /// The counterpart to `testMemoryProfilingKeepsRecordingAcrossBackground_andPreservesLiveSet`:
    /// where background must NOT restart the session, consent revocation must. Clearing is the
    /// correct semantics here — the samples may not be retained at all — so this asserts the
    /// generation DOES advance, proving the sample table was cleared rather than merely flagged off.
    func testConsentRevocationClearsTheSession() {
        let provider = makeSamplerProvider(memorySampleRate: .maxSampleRate)
        let profiler = makeProfiler(profilingSamplerProvider: provider)
        connectMessageReceiver(to: profiler, profilingSamplerProvider: provider)

        core.context = .mockWith(trackingConsent: .granted, applicationStateHistory: .mockAppInForeground())
        flushQueue()
        XCTAssertTrue(dd_memory_profiler_is_running(), "Precondition: memory must be running")

        withSampledObject {
            let generationBefore = dd_memory_test_session_generation()
            XCTAssertGreaterThan(dd_memory_test_live_count(), 0, "Precondition: the live set must be populated")

            core.context = .mockWith(trackingConsent: .notGranted, applicationStateHistory: .mockAppInForeground())
            flushQueue()

            XCTAssertFalse(dd_memory_profiler_is_running(), "Consent revocation must stop recording")
            XCTAssertNotEqual(
                dd_memory_test_session_generation(),
                generationBefore,
                "Consent revocation must end the session, not pause it"
            )
        }
        withExtendedLifetime(profiler) {}
    }

    /// A quota rejection stops and clears; nothing will be uploaded for that RUM session anyway.
    /// Quota resets only on a NEW session, so the restart is a genuinely fresh window rather than a
    /// resumed one with a hole in it — and `memoryWindowStart` must advance to the restart moment so
    /// the first post-reset window does not claim to cover the rejected period.
    func testQuotaRejectionClearsSession_andRestartIsAFreshWindow() throws {
        let dateProvider = DateProviderMock()
        let quotaChecker = ProfilingQuotaCheckerMock()
        let provider = makeSamplerProvider(continuousSampleRate: 0, memorySampleRate: .maxSampleRate)
        let profiler = makeProfiler(
            profilingSamplerProvider: provider,
            quotaChecker: quotaChecker,
            dateProvider: dateProvider
        )
        connectMessageReceiver(to: profiler, profilingSamplerProvider: provider)

        enterForeground()
        XCTAssertTrue(dd_memory_profiler_is_running(), "Precondition: memory must be running")
        let generationBeforeRejection = dd_memory_test_session_generation()

        // Quota rejected → recording stops and the table is cleared. `isRejectedByQuota` reads the
        // checker's stored result, so set it as well as firing the callback.
        let rejection = ProfilingQuotaResult(decision: .quotaKO, reason: .quotaExceeded)
        quotaChecker.quotaResult = rejection
        quotaChecker.onQuotaResultUpdate?(rejection)
        flushQueue()

        XCTAssertFalse(dd_memory_profiler_is_running(), "A quota rejection must stop recording")

        // Quota reset (new session) → recording restarts as a fresh session. The clock must advance
        // BEFORE the restart, otherwise `restartMoment` coincides with the profiler's initial
        // `memoryWindowStart` and the assertion below would hold with or without the advance.
        let restartMoment = dateProvider.now.addingTimeInterval(30)
        dateProvider.now = restartMoment
        quotaChecker.quotaResult = nil
        quotaChecker.onQuotaResultUpdate?(nil)
        flushQueue()

        XCTAssertTrue(dd_memory_profiler_is_running(), "A quota reset must restart recording")
        XCTAssertNotEqual(
            dd_memory_test_session_generation(),
            generationBeforeRejection,
            "The restart must be a fresh session, not a resumed one"
        )

        // The window must be bounded from the restart, not from before the rejection: emit a
        // heap-only profile and check its start.
        try withSampledObject {
            sendLongTask(to: profiler)
            enterBackground(at: dateProvider.now)

            let event = try XCTUnwrap(core.events(ofType: ProfileEvent.self).last)
            XCTAssertEqual(
                event.start,
                restartMoment.addingTimeInterval(profiler.currentServerTimeOffset),
                "the window must start at the restart, not before the quota rejection it holds no samples for"
            )
        }
        withExtendedLifetime(profiler) {}
    }

    func testQuotaReset_doesNotCarryRejectedSessionCorrelationIntoTheNewSession() throws {
        let dateProvider = DateProviderMock()
        let quotaChecker = ProfilingQuotaCheckerMock()
        let provider = makeSamplerProvider(continuousSampleRate: 0, memorySampleRate: .maxSampleRate)
        let profiler = makeProfiler(
            profilingSamplerProvider: provider,
            quotaChecker: quotaChecker,
            dateProvider: dateProvider
        )
        connectMessageReceiver(to: profiler, profilingSamplerProvider: provider)
        let firstSession: UUID = .mockRandom()
        core.context = .mockWith(
            applicationStateHistory: .mockAppInForeground(),
            additionalContext: [RUMCoreContext.mockWith(sessionID: firstSession, sessionSampleRate: .maxSampleRate)]
        )
        flushQueue()

        // Keep correlation pending regardless of whether any ambient allocation was sampled.
        dd_memory_test_force_capture_failure(true)
        _ = profiler.receive(
            message: .payload(MemoryWarningMessage(
                attributes: [RUMCoreContext.IDs.sessionID: firstSession.uuidString.lowercased()],
                error: DurationEvent(id: "rejected-session-warning", type: .error, start: 0, duration: 0)
            )),
            from: core
        )
        flushQueue()
        dd_memory_test_force_capture_failure(false)
        XCTAssertEqual(heapAttachmentCount, 0)

        let rejection = ProfilingQuotaResult(decision: .quotaKO, reason: .quotaExceeded)
        quotaChecker.quotaResult = rejection
        quotaChecker.onQuotaResultUpdate?(rejection)
        flushQueue()
        XCTAssertFalse(dd_memory_profiler_is_running())

        core.context = .mockWith(
            applicationStateHistory: .mockAppInForeground(),
            additionalContext: [RUMCoreContext.mockWith(sessionID: .mockRandom(), sessionSampleRate: .maxSampleRate)]
        )
        flushQueue()
        quotaChecker.quotaResult = nil
        quotaChecker.onQuotaResultUpdate?(nil)
        flushQueue()
        XCTAssertTrue(dd_memory_profiler_is_running())

        try withSampledObject {
            dateProvider.now.addTimeInterval(10)
            enterBackground(at: dateProvider.now)

            let event = try XCTUnwrap(core.events(ofType: ProfileEvent.self).last)
            XCTAssertNil(event.additionalAttributes?[RUMCoreContext.IDs.errorID])
            XCTAssertNil(event.additionalAttributes?[RUMCoreContext.IDs.sessionID])
        }
        withExtendedLifetime(profiler) {}
    }

    // MARK: - Fail closed on install failure

    /// The shared sampler backs both interception paths, so a sampler that cannot
    /// start means neither installs. Memory profiling must fail closed and latch,
    /// so a non-transient failure is not retried on every lifecycle transition.
    ///
    /// The observable is the install-failure telemetry count, deliberately: the
    /// native `dd_memory_profiler_is_running()` reads false whenever the sampler
    /// did not start, whether or not the Swift side latched, so asserting on it
    /// alone cannot tell a fail-closed profiler from one that merely looks
    /// stopped. Without the latch, each background→foreground cycle reconciles
    /// into a fresh install attempt and repeats the telemetry.
    func testMemoryProfilingFailsClosedAndDoesNotRetry_whenNeitherPathInstalls() {
        dd_memory_test_force_start_failure(true)
        defer { dd_memory_test_force_start_failure(false) }

        let telemetry = TelemetryMock()
        let provider = makeSamplerProvider(memorySampleRate: .maxSampleRate)
        let profiler = makeProfiler(profilingSamplerProvider: provider, telemetry: telemetry)
        connectMessageReceiver(to: profiler, profilingSamplerProvider: provider)

        core.context = .mockWith(trackingConsent: .granted, applicationStateHistory: .mockAppInForeground())
        flushQueue()

        XCTAssertFalse(dd_memory_profiler_is_running(), "The sampler must not be running")
        let attemptsAfterFirstInstall = installFailureCount(in: telemetry)
        XCTAssertGreaterThan(attemptsAfterFirstInstall, 0, "The failed install must be reported once")

        // Background, then foreground again. Reconciliation runs on both.
        core.context = .mockWith(trackingConsent: .granted, applicationStateHistory: .mockAppInBackground())
        flushQueue()
        core.context = .mockWith(trackingConsent: .granted, applicationStateHistory: .mockAppInForeground())
        flushQueue()

        XCTAssertEqual(
            installFailureCount(in: telemetry),
            attemptsAfterFirstInstall,
            "A latched install failure must not be retried, and must not re-report"
        )
        XCTAssertFalse(dd_memory_profiler_is_running(), "The sampler must still not be running")
        withExtendedLifetime(profiler) {}
    }

    // MARK: - Type name resolution stays off the hot path

    func testSwiftSamplesPreserveMetadataForDeferredTypeNameResolution() throws {
        let provider = makeSamplerProvider(memorySampleRate: .maxSampleRate)
        let profiler = makeProfiler(profilingSamplerProvider: provider)
        connectMessageReceiver(to: profiler, profilingSamplerProvider: provider)
        enterForeground()

        dd_memory_test_force_next_sample()
        let object = ProdSwiftFixture()
        try withExtendedLifetime(object) {
            var view = dd_memory_aggregation_view_t()
            XCTAssertTrue(dd_memory_profiler_capture(false, &view))
            let samples = try XCTUnwrap(view.samples)
            let swiftSample = try XCTUnwrap((0..<Int(view.count)).map { samples[$0] }.first {
                $0.key.source == DD_MEMORY_LIVE_SAMPLE_SOURCE_SWIFT
            })
            XCTAssertNil(swiftSample.key.class_name)
            XCTAssertNotNil(swiftSample.key.swift_metadata)
            XCTAssertNotNil(swiftSample.key.swift_name_resolver)
            XCTAssertGreaterThan(swiftSample.inuse_objects, 0)
        }
        withExtendedLifetime(profiler) {}
    }

    // MARK: - Teardown / stop

    func testMemoryProfilerStops_whenProfilerDeallocates() {
        let provider = makeSamplerProvider(memorySampleRate: .maxSampleRate)
        var profiler: DatadogProfiler? = makeProfiler(profilingSamplerProvider: provider)
        connectMessageReceiver(to: profiler!, profilingSamplerProvider: provider)

        enterForeground()
        XCTAssertTrue(dd_memory_profiler_is_running(), "Precondition: memory profiler must be running")

        // `connectMessageReceiver` wired the profiler into `core.messageReceiver`, so `core`
        // holds a strong reference. Drop it first, otherwise `deinit` never runs.
        core.messageReceiver = NOPFeatureMessageReceiver()
        profiler = nil

        XCTAssertFalse(dd_memory_profiler_is_running(), "Memory profiler must stop when the profiler is deallocated")
    }

    // MARK: - Swift interception is wired

    func testSwiftInterception_isActive_whenMemoryProfilingRuns() {
        let provider = makeSamplerProvider(memorySampleRate: .maxSampleRate)
        let profiler = makeProfiler(profilingSamplerProvider: provider)
        connectMessageReceiver(to: profiler, profilingSamplerProvider: provider)

        enterForeground()
        XCTAssertTrue(dd_memory_profiler_is_running(), "Precondition: memory profiler must be running")

        // A pure-Swift allocation (swift_allocObject path) must land in the shared live-set.
        dd_memory_test_force_next_sample()
        let before = dd_memory_test_live_count()
        let obj = ProdSwiftFixture()
        withExtendedLifetime(obj) {
            XCTAssertEqual(
                dd_memory_test_live_count(),
                before + 1,
                "pure-Swift alloc must be captured => Swift interception active in the production path"
            )
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
        dateProvider: DateProvider = DateProviderMock(),
        telemetry: TelemetryMock? = nil
    ) -> DatadogProfiler {
        DatadogProfiler(
            core: core,
            profilingSamplerProvider: profilingSamplerProvider,
            quotaChecker: quotaChecker,
            queue: profilerQueue,
            telemetryController: telemetry.map { .init(telemetry: $0) } ?? .init(),
            profilingInterval: .infinity,
            dateProvider: dateProvider
        )
    }

    /// A heap-only profiler — continuous CPU sampled out, memory sampled in — connected to the core
    /// and brought to the foreground, so the next background transition closes a real window.
    func makeForegroundHeapOnlyProfiler(dateProvider: DateProviderMock) -> DatadogProfiler {
        let provider = makeSamplerProvider(continuousSampleRate: 0, memorySampleRate: .maxSampleRate)
        let profiler = makeProfiler(profilingSamplerProvider: provider, dateProvider: dateProvider)
        connectMessageReceiver(to: profiler, profilingSamplerProvider: provider)
        enterForeground()
        XCTAssertTrue(dd_memory_profiler_is_running(), "Precondition: memory must record in the foreground")
        return profiler
    }

    /// Moves the app to the foreground and lets the profiler observe the update.
    func enterForeground() {
        core.context = .mockWith(applicationStateHistory: .mockAppInForeground())
        flushQueue()
    }

    /// Moves the app from active to background — the transition that closes the current window —
    /// and lets the profiler observe the update.
    func enterBackground(at date: Date) {
        core.context = .mockWith(applicationStateHistory: .mockWith(
            initialState: .active,
            date: date.addingTimeInterval(-1),
            transitions: [(state: .background, date: date)]
        ))
        flushQueue()
    }

    /// Forces the next allocation to be sampled and keeps that object alive for the duration of
    /// `body`, so it stays in the live set while the assertions run.
    func withSampledObject(_ body: () throws -> Void) rethrows {
        dd_memory_test_force_next_sample()
        let object = ProdSwiftFixture()
        try withExtendedLifetime(object) { try body() }
    }

    /// Number of emitted profiles carrying a `heap.pprof` attachment. Counts the heap specifically
    /// rather than events, so a CPU-only profile emitted alongside cannot skew the assertion.
    var heapAttachmentCount: Int {
        core.metadata
            .compactMap { $0 as? ProfileAttachments }
            .filter { $0.heapPprof != nil }
            .count
    }

    /// Sends a correlated RUM event of interest. A long task is used deliberately: unlike an
    /// operation step it does not run `updateProfilerState`, which would wipe the accumulated
    /// vitals via `cleanUpState` before the window is ever flushed.
    func sendLongTask(to profiler: DatadogProfiler) {
        let longTask = DurationEvent(id: .mockRandom(), type: .longTask, start: 0, duration: 100)
        _ = profiler.receive(
            message: .payload(LongTaskMessage(attributes: mockRandomAttributes(), longTask: longTask)),
            from: core
        )
        flushQueue()
    }

    /// Number of memory-interception install failures reported so far.
    func installFailureCount(in telemetry: TelemetryMock) -> Int {
        telemetry.messages
            .compactMap(\.asError)
            .filter { $0.message.contains("memory profiling failed to install") }
            .count
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
