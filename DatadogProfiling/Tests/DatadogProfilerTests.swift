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
//swiftlint:disable duplicate_imports
import DatadogMachProfiler
import DatadogMachProfiler.Testing
//swiftlint:enable duplicate_imports

final class DatadogProfilerTests: XCTestCase {
    private var core: PassthroughCoreMock!  // swiftlint:disable:this implicitly_unwrapped_optional
    private let profilerQueue = DispatchQueue(label: "test.profiler")

    override func setUp() {
        super.setUp()
        core = PassthroughCoreMock(context: .mockWith(applicationStateHistory: .mockAppInForeground()))
        DatadogProfiler.resetActiveInstance()
        dd_profiler_stop()
        dd_profiler_destroy()
    }

    override func tearDown() {
        profilerQueue.sync {}
        core.messageReceiver = NOPFeatureMessageReceiver()
        DatadogProfiler.resetActiveInstance()
        dd_profiler_stop()
        dd_profiler_destroy()
        dd_delete_profiling_defaults()
        core = nil
        super.tearDown()
    }

    // MARK: - receive(message:from:)

    func testReceiveRUMEvents() {
        // Given
        let profiler = continuousProfiler()
        let startOperation: Vital = .mockWith(name: "operation")
        let endOperation: Vital = .mockWith(id: .mockRandom(), name: "operation", stepType: .end)
        let launchVital: Vital = .mockWith(stepType: nil)
        let ttfdVital: Vital = .mockWith(stepType: nil, duration: 2_000_000_000)
        let longTask = DurationEvent(id: .mockRandom(), type: .longTask, start: 0, duration: 100)
        let hang = DurationEvent(id: .mockRandom(), type: .error, start: 0, duration: 500)

        // When
        var result = profiler.receive(
            message: .payload(OperationMessage(attributes: mockRandomAttributes(), operation: startOperation)),
            from: core
        )

        // Then
        XCTAssertFalse(result, "Profiler does not consume RUM operations before app launch")

        // When
        result = profiler.receive(
            message: .payload(OperationMessage(attributes: mockRandomAttributes(), operation: endOperation)),
            from: core
        )

        // Then
        XCTAssertFalse(result, "Profiler does not consume RUM operations before app launch")

        // When
        result = profiler.receive(
            message: .payload(TTIDMessage(attributes: mockRandomAttributes(), ttid: launchVital)),
            from: core
        )

        // Then
        XCTAssertTrue(result, "Coordinator consumes app launch vitals")

        // When
        result = profiler.receive(
            message: .payload(OperationMessage(
                attributes: mockRandomAttributes(),
                operation: ttfdVital
            )),
            from: core
        )

        // Then
        XCTAssertTrue(result, "Operation messages should be consumed by continuous profiler after app launch")

        // When
        result = profiler.receive(
            message: .payload(LongTaskMessage(attributes: mockRandomAttributes(), longTask: longTask)),
            from: core
        )

        // Then
        XCTAssertTrue(result, "Long tasks should be consumed by continuous profiler after app launch")

        // When
        result = profiler.receive(
            message: .payload(AppHangMessage(attributes: mockRandomAttributes(), hang: hang)),
            from: core
        )

        // Then
        XCTAssertTrue(result, "App hangs should be consumed by continuous profiler after app launch")
    }

    func testReceiveApplicationLaunchVital_capturesOngoingRUMVitals() throws {
        // Given
        let dateProvider = DateProviderMock()
        let profiler = continuousProfiler(isAppLaunchProfilingEnabled: true, dateProvider: dateProvider)
        let completedOperationStart = Vital.mockWith(name: "completed-operation")
        let completedOperationEnd = Vital.mockWith(
            name: completedOperationStart.name,
            operationKey: completedOperationStart.operationKey,
            stepType: .end
        )
        let ongoingOperationStart = Vital.mockWith(name: "ongoing-operation", stepType: .start, date: dateProvider.now)
        let hang = DurationEvent(id: "hang-id", type: .error, start: 0, duration: 500)
        let longTask = DurationEvent(id: "long-task-id", type: .longTask, start: 0, duration: 100)
        let launchVital: Vital = .mockWith(stepType: nil)

        dd_profiler_start_testing(100, false, 5.seconds.dd.toInt64Nanoseconds, 0)

        _ = profiler.receive(
            message: .payload(OperationMessage(attributes: mockRandomAttributes(), operation: completedOperationStart)),
            from: core
        )
        _ = profiler.receive(
            message: .payload(OperationMessage(attributes: mockRandomAttributes(), operation: completedOperationEnd)),
            from: core
        )
        _ = profiler.receive(
            message: .payload(OperationMessage(attributes: mockRandomAttributes(), operation: ongoingOperationStart)),
            from: core
        )
        _ = profiler.receive(
            message: .payload(AppHangMessage(attributes: mockRandomAttributes(), hang: hang)),
            from: core
        )
        _ = profiler.receive(
            message: .payload(LongTaskMessage(attributes: mockRandomAttributes(), longTask: longTask)),
            from: core
        )

        // When - receive TTID to keep it in the active continuous profile.
        let result = profiler.receive(
            message: .payload(TTIDMessage(attributes: mockRandomAttributes(), ttid: launchVital)),
            from: core
        )
        flushQueue()
        XCTAssertTrue(result)
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_RUNNING)
        XCTAssertTrue(core.metadata.isEmpty, "TTID should not cut the profile while continuous profiling keeps running")

        // When - transition to background to flush the next continuous/custom profile.
        core.context = .mockWith(applicationStateHistory: .mockWith(
            initialState: .active,
            date: dateProvider.now.addingTimeInterval(-1),
            transitions: [(state: .background, date: dateProvider.now)]
        ))
        let expectedProfileCount = core.metadata.count + 1
        _ = profiler.receive(message: .context(core.context), from: core)
        waitUntil(timeout: 1.0) {
            core.metadata.count >= expectedProfileCount
        }

        // Then
        let metadata = try XCTUnwrap(core.metadata.last as? ProfileAttachments)
        let rumEvents = try typedRUMEvents(from: metadata)
        let vitalIDs = eventIDs(ofType: "vital", in: rumEvents)
        XCTAssertEqual(Set(vitalIDs), Set([completedOperationStart.id, ongoingOperationStart.id, launchVital.id]))
        XCTAssertEqual(eventIDs(ofType: "error", in: rumEvents), [hang.id])
        XCTAssertEqual(eventIDs(ofType: "long_task", in: rumEvents), [longTask.id])
    }
}

// MARK: - Notifications

extension DatadogProfilerTests {
    func testApplicationDidEnterBackground_stopsProfiler() {
        // Given
        let dateProvider = DateProviderMock()
        let profiler = continuousProfiler(dateProvider: dateProvider)
        dd_profiler_start_testing(100, false, 5.seconds.dd.toInt64Nanoseconds, 0)
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_RUNNING)

        // When - transition context to background while retaining foreground history
        core.context = .mockWith(applicationStateHistory: .mockWith(
            initialState: .active,
            date: dateProvider.now.addingTimeInterval(-1),
            transitions: [(state: .background, date: dateProvider.now)]
        ))
        _ = profiler.receive(message: .context(core.context), from: core)
        flushQueue()

        // Then
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_STOPPED)
        withExtendedLifetime(profiler) {}
    }

    func testTrackingConsentNotGranted_stopsDiscardsAndDropsPayloadsUntilConsentIsAllowedAgain() {
        // Given
        let profilingSamplerProvider = profilingSamplerProvider(isContinuousProfiling: true)
        profilingSamplerProvider.updateWith(
            deterministicSampler: DeterministicSampler(uuid: .mockRandom(), samplingRate: .maxSampleRate)
        )
        let dateProvider = DateProviderMock()
        let profiler = continuousProfiler(
            profilingSamplerProvider: profilingSamplerProvider,
            dateProvider: dateProvider
        )
        dd_profiler_start_testing(100, false, Int64.max, 0)
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_RUNNING)

        let trace = UnsafeMutablePointer<stack_trace_t>.allocate(capacity: 1)
        trace.pointee = .mockWith(tid: 1, addresses: [0x100001000])
        dd_pprof_add_samples(dd_profiler_get_profile(), trace, 1)
        dd_free(trace)
        XCTAssertGreaterThan(dd_pprof_sample_count(dd_profiler_get_profile()), 0)
        let longTask = DurationEvent(id: .mockRandom(), type: .longTask, start: 0, duration: 100)
        _ = profiler.receive(
            message: .payload(LongTaskMessage(attributes: mockRandomAttributes(), longTask: longTask)),
            from: core
        )

        // When
        core.context = .mockWith(
            trackingConsent: .notGranted,
            applicationStateHistory: .mockWith(
                initialState: .active,
                date: dateProvider.now.addingTimeInterval(-1),
                transitions: [(state: .background, date: dateProvider.now)]
            ),
            additionalContext: [RUMCoreContext.mockWith(sessionSampleRate: .maxSampleRate)]
        )
        _ = profiler.receive(message: .context(core.context), from: core)
        flushQueue()

        // Then
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_STOPPED)
        XCTAssertEqual(dd_pprof_sample_count(dd_profiler_get_profile()), 0)
        XCTAssertTrue(core.metadata.isEmpty)
        let profilingContext = core.context.additionalContext(ofType: ProfilingContext.self)
        XCTAssertEqual(profilingContext?.status, .stopped(reason: .manual))
        XCTAssertNil(profilingContext?.quotaReason)

        // When - payloads arrive while consent is denied, then consent becomes allowed again.
        let deniedLongTask = DurationEvent(id: .mockRandom(), type: .longTask, start: 0, duration: 100)
        _ = profiler.receive(
            message: .payload(LongTaskMessage(attributes: mockRandomAttributes(), longTask: deniedLongTask)),
            from: core
        )
        core.context = .mockWith(
            trackingConsent: .granted,
            applicationStateHistory: .mockAppInForeground(),
            additionalContext: [RUMCoreContext.mockWith(sessionSampleRate: .maxSampleRate)]
        )
        _ = profiler.receive(message: .context(core.context), from: core)
        flushQueue()
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_RUNNING)

        let allowedTrace = UnsafeMutablePointer<stack_trace_t>.allocate(capacity: 1)
        allowedTrace.pointee = .mockWith(tid: 1, addresses: [0x100001000])
        dd_pprof_add_samples(dd_profiler_get_profile(), allowedTrace, 1)
        dd_free(allowedTrace)
        XCTAssertGreaterThan(dd_pprof_sample_count(dd_profiler_get_profile()), 0)

        core.context = .mockWith(
            trackingConsent: .granted,
            applicationStateHistory: .mockWith(
                initialState: .active,
                date: dateProvider.now.addingTimeInterval(-1),
                transitions: [(state: .background, date: dateProvider.now)]
            ),
            additionalContext: [RUMCoreContext.mockWith(sessionSampleRate: .maxSampleRate)]
        )
        waitForProfileWrite(expectingWrite: false, timeout: 0.15) {
            _ = profiler.receive(message: .context(core.context), from: core)
            flushQueue()
        }

        // Then
        XCTAssertTrue(core.metadata.isEmpty)
        withExtendedLifetime(profiler) {}
    }

    func testTrackingConsentPending_doesNotStopProfiler() {
        // Given
        let profilingSamplerProvider = profilingSamplerProvider(isContinuousProfiling: true)
        profilingSamplerProvider.updateWith(
            deterministicSampler: DeterministicSampler(uuid: .mockRandom(), samplingRate: .maxSampleRate)
        )
        let profiler = continuousProfiler(profilingSamplerProvider: profilingSamplerProvider)
        dd_profiler_start_testing(100, false, Int64.max, 0)

        // When
        core.context = .mockWith(
            trackingConsent: .pending,
            applicationStateHistory: .mockAppInForeground(),
            additionalContext: [RUMCoreContext.mockWith(sessionSampleRate: .maxSampleRate)]
        )
        _ = profiler.receive(message: .context(core.context), from: core)
        flushQueue()

        // Then
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_RUNNING)
        withExtendedLifetime(profiler) {}
    }

    func testTrackingConsentNotGranted_cleansObserverPayloadsAndUpdatesProfilingContext() throws {
        // Given
        let coordinatorSamplerProvider = profilingSamplerProvider(isContinuousProfiling: true)
        let coordinator = continuousProfiler(profilingSamplerProvider: coordinatorSamplerProvider)
        let observerCore = PassthroughCoreMock(context: .mockWith(applicationStateHistory: .mockAppInForeground()))
        let observer = DatadogProfiler(
            core: observerCore,
            profilingSamplerProvider: profilingSamplerProvider(isContinuousProfiling: true),
            quotaChecker: quotaChecker(),
            queue: profilerQueue,
            isAppLaunchProfilingEnabled: true
        )
        XCTAssertEqual(observer.role, .observer)
        XCTAssertEqual(dd_profiler_start(), 1)
        observerCore.set(context: ProfilingContext(status: .current))
        let longTask = DurationEvent(id: .mockRandom(), type: .longTask, start: 0, duration: 100)

        _ = observer.receive(
            message: .payload(LongTaskMessage(
                attributes: mockRandomAttributes(),
                longTask: longTask
            )),
            from: observerCore
        )
        flushQueue()
        XCTAssertTrue(observer.hasEventsOfInterest)
        XCTAssertEqual(
            try XCTUnwrap(observerCore.context.additionalContext(ofType: ProfilingContext.self)).status,
            .running
        )

        // When
        var observerContext = observerCore.context
        observerContext.trackingConsent = .notGranted
        observerCore.context = observerContext
        _ = observer.receive(message: .context(observerContext), from: observerCore)

        _ = observer.receive(
            message: .payload(LongTaskMessage(
                attributes: mockRandomAttributes(),
                longTask: longTask
            )),
            from: observerCore
        )
        flushQueue()

        // Then
        XCTAssertFalse(observer.hasEventsOfInterest)
        XCTAssertEqual(
            try XCTUnwrap(observerCore.context.additionalContext(ofType: ProfilingContext.self)).status,
            .stopped(reason: .manual)
        )

        // When - consent is granted again.
        observerContext = observerCore.context
        observerContext.trackingConsent = .granted
        observerCore.context = observerContext
        _ = observer.receive(message: .context(observerContext), from: observerCore)
        flushQueue()

        // Then - the observer publishes the shared native profiler status again.
        XCTAssertEqual(
            try XCTUnwrap(observerCore.context.additionalContext(ofType: ProfilingContext.self)).status,
            .running
        )

        // When - consent is revoked before the coordinator receives its sampling decision.
        observerContext = observerCore.context
        observerContext.trackingConsent = .notGranted
        observerCore.context = observerContext
        _ = observer.receive(message: .context(observerContext), from: observerCore)
        flushQueue()

        coordinatorSamplerProvider.updateWith(
            deterministicSampler: DeterministicSampler(uuid: .mockRandom(), samplingRate: 0)
        )
        _ = coordinator.receive(message: .context(core.context), from: core)
        flushQueue()

        // Then - the denied observer does not keep the sampled-out native profiler alive.
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_STOPPED)
        withExtendedLifetime(coordinator) {}
        withExtendedLifetime(observer) {}
    }

    func testApplicationDidEnterBackground_doesNothing_whenAppWasNeverInForeground() {
        // Given
        let profiler = continuousProfiler()
        dd_profiler_start_testing(100, false, 5.seconds.dd.toInt64Nanoseconds, 0)

        // App was only ever in background (e.g. UIScene based app)
        core.context = .mockWith(applicationStateHistory: .mockAppInBackground())

        // When
        _ = profiler.receive(message: .context(core.context), from: core)
        flushQueue()

        // Then
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_RUNNING)
        XCTAssertTrue(core.metadata.isEmpty)
        withExtendedLifetime(profiler) {}
    }

    func testApplicationDidEnterBackground_includesAccumulatedVitalsInProfile() throws {
        // Given
        let dateProvider = DateProviderMock()
        let profiler = continuousProfiler(dateProvider: dateProvider)
        dd_profiler_start_testing(100, false, 5.seconds.dd.toInt64Nanoseconds, 0)

        let startOperation = Vital.mockWith(id: .mockRandom(), name: "operation")
        let endOperation = Vital.mockWith(id: .mockRandom(), name: "operation", operationKey: startOperation.operationKey, stepType: .end)
        _ = profiler.receive(message: .payload(OperationMessage(attributes: mockRandomAttributes(), operation: startOperation)), from: core)
        _ = profiler.receive(message: .payload(OperationMessage(attributes: mockRandomAttributes(), operation: endOperation)), from: core)

        // When
        core.context = .mockWith(applicationStateHistory: .mockWith(
            initialState: .active,
            date: dateProvider.now.addingTimeInterval(-1),
            transitions: [(state: .background, date: dateProvider.now)]
        ))
        waitForProfileWrite {
            _ = profiler.receive(message: .context(core.context), from: core)
        }

        // Then
        let metadata = try XCTUnwrap(core.metadata.first as? ProfileAttachments)
        let rumEvents = try typedRUMEvents(from: metadata)
        let vitalIDs = eventIDs(ofType: "vital", in: rumEvents)
        XCTAssertTrue(vitalIDs.contains(startOperation.id))
        withExtendedLifetime(profiler) {}
    }

    func testApplicationDidEnterBackground_includesTTFDVitalFromOperationMessageInProfile() throws {
        // Given
        let dateProvider = DateProviderMock()
        let profiler = continuousProfiler(dateProvider: dateProvider)
        let ttfdVital = Vital.mockWith(
            id: "ttfd-id",
            name: "time_to_full_display",
            operationKey: nil,
            stepType: nil,
            date: dateProvider.now,
            duration: 2_000_000_000
        )

        dd_profiler_start_testing(100, false, 5.seconds.dd.toInt64Nanoseconds, 0)
        _ = profiler.receive(message: .payload(OperationMessage(attributes: mockRandomAttributes(), operation: ttfdVital)), from: core)

        // When
        core.context = .mockWith(applicationStateHistory: .mockWith(
            initialState: .active,
            date: dateProvider.now.addingTimeInterval(-1),
            transitions: [(state: .background, date: dateProvider.now)]
        ))
        waitForProfileWrite(timeout: 0.3) {
            _ = profiler.receive(message: .context(core.context), from: core)
        }

        // Then
        let metadata = try XCTUnwrap(core.metadata.first as? ProfileAttachments)
        let rumEvents = try typedRUMEvents(from: metadata)
        let vitalIDs = eventIDs(ofType: "vital", in: rumEvents)
        XCTAssertEqual(vitalIDs, ["ttfd-id"])

        let event = try XCTUnwrap(core.events.first as? ProfileEvent)
        let attributeVitalIDs = try XCTUnwrap(event.additionalAttributes?[RUMCoreContext.IDs.vitalID] as? [String])
        XCTAssertEqual(attributeVitalIDs, ["ttfd-id"])
        withExtendedLifetime(profiler) {}
    }

    func testApplicationDidEnterBackground_correctsAttachedVitalTimestampWithServerTimeOffset() throws {
        // Given
        let dateProvider = DateProviderMock()
        let profiler = continuousProfiler(dateProvider: dateProvider)
        let serverTimeOffset: TimeInterval = 2
        let startDate = Date(timeIntervalSince1970: 10)
        let startOperation = Vital.mockWith(
            id: "operation-id",
            name: "operation",
            operationKey: "key",
            stepType: .start,
            date: startDate,
            serverTimeOffset: serverTimeOffset
        )
        let endOperation = Vital.mockWith(
            id: "operation-end-id",
            name: "operation",
            operationKey: startOperation.operationKey,
            stepType: .end,
            date: startDate.addingTimeInterval(1),
            serverTimeOffset: serverTimeOffset
        )

        dd_profiler_start_testing(100, false, 5.seconds.dd.toInt64Nanoseconds, 0)

        _ = profiler.receive(
            message: .payload(
                OperationMessage(
                    attributes: mockRandomAttributes(),
                    operation: startOperation
                )
            ),
            from: core
        )
        _ = profiler.receive(
            message: .payload(
                OperationMessage(
                    attributes: mockRandomAttributes(),
                    operation: endOperation
                )
            ),
            from: core
        )

        // When
        core.context = .mockWith(
            serverTimeOffset: serverTimeOffset,
            applicationStateHistory: .mockWith(
                initialState: .active,
                date: dateProvider.now.addingTimeInterval(-1),
                transitions: [(state: .background, date: dateProvider.now)]
            )
        )
        waitForProfileWrite(timeout: 0.3) {
            _ = profiler.receive(message: .context(core.context), from: core)
        }

        // Then
        let metadata = try XCTUnwrap(core.metadata.first as? ProfileAttachments)
        let vitals = try typedRUMEvents(from: metadata).filter { $0["type"] as? String == "vital" }
        let start = try XCTUnwrap(vitals.first?["start_ns"] as? Int64)
        XCTAssertEqual(start, startDate.addingTimeInterval(serverTimeOffset).timeIntervalSince1970.dd.toInt64Nanoseconds)
        withExtendedLifetime(profiler) {}
    }

    func testApplicationDidEnterBackground_includesLongTasksInProfile() throws {
        // Given
        let dateProvider = DateProviderMock()
        let profilingSamplerProvider = profilingSamplerProvider(isContinuousProfiling: true)
        profilingSamplerProvider.updateWith(
            deterministicSampler: DeterministicSampler(uuid: .mockRandom(), samplingRate: .maxSampleRate)
        )
        let profiler = continuousProfiler(profilingSamplerProvider: profilingSamplerProvider, dateProvider: dateProvider)
        dd_profiler_start_testing(100, false, 5.seconds.dd.toInt64Nanoseconds, 0)

        let attributes: [AttributeKey: AttributeValue] = [
            RUMCoreContext.IDs.sessionID: "long-task-session-id",
            RUMCoreContext.IDs.viewID: "long-task-view-id"
        ]
        let longTask = DurationEvent(id: .mockRandom(), type: .longTask, start: 0, duration: 100)
        _ = profiler.receive(message: .payload(LongTaskMessage(attributes: attributes, longTask: longTask)), from: core)

        // When
        core.context = .mockWith(applicationStateHistory: .mockWith(
            initialState: .active,
            date: dateProvider.now.addingTimeInterval(-1),
            transitions: [(state: .background, date: dateProvider.now)]
        ))
        waitForProfileWrite {
            _ = profiler.receive(message: .context(core.context), from: core)
        }

        // Then
        let metadata = try XCTUnwrap(core.metadata.first as? ProfileAttachments)
        let rumEvents = try typedRUMEvents(from: metadata)
        XCTAssertEqual(eventIDs(ofType: "long_task", in: rumEvents), [longTask.id])
        let event = try XCTUnwrap(core.events.first as? ProfileEvent)
        XCTAssertEqual(event.additionalAttributes?[RUMCoreContext.IDs.sessionID] as? String, "long-task-session-id")
        XCTAssertEqual(event.additionalAttributes?[RUMCoreContext.IDs.viewID] as? String, "long-task-view-id")
        withExtendedLifetime(profiler) {}
    }

    func testApplicationDidEnterBackground_includesAppHangsInProfile() throws {
        // Given
        let dateProvider = DateProviderMock()
        let profilingSamplerProvider = profilingSamplerProvider(isContinuousProfiling: true)
        profilingSamplerProvider.updateWith(
            deterministicSampler: DeterministicSampler(uuid: .mockRandom(), samplingRate: .maxSampleRate)
        )
        let profiler = continuousProfiler(profilingSamplerProvider: profilingSamplerProvider, dateProvider: dateProvider)
        dd_profiler_start_testing(100, false, 5.seconds.dd.toInt64Nanoseconds, 0)

        let attributes: [AttributeKey: AttributeValue] = [
            RUMCoreContext.IDs.sessionID: "app-hang-session-id",
            RUMCoreContext.IDs.viewID: "app-hang-view-id"
        ]
        let hang = DurationEvent(id: .mockRandom(), type: .error, start: 0, duration: 500)
        XCTAssertTrue(profiler.receive(message: .payload(AppHangMessage(attributes: attributes, hang: hang)), from: core))

        // When
        core.context = .mockWith(applicationStateHistory: .mockWith(
            initialState: .active,
            date: dateProvider.now.addingTimeInterval(-1),
            transitions: [(state: .background, date: dateProvider.now)]
        ))
        waitForProfileWrite {
            _ = profiler.receive(message: .context(core.context), from: core)
        }

        // Then
        let metadata = try XCTUnwrap(core.metadata.first as? ProfileAttachments)
        let rumEvents = try typedRUMEvents(from: metadata)
        XCTAssertEqual(eventIDs(ofType: "error", in: rumEvents), [hang.id])
        let event = try XCTUnwrap(core.events.first as? ProfileEvent)
        XCTAssertEqual(event.additionalAttributes?[RUMCoreContext.IDs.sessionID] as? String, "app-hang-session-id")
        XCTAssertEqual(event.additionalAttributes?[RUMCoreContext.IDs.viewID] as? String, "app-hang-view-id")
        withExtendedLifetime(profiler) {}
    }
}

// MARK: - Sampling Decisions

extension DatadogProfilerTests {
    func testContinuousProfiler_doesNotStartProfilerAtInit_whenWaitingForInitialContext() {
        // Given
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_NOT_CREATED)

        // When
        let profiler = continuousProfiler()

        // Then
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_NOT_CREATED)
        withExtendedLifetime(profiler) {}
    }

    func testContinuousProfiler_doesNotStartProfilerAtInit_whenInitialConditionsPreventProfiling() {
        // Given
        core = PassthroughCoreMock(context: .mockWith(applicationStateHistory: .mockAppInBackground()))
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_NOT_CREATED)

        // When
        let profiler = continuousProfiler()

        // Then
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_NOT_CREATED)
        withExtendedLifetime(profiler) {}
    }

    func testReceiveContext_startsContinuousProfiler_whenSamplingDecisionIsNotReceived() {
        // Given
        core = PassthroughCoreMock(context: .mockWith(applicationStateHistory: .mockAppInBackground()))
        let profilingSamplerProvider = profilingSamplerProvider(isContinuousProfiling: true)
        let profiler = continuousProfiler(
            profilingSamplerProvider: profilingSamplerProvider,
            isAppLaunchProfilingEnabled: true
        )
        connectMessageReceiver(to: profiler, profilingSamplerProvider: profilingSamplerProvider)
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_NOT_CREATED)

        // When
        core.context = .mockWith(applicationStateHistory: .mockAppInForeground())
        flushQueue()

        // Then
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_RUNNING)
        withExtendedLifetime(profiler) {}
    }

    func testReceiveContext_startsContinuousProfiler_whenSessionIsSampledIn() {
        // Given
        core = PassthroughCoreMock(context: .mockWith(applicationStateHistory: .mockAppInBackground()))
        let profilingSamplerProvider = profilingSamplerProvider(isContinuousProfiling: true)
        let profiler = continuousProfiler(profilingSamplerProvider: profilingSamplerProvider)
        connectMessageReceiver(to: profiler, profilingSamplerProvider: profilingSamplerProvider)
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_NOT_CREATED)

        // When
        core.context = .mockWith(
            applicationStateHistory: .mockAppInForeground(),
            additionalContext: [RUMCoreContext.mockWith(sessionSampleRate: .maxSampleRate)]
        )
        flushQueue()

        // Then
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_RUNNING)
        withExtendedLifetime(profiler) {}
    }

    func testReceiveContext_stopsWithoutWriting_whenSessionSamplesOutBeforeTTID() {
        // Given
        core = PassthroughCoreMock(context: .mockWith(applicationStateHistory: .mockAppInBackground()))
        let profilingSamplerProvider = profilingSamplerProvider(isContinuousProfiling: true)
        let dateProvider = DateProviderMock()
        let profiler = continuousProfiler(
            profilingSamplerProvider: profilingSamplerProvider,
            dateProvider: dateProvider
        )
        connectMessageReceiver(to: profiler, profilingSamplerProvider: profilingSamplerProvider)
        core.context = .mockWith(
            applicationStateHistory: .mockAppInForeground()
        )
        flushQueue()
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_RUNNING)

        // When - continuous profiling samples out before TTID.
        core.context = .mockWith(
            applicationStateHistory: .mockAppInForeground(),
            additionalContext: [RUMCoreContext.mockWith(sessionSampleRate: 0)]
        )
        flushQueue()

        // Then
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_STOPPED)

        // When - TTID arrives before the app moves to background.
        _ = profiler.receive(
            message: .payload(TTIDMessage(attributes: mockRandomAttributes(), ttid: .mockWith(stepType: nil))),
            from: core
        )

        waitForProfileWrite(expectingWrite: false, timeout: 0.15) {
            core.context = .mockWith(
                applicationStateHistory: .mockWith(
                    initialState: .active,
                    date: dateProvider.now.addingTimeInterval(-1),
                    transitions: [(state: .background, date: dateProvider.now)]
                ),
                additionalContext: [RUMCoreContext.mockWith(sessionSampleRate: 0)]
            )
            flushQueue()
        }

        // Then - TTID alone does not admit the stopped optimistic profile as custom profiling.
        XCTAssertTrue(core.metadata.isEmpty)
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_STOPPED)
        withExtendedLifetime(profiler) {}
    }

    func testReceiveContext_writesAppLaunchProfile_whenTTIDIsReceivedBeforeSessionSamplesOut() throws {
        // Given
        core = PassthroughCoreMock(context: .mockWith(applicationStateHistory: .mockAppInBackground()))
        let profilingSamplerProvider = profilingSamplerProvider(isContinuousProfiling: true)
        let profiler = continuousProfiler(
            profilingSamplerProvider: profilingSamplerProvider,
            isAppLaunchProfilingEnabled: true
        )
        connectMessageReceiver(to: profiler, profilingSamplerProvider: profilingSamplerProvider)
        core.context = .mockWith(applicationStateHistory: .mockAppInForeground())
        flushQueue()
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_RUNNING)

        let launchVital = Vital.mockWith(id: "ttid-id", name: "time_to_initial_display", stepType: nil)
        _ = profiler.receive(
            message: .payload(TTIDMessage(attributes: mockRandomAttributes(), ttid: launchVital)),
            from: core
        )
        flushQueue()
        XCTAssertTrue(core.metadata.isEmpty)

        // When - the first RUM sampling decision arrives after TTID and samples continuous profiling out.
        waitForProfileWrite(timeout: 1.0) {
            core.context = .mockWith(
                applicationStateHistory: .mockAppInForeground(),
                additionalContext: [RUMCoreContext.mockWith(sessionSampleRate: 0)]
            )
        }

        // Then - the already captured TTID is written as the standalone app-launch profile.
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_STOPPED)
        let metadata = try XCTUnwrap(core.metadata.first as? ProfileAttachments)
        let rumEvents = try typedRUMEvents(from: metadata)
        XCTAssertEqual(eventIDs(ofType: "vital", in: rumEvents), ["ttid-id"])
        let event = try XCTUnwrap(core.events.first as? ProfileEvent)
        XCTAssertTrue(event.tags.contains("operation:launch"))
        withExtendedLifetime(profiler) {}
    }

    func testReceiveContext_keepsNativeProfilerRunning_whenSessionIsSampledOutBeforeAppLaunchVital() throws {
        // Given
        core = PassthroughCoreMock(context: .mockWith(applicationStateHistory: .mockAppInBackground()))
        let observerCore = PassthroughCoreMock()
        let coordinatorSamplerProvider = profilingSamplerProvider(isContinuousProfiling: true)
        let profiler = continuousProfiler(
            profilingSamplerProvider: coordinatorSamplerProvider,
            isAppLaunchProfilingEnabled: false
        )
        let observer = DatadogProfiler(
            core: observerCore,
            profilingSamplerProvider: profilingSamplerProvider(isContinuousProfiling: false),
            quotaChecker: quotaChecker(),
            queue: profilerQueue,
            isAppLaunchProfilingEnabled: true
        )
        connectMessageReceiver(to: profiler, profilingSamplerProvider: coordinatorSamplerProvider)
        core.context = .mockWith(applicationStateHistory: .mockAppInForeground())
        flushQueue()
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_RUNNING)

        // When - the RUM session samples out before TTID can harvest app-launch.
        core.context = .mockWith(
            applicationStateHistory: .mockAppInForeground(),
            additionalContext: [RUMCoreContext.mockWith(sessionSampleRate: 0)]
        )
        flushQueue()

        // Then - observer app-launch profiling keeps the shared native profiler alive.
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_RUNNING)

        // When - TTID is processed.
        let observerWriteExpectation = expectation(description: "observer app-launch profile write")
        observerCore.onEventWriteContext = { _ in observerWriteExpectation.fulfill() }
        defer { observerCore.onEventWriteContext = nil }

        _ = profiler.receive(
            message: .payload(TTIDMessage(attributes: mockRandomAttributes(), ttid: .mockWith(stepType: nil))),
            from: core
        )
        flushQueue()
        _ = observer.receive(
            message: .payload(TTIDMessage(
                attributes: mockRandomAttributes(),
                ttid: .mockWith(id: "observer-ttid-id", stepType: nil)
            )),
            from: observerCore
        )

        // Then - the sampled-out continuous profiler can stop after app-launch harvesting.
        waitForExpectations(timeout: 1.0)
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_STOPPED)
        XCTAssertTrue(core.events.isEmpty)
        XCTAssertEqual(observerCore.events.count, 1)
        let observerMetadata = try XCTUnwrap(observerCore.metadata.first as? ProfileAttachments)
        XCTAssertEqual(eventIDs(ofType: "vital", in: try typedRUMEvents(from: observerMetadata)), ["observer-ttid-id"])
        withExtendedLifetime(profiler) {}
        withExtendedLifetime(observer) {}
    }

    func testReceiveOperationStart_afterContinuousProfilingSamplesOut_doesNotStartCustomProfiling() {
        // Given
        core = PassthroughCoreMock(context: .mockWith(applicationStateHistory: .mockAppInBackground()))
        let profilingSamplerProvider = profilingSamplerProvider(isContinuousProfiling: true)
        let dateProvider = DateProviderMock()
        let profiler = continuousProfiler(
            profilingSamplerProvider: profilingSamplerProvider,
            dateProvider: dateProvider
        )
        connectMessageReceiver(to: profiler, profilingSamplerProvider: profilingSamplerProvider)
        core.context = .mockWith(applicationStateHistory: .mockAppInForeground())
        flushQueue()
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_RUNNING)
        _ = profiler.receive(
            message: .payload(TTIDMessage(attributes: mockRandomAttributes(), ttid: .mockWith(stepType: nil))),
            from: core
        )

        core.context = .mockWith(
            applicationStateHistory: .mockAppInForeground(),
            additionalContext: [RUMCoreContext.mockWith(sessionSampleRate: 0)]
        )
        flushQueue()
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_STOPPED)

        let startOperation = Vital.mockWith(stepType: .start, date: dateProvider.now)

        // When
        _ = profiler.receive(
            message: .payload(OperationMessage(attributes: mockRandomAttributes(), operation: startOperation)),
            from: core
        )
        flushQueue()

        // Then
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_STOPPED)
        withExtendedLifetime(profiler) {}
    }

    func testReceiveOperationStartWhenContinuousProfilingSamplesOut_doesNotStartProfiler() {
        // Given
        dd_profiler_start_testing(0, false, 5.seconds.dd.toInt64Nanoseconds, 0)
        let dateProvider = DateProviderMock()
        let profilingSamplerProvider = profilingSamplerProvider(isContinuousProfiling: true)
        profilingSamplerProvider.updateWith(
            deterministicSampler: DeterministicSampler(uuid: .mockRandom(), samplingRate: 0)
        )
        let profiler = continuousProfiler(
            profilingSamplerProvider: profilingSamplerProvider,
            dateProvider: dateProvider
        )
        shareCurrentContext(with: profiler)
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_NOT_STARTED)

        let startOperation = Vital.mockWith(stepType: .start, date: dateProvider.now)

        // When
        _ = profiler.receive(
            message: .payload(OperationMessage(attributes: mockRandomAttributes(), operation: startOperation)),
            from: core
        )
        flushQueue()

        // Then
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_NOT_STARTED)
        withExtendedLifetime(profiler) {}
    }

    func testTimer_stopsContinuousProfiler_whenSamplingDecisionIsNotReceived_andGraceExpires() {
        // Given
        core = PassthroughCoreMock(context: .mockWith(applicationStateHistory: .mockAppInBackground()))
        let profilingSamplerProvider = profilingSamplerProvider(isContinuousProfiling: true)
        let profiler = continuousProfiler(
            profilingSamplerProvider: profilingSamplerProvider,
            profilingInterval: 0.05
        )
        connectMessageReceiver(to: profiler, profilingSamplerProvider: profilingSamplerProvider)
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_NOT_CREATED)

        // When
        core.context = .mockWith(applicationStateHistory: .mockAppInForeground())
        flushQueue()
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_RUNNING)
        waitUntil(timeout: 1.0) {
            dd_profiler_get_status() == DD_PROFILER_STATUS_STOPPED
        }

        // Then
        XCTAssertTrue(core.metadata.isEmpty)
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_STOPPED)
        withExtendedLifetime(profiler) {}
    }

    func testReceiveContext_restartsContinuousProfiler_afterNativeTimeout() {
        // Given
        let profilingSamplerProvider = profilingSamplerProvider(isContinuousProfiling: true)
        profilingSamplerProvider.updateWith(
            deterministicSampler: DeterministicSampler(uuid: .mockRandom(), samplingRate: .maxSampleRate)
        )
        let profiler = continuousProfiler(profilingSamplerProvider: profilingSamplerProvider)
        dd_profiler_start_testing(100, false, 0, 0)

        let samplingExpectation = expectation(description: "native samples collected")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
            samplingExpectation.fulfill()
        }
        waitForExpectations(timeout: 1.0)

        let timedOutProfile = dd_profiler_flush_and_get_profile()
        dd_pprof_destroy(timedOutProfile)
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_TIMEOUT)

        // When - the next eligible context is received.
        core.context = .mockWith(
            applicationStateHistory: .mockAppInForeground(),
            additionalContext: [RUMCoreContext.mockWith(sessionSampleRate: .maxSampleRate)]
        )
        shareCurrentContext(with: profiler)

        // Then
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_RUNNING)
        withExtendedLifetime(profiler) {}
    }

    func testWritesProfileInCustomProfiling_evenIfContinuousProfileIsNotSampled() {
        // Given
        let dateProvider = DateProviderMock()
        let profilingSamplerProvider = profilingSamplerProvider(isContinuousProfiling: true)
        profilingSamplerProvider.updateWith(
            deterministicSampler: DeterministicSampler(uuid: .mockRandom(), samplingRate: 0)
        )
        let profiler = continuousProfiler(profilingSamplerProvider: profilingSamplerProvider, dateProvider: dateProvider)
        let startOperation = Vital.mockWith(name: "operation")
        let endOperation = Vital.mockWith(
            name: startOperation.name,
            operationKey: startOperation.operationKey,
            stepType: .end
        )
        dd_profiler_start_testing(100, false, 5.seconds.dd.toInt64Nanoseconds, 0)

        _ = profiler.receive(message: .payload(OperationMessage(attributes: mockRandomAttributes(), operation: startOperation)), from: core)
        _ = profiler.receive(message: .payload(OperationMessage(attributes: mockRandomAttributes(), operation: endOperation)), from: core)

        // When
        core.context = .mockWith(applicationStateHistory: .mockWith(
            initialState: .active,
            date: dateProvider.now.addingTimeInterval(-1),
            transitions: [(state: .background, date: dateProvider.now)]
        ))
        waitForProfileWrite {
            _ = profiler.receive(message: .context(core.context), from: core)
        }

        // Then
        XCTAssertFalse(core.metadata.isEmpty)
        withExtendedLifetime(profiler) {}
    }

    func testWritesProfileOnTimer_whenContinuousProfileIsNotSampled_andOperationsComplete() {
        // Given
        let initialDate = Date().addingTimeInterval(-(DatadogProfiler.Constants.minProfileDuration + 3))
        let dateProvider = DateProviderMock(now: initialDate)
        core.context = .mockWith(applicationStateHistory: .mockAppInForeground(since: initialDate.addingTimeInterval(-1)))

        let profilingSamplerProvider = profilingSamplerProvider(isContinuousProfiling: true)
        profilingSamplerProvider.updateWith(
            deterministicSampler: DeterministicSampler(uuid: .mockRandom(), samplingRate: 0)
        )
        let profiler = continuousProfiler(
            profilingSamplerProvider: profilingSamplerProvider,
            dateProvider: dateProvider
        )
        core.context = .mockWith(
            applicationStateHistory: .mockAppInForeground(),
            additionalContext: [RUMCoreContext.mockWith(sessionSampleRate: .maxSampleRate)]
        )
        shareCurrentContext(with: profiler)
        dd_profiler_start_testing(100, false, 5.seconds.dd.toInt64Nanoseconds, 0)
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_RUNNING)

        let startOperation = Vital.mockWith(stepType: .start, date: dateProvider.now)
        _ = profiler.receive(
            message: .payload(OperationMessage(attributes: mockRandomAttributes(), operation: startOperation)),
            from: core
        )
        flushQueue()
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_RUNNING)

        dateProvider.now = dateProvider.now.addingTimeInterval(DatadogProfiler.Constants.minProfileDuration + 1)

        let endOperation = Vital.mockWith(
            name: startOperation.name,
            operationKey: startOperation.operationKey,
            stepType: .end
        )

        // When - operations complete, sampled-out continuous profiling should use the custom timer path.
        _ = profiler.receive(
            message: .payload(OperationMessage(attributes: mockRandomAttributes(), operation: endOperation)),
            from: core
        )
        waitUntil(timeout: 1.0) {
            dd_profiler_get_status() == DD_PROFILER_STATUS_STOPPED && core.metadata.isEmpty == false
        }

        // Then
        XCTAssertFalse(core.metadata.isEmpty)
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_STOPPED)
        withExtendedLifetime(profiler) {}
    }
}

// MARK: - Write Decisions

extension DatadogProfilerTests {
    func testDoesNotWriteProfile_whenNoEventsAccumulated() {
        // Given
        let dateProvider = DateProviderMock()
        let profiler = continuousProfiler(dateProvider: dateProvider)
        dd_profiler_start_testing(100, false, 5.seconds.dd.toInt64Nanoseconds, 0)

        // When
        core.context = .mockWith(applicationStateHistory: .mockWith(
            initialState: .active,
            date: dateProvider.now.addingTimeInterval(-1),
            transitions: [(state: .background, date: dateProvider.now)]
        ))
        waitForProfileWrite(expectingWrite: false) {
            _ = profiler.receive(message: .context(core.context), from: core)
        }

        // Then
        XCTAssertTrue(core.metadata.isEmpty)
        withExtendedLifetime(profiler) {}
    }

    func testDoesNotWriteProfile_whenNoEventsAccumulated_onTimerCycle() {
        // Given
        let profilingSamplerProvider = profilingSamplerProvider(isContinuousProfiling: true)
        profilingSamplerProvider.updateWith(
            deterministicSampler: DeterministicSampler(uuid: .mockRandom(), samplingRate: .maxSampleRate)
        )
        let profiler = continuousProfiler(
            profilingSamplerProvider: profilingSamplerProvider,
            profilingInterval: 0.05
        )
        dd_profiler_start_testing(100, false, 5.seconds.dd.toInt64Nanoseconds, 0)

        // When
        waitForProfileWrite(expectingWrite: false, timeout: 0.15) {}

        // Then
        XCTAssertTrue(core.metadata.isEmpty)
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_RUNNING)
        withExtendedLifetime(profiler) {}
    }

    func testWritesProfile_whenRUMOperationsAccumulated() {
        // Given
        let dateProvider = DateProviderMock()
        let profiler = continuousProfiler(dateProvider: dateProvider)
        dd_profiler_start_testing(100, false, 5.seconds.dd.toInt64Nanoseconds, 0)

        let startOperation = Vital.mockWith(name: "operation")
        let endOperation = Vital.mockWith(name: "operation", operationKey: startOperation.operationKey, stepType: .end)
        _ = profiler.receive(message: .payload(OperationMessage(attributes: mockRandomAttributes(), operation: startOperation)), from: core)
        _ = profiler.receive(message: .payload(OperationMessage(attributes: mockRandomAttributes(), operation: endOperation)), from: core)

        // When
        core.context = .mockWith(applicationStateHistory: .mockWith(
            initialState: .active,
            date: dateProvider.now.addingTimeInterval(-1),
            transitions: [(state: .background, date: dateProvider.now)]
        ))
        waitForProfileWrite(timeout: 0.3) {
            _ = profiler.receive(message: .context(core.context), from: core)
        }

        // Then
        XCTAssertFalse(core.metadata.isEmpty)
        withExtendedLifetime(profiler) {}
    }

    func testDoesNotWriteProfile_whenOnlyLongTasksAccumulated() {
        // Given
        let dateProvider = DateProviderMock()
        let profiler = continuousProfiler(dateProvider: dateProvider)
        let longTask = DurationEvent(id: .mockRandom(), type: .longTask, start: 0, duration: 100)
        dd_profiler_start_testing(100, false, 5.seconds.dd.toInt64Nanoseconds, 0)

        _ = profiler.receive(message: .payload(LongTaskMessage(attributes: mockRandomAttributes(), longTask: longTask)), from: core)

        // When
        core.context = .mockWith(applicationStateHistory: .mockWith(
            initialState: .active,
            date: dateProvider.now.addingTimeInterval(-1),
            transitions: [(state: .background, date: dateProvider.now)]
        ))
        waitForProfileWrite(expectingWrite: false) {
            _ = profiler.receive(message: .context(core.context), from: core)
        }

        // Then
        XCTAssertTrue(core.metadata.isEmpty)
        withExtendedLifetime(profiler) {}
    }

    func testDoesNotWriteProfile_whenOnlyAppHangsAccumulated() {
        // Given
        let dateProvider = DateProviderMock()
        let profiler = continuousProfiler(dateProvider: dateProvider)
        let hang = DurationEvent(id: .mockRandom(), type: .error, start: 0, duration: 500)
        dd_profiler_start_testing(100, false, 5.seconds.dd.toInt64Nanoseconds, 0)

        _ = profiler.receive(message: .payload(AppHangMessage(attributes: mockRandomAttributes(), hang: hang)), from: core)

        // When
        core.context = .mockWith(applicationStateHistory: .mockWith(
            initialState: .active,
            date: dateProvider.now.addingTimeInterval(-1),
            transitions: [(state: .background, date: dateProvider.now)]
        ))
        waitForProfileWrite(expectingWrite: false) {
            _ = profiler.receive(message: .context(core.context), from: core)
        }

        // Then
        XCTAssertTrue(core.metadata.isEmpty)
        withExtendedLifetime(profiler) {}
    }

    func testDoesNotWriteProfile_whenAppHangsAndLongTasksAccumulated_butContinuousProfilingIsSampledOut() {
        // Given
        let dateProvider = DateProviderMock()
        let profilingSamplerProvider = profilingSamplerProvider(isContinuousProfiling: true)
        profilingSamplerProvider.updateWith(
            deterministicSampler: DeterministicSampler(uuid: .mockRandom(), samplingRate: 0)
        )
        let profiler = continuousProfiler(profilingSamplerProvider: profilingSamplerProvider, dateProvider: dateProvider)
        let hang = DurationEvent(id: .mockRandom(), type: .error, start: 0, duration: 500)
        let longTask = DurationEvent(id: .mockRandom(), type: .longTask, start: 0, duration: 100)
        dd_profiler_start_testing(100, false, 5.seconds.dd.toInt64Nanoseconds, 0)

        _ = profiler.receive(message: .payload(AppHangMessage(attributes: mockRandomAttributes(), hang: hang)), from: core)
        _ = profiler.receive(message: .payload(LongTaskMessage(attributes: mockRandomAttributes(), longTask: longTask)), from: core)

        // When
        core.context = .mockWith(applicationStateHistory: .mockWith(
            initialState: .active,
            date: dateProvider.now.addingTimeInterval(-1),
            transitions: [(state: .background, date: dateProvider.now)]
        ))
        waitForProfileWrite(expectingWrite: false) {
            _ = profiler.receive(message: .context(core.context), from: core)
        }

        // Then
        XCTAssertTrue(core.metadata.isEmpty)
        withExtendedLifetime(profiler) {}
    }

    func testApplicationWillEnterForeground_restartsProfilerAfterBackground_whenContinuousProfilingIsSampledIn() {
        // Given
        let dateProvider = DateProviderMock()
        let profilingSamplerProvider = profilingSamplerProvider(isContinuousProfiling: true)
        profilingSamplerProvider.updateWith(
            deterministicSampler: DeterministicSampler(uuid: .mockRandom(), samplingRate: .maxSampleRate)
        )
        let profiler = continuousProfiler(
            profilingSamplerProvider: profilingSamplerProvider,
            dateProvider: dateProvider
        )
        dd_profiler_start_testing(100, false, 5.seconds.dd.toInt64Nanoseconds, 0)
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_RUNNING)

        // Send background context to stop the profiler and record the state transition
        core.context = .mockWith(applicationStateHistory: .mockWith(
            initialState: .active,
            date: dateProvider.now.addingTimeInterval(-1),
            transitions: [(state: .background, date: dateProvider.now)]
        ))
        _ = profiler.receive(message: .context(core.context), from: core)
        flushQueue()
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_STOPPED)

        // When - enter foreground
        core.context = .mockWith(applicationStateHistory: .mockWith(
            initialState: .active,
            date: dateProvider.now.addingTimeInterval(-2),
            transitions: [
                (state: .background, date: dateProvider.now.addingTimeInterval(-1)),
                (state: .inactive, date: dateProvider.now)
            ]
        ))
        _ = profiler.receive(message: .context(core.context), from: core)
        flushQueue()

        // Then
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_RUNNING)
        withExtendedLifetime(profiler) {}
    }

    func testApplicationWillEnterForeground_doesNotRestartProfilerAfterBackground_whenContinuousProfilingSamplingDecisionIsNotReceived() {
        // Given
        let dateProvider = DateProviderMock()
        let profiler = continuousProfiler(dateProvider: dateProvider)
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_NOT_CREATED)

        // Send background context to record the state transition
        core.context = .mockWith(applicationStateHistory: .mockWith(
            initialState: .active,
            date: dateProvider.now.addingTimeInterval(-1),
            transitions: [(state: .background, date: dateProvider.now)]
        ))
        _ = profiler.receive(message: .context(core.context), from: core)
        flushQueue()
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_NOT_CREATED)

        // When - enter foreground with no sampling decision and no ongoing operation
        core.context = .mockWith(applicationStateHistory: .mockWith(
            initialState: .active,
            date: dateProvider.now.addingTimeInterval(-2),
            transitions: [
                (state: .background, date: dateProvider.now.addingTimeInterval(-1)),
                (state: .inactive, date: dateProvider.now)
            ]
        ))
        _ = profiler.receive(message: .context(core.context), from: core)
        flushQueue()

        // Then
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_NOT_CREATED)
        withExtendedLifetime(profiler) {}
    }
}

// MARK: - Custom Profiling

extension DatadogProfilerTests {
    func testCustomProfiler_doesNotStartProfilerAtInit() {
        // Given
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_NOT_CREATED)

        // When
        let profiler = customProfiler()

        // Then
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_NOT_CREATED, "Custom profiler should not start at init")
        withExtendedLifetime(profiler) {}
    }

    func testCustomProfiler_doesNotStartProfilerOnFirstRUMOperationStart() {
        // Given
        dd_profiler_start_testing(0, false, 5.seconds.dd.toInt64Nanoseconds, 0)
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_NOT_STARTED)

        let dateProvider = DateProviderMock()
        let profiler = customProfiler(dateProvider: dateProvider)

        // When
        let operation = Vital.mockWith(stepType: .start, date: dateProvider.now + 1)
        _ = profiler.receive(
            message: .payload(
                OperationMessage(
                    attributes: mockRandomAttributes(),
                    operation: operation
                )
            ),
            from: core
        )
        flushQueue()

        // Then
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_NOT_STARTED)

        // When
        _ = profiler.receive(
            message: .payload(
                OperationMessage(
                    attributes: mockRandomAttributes(),
                    operation: .mockWith(
                        name: operation.name,
                        operationKey: operation.operationKey,
                        stepType: .end,
                        date: dateProvider.now + 2
                    )
                )
            ),
            from: core
        )
        flushQueue()

        dd_profiler_start_testing(100, false, 5.seconds.dd.toInt64Nanoseconds, 0)
        core.context = .mockWith(applicationStateHistory: .mockWith(
            initialState: .active,
            date: dateProvider.now.addingTimeInterval(-1),
            transitions: [(state: .background, date: dateProvider.now)]
        ))
        waitForProfileWrite(expectingWrite: false) {
            _ = profiler.receive(message: .context(core.context), from: core)
        }

        // Then
        XCTAssertTrue(core.metadata.isEmpty)
        withExtendedLifetime(profiler) {}
    }

    func testCustomProfiler_doesNotRestartProfilerStoppedByContextOnOperation() {
        // Given
        dd_profiler_start_testing(100, false, 5.seconds.dd.toInt64Nanoseconds, 0)
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_RUNNING)

        let dateProvider = DateProviderMock()
        let profiler = customProfiler(dateProvider: dateProvider)
        shareCurrentContext(with: profiler)
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_STOPPED)

        // When
        _ = profiler.receive(
            message: .payload(
                OperationMessage(
                    attributes: mockRandomAttributes(),
                    operation: .mockWith(stepType: .start, date: dateProvider.now + 1)
                )
            ),
            from: core
        )
        flushQueue()

        // Then - custom operation does not restart the stopped profiler.
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_STOPPED)
        withExtendedLifetime(profiler) {}
    }

    func testCustomProfiler_beforeReceivingAppLaunchVital() {
        // Given
        let profiler = customProfiler()
        let longTask = DurationEvent(id: .mockRandom(), type: .longTask, start: 0, duration: 100)
        let hang = DurationEvent(id: .mockRandom(), type: .error, start: 0, duration: 500)
        let operation: Vital = .mockWith(stepType: .start)

        // Then
        XCTAssertTrue(profiler.receive(message: .payload(LongTaskMessage(attributes: mockRandomAttributes(), longTask: longTask)), from: core))
        XCTAssertTrue(profiler.receive(message: .payload(AppHangMessage(attributes: mockRandomAttributes(), hang: hang)), from: core))
        XCTAssertFalse(profiler.receive(message: .payload(OperationMessage(attributes: mockRandomAttributes(), operation: operation)), from: core))
        withExtendedLifetime(profiler) {}
    }

    func testCustomProfiler_doesNotWriteProfile_whenNoEventsAccumulated() {
        // Given
        let dateProvider = DateProviderMock()
        let profiler = customProfiler(dateProvider: dateProvider)
        dd_profiler_start_testing(100, false, 5.seconds.dd.toInt64Nanoseconds, 0)

        // When - background context with no accumulated events
        core.context = .mockWith(applicationStateHistory: .mockWith(
            initialState: .active,
            date: dateProvider.now.addingTimeInterval(-1),
            transitions: [(state: .background, date: dateProvider.now)]
        ))
        waitForProfileWrite(expectingWrite: false) {
            _ = profiler.receive(message: .context(core.context), from: core)
        }

        // Then
        XCTAssertTrue(core.metadata.isEmpty)
        withExtendedLifetime(profiler) {}
    }

    func testCustomProfiler_writesProfile_whenRUMOperationsAccumulated() {
        // Given
        // Start dateProvider 8 seconds in the past so that after advancing by minProfileDuration+1,
        // the resulting fireDate is still in the past and the timer fires immediately.
        let initialDate = Date().addingTimeInterval(-(DatadogProfiler.Constants.minProfileDuration + 3))
        let dateProvider = DateProviderMock(now: initialDate)
        // Ensure core.context has an active state that falls within dateProvider.now's range
        core.context = .mockWith(applicationStateHistory: .mockAppInForeground(since: initialDate.addingTimeInterval(-1)))
        let profiler = customProfiler(dateProvider: dateProvider)
        shareCurrentContext(with: profiler)
        dd_profiler_start_testing(100, false, 5.seconds.dd.toInt64Nanoseconds, 0)
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_RUNNING)

        let startOp: Vital = .mockWith(stepType: .start, date: dateProvider.now)
        _ = profiler.receive(message: .payload(OperationMessage(attributes: mockRandomAttributes(), operation: startOp)), from: core)
        flushQueue()
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_RUNNING)

        // Advance dateProvider by minProfileDuration+1 — the result is still in the past,
        // so fireTimer(after: 0) sets a past fireDate and the timer fires immediately.
        dateProvider.now = dateProvider.now.addingTimeInterval(DatadogProfiler.Constants.minProfileDuration + 1)

        let endOp: Vital = .mockWith(name: startOp.name, operationKey: startOp.operationKey, stepType: .end)

        // When - operations complete, profiler stops and writes via timer (no background notification needed)
        _ = profiler.receive(message: .payload(OperationMessage(attributes: mockRandomAttributes(), operation: endOp)), from: core)
        waitUntil(timeout: 1.0) {
            dd_profiler_get_status() == DD_PROFILER_STATUS_STOPPED && core.metadata.isEmpty == false
        }

        // Then
        XCTAssertFalse(core.metadata.isEmpty)
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_STOPPED)
        withExtendedLifetime(profiler) {}
    }

    func testCustomProfiler_includesVitalsInProfile_whenOperationsComplete() throws {
        // Given
        let initialDate = Date().addingTimeInterval(-(DatadogProfiler.Constants.minProfileDuration + 3))
        let dateProvider = DateProviderMock(now: initialDate)
        core.context = .mockWith(applicationStateHistory: .mockAppInForeground(since: initialDate.addingTimeInterval(-1)))
        let profiler = customProfiler(dateProvider: dateProvider)
        shareCurrentContext(with: profiler)
        dd_profiler_start_testing(100, false, 5.seconds.dd.toInt64Nanoseconds, 0)

        let startOp = Vital.mockWith(id: "start-id", name: "operation", stepType: .start, date: dateProvider.now)
        let orphanedEnd = Vital.mockWith(id: "orphan-id", name: "other-operation", stepType: .end, date: dateProvider.now)
        _ = profiler.receive(message: .payload(OperationMessage(attributes: mockRandomAttributes(), operation: startOp)), from: core)
        _ = profiler.receive(message: .payload(OperationMessage(attributes: mockRandomAttributes(), operation: orphanedEnd)), from: core)
        flushQueue()

        dateProvider.now = dateProvider.now.addingTimeInterval(DatadogProfiler.Constants.minProfileDuration + 1)

        let launchVital = Vital.mockWith(id: "ttid-id", name: "time_to_initial_display", stepType: nil)
        _ = profiler.receive(message: .payload(TTIDMessage(attributes: mockRandomAttributes(), ttid: launchVital)), from: core)

        let endOp = Vital.mockWith(id: "end-id", name: startOp.name, operationKey: startOp.operationKey, stepType: .end)

        // When
        _ = profiler.receive(message: .payload(OperationMessage(attributes: mockRandomAttributes(), operation: endOp)), from: core)
        waitUntil(timeout: 1.0) {
            dd_profiler_get_status() == DD_PROFILER_STATUS_STOPPED && core.metadata.isEmpty == false
        }

        // Then
        let metadata = try XCTUnwrap(core.metadata.first as? ProfileAttachments)
        let rumEvents = try typedRUMEvents(from: metadata)
        let vitalIDs = eventIDs(ofType: "vital", in: rumEvents)
        XCTAssertEqual(Set(vitalIDs), Set(["start-id", "ttid-id"]))
        XCTAssertFalse(vitalIDs.contains("orphan-id"))
        let event = try XCTUnwrap(core.events.first as? ProfileEvent)
        XCTAssertTrue(event.tags.contains("operation:custom"))
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_STOPPED)
        withExtendedLifetime(profiler) {}
    }

    func testCustomProfiler_doesNotStartProfiler_onEndOperationWithoutMatchingStart() {
        // Given
        let profiler = customProfiler()
        dd_profiler_start_testing(0, false, 5.seconds.dd.toInt64Nanoseconds, 0)
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_NOT_STARTED)

        let orphanEnd: Vital = .mockWith(stepType: .end)

        // When
        _ = profiler.receive(message: .payload(OperationMessage(attributes: mockRandomAttributes(), operation: orphanEnd)), from: core)
        flushQueue()

        // Then - no matching start vital, so profiler should not have been started
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_NOT_STARTED)
        withExtendedLifetime(profiler) {}
    }

    func testCustomProfiler_respectsMinProfileDuration() {
        // Given
        let dateProvider = DateProviderMock(now: Date())
        let profiler = customProfiler(dateProvider: dateProvider)
        shareCurrentContext(with: profiler)
        dd_profiler_start_testing(100, false, 5.seconds.dd.toInt64Nanoseconds, 0)

        let startOp: Vital = .mockWith(stepType: .start, date: dateProvider.now)
        _ = profiler.receive(message: .payload(OperationMessage(attributes: mockRandomAttributes(), operation: startOp)), from: core)
        flushQueue()
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_RUNNING)

        // Operations complete immediately (well within minProfileDuration)
        let endOp: Vital = .mockWith(name: startOp.name, operationKey: startOp.operationKey, stepType: .end)
        _ = profiler.receive(message: .payload(OperationMessage(attributes: mockRandomAttributes(), operation: endOp)), from: core)
        flushQueue()

        // Then - profiler is still running because minProfileDuration has not elapsed yet
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_RUNNING)
        withExtendedLifetime(profiler) {}
    }

    func testCustomProfiler_keepsProfilerRunning_whenOperationsIsRecent() {
        // Given
        let dateProvider = DateProviderMock(now: Date())
        let profiler = customProfiler(isAppLaunchProfilingEnabled: true, dateProvider: dateProvider)
        shareCurrentContext(with: profiler)
        dd_profiler_start_testing(100, false, 5.seconds.dd.toInt64Nanoseconds, 0)

        let startOp: Vital = .mockWith(date: dateProvider.now.addingTimeInterval(1))
        _ = profiler.receive(message: .payload(OperationMessage(attributes: mockRandomAttributes(), operation: startOp)), from: core)

        // When - app launch vital received while operation is still recent
        let launchVital: Vital = .mockWith()
        _ = profiler.receive(message: .payload(TTIDMessage(attributes: mockRandomAttributes(), ttid: launchVital)), from: core)
        flushQueue()

        // Then - profiler keeps running since operation is within cutoff window
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_RUNNING)
        withExtendedLifetime(profiler) {}
    }

    func testCustomProfiler_stopsProfiler_whenOperationsExpired() {
        // Given
        let dateProvider = DateProviderMock(now: Date())
        let profiler = customProfiler(isAppLaunchProfilingEnabled: true, dateProvider: dateProvider)
        shareCurrentContext(with: profiler)
        dd_profiler_start_testing(100, false, 5.seconds.dd.toInt64Nanoseconds, 0)

        let startOp: Vital = .mockWith(stepType: .start, date: dateProvider.now)
        _ = profiler.receive(message: .payload(OperationMessage(attributes: mockRandomAttributes(), operation: startOp)), from: core)
        flushQueue()

        // Advance past the RUM event cutoff.
        dateProvider.now = dateProvider.now.addingTimeInterval(DatadogProfiler.Constants.cutOffTime + 1)

        // When - app launch vital received after cutoff
        let launchVital = Vital.mockWith()
        _ = profiler.receive(message: .payload(TTIDMessage(attributes: mockRandomAttributes(), ttid: launchVital)), from: core)
        flushQueue()

        // Then - profiler stops since no recent operations remain
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_STOPPED)
        withExtendedLifetime(profiler) {}
    }

    func testCustomProfiler_applicationDidEnterBackground_stopsProfilerAndSendsProfile() {
        // Given
        let dateProvider = DateProviderMock()
        let profiler = customProfiler(dateProvider: dateProvider)
        dd_profiler_start_testing(100, false, 5.seconds.dd.toInt64Nanoseconds, 0)
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_RUNNING)

        // When
        core.context = .mockWith(applicationStateHistory: .mockWith(
            initialState: .active,
            date: dateProvider.now.addingTimeInterval(-1),
            transitions: [(state: .background, date: dateProvider.now)]
        ))
        _ = profiler.receive(message: .context(core.context), from: core)
        flushQueue()

        // Then
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_STOPPED)
        withExtendedLifetime(profiler) {}
    }

    func testCustomProfiler_applicationDidEnterBackground_includesLongTasksInProfile() throws {
        // Given
        let dateProvider = DateProviderMock()
        let profiler = customProfiler(dateProvider: dateProvider)
        dd_profiler_start_testing(100, false, 5.seconds.dd.toInt64Nanoseconds, 0)

        let startOperation = Vital.mockWith(name: "operation", date: dateProvider.now)
        let endOperation = Vital.mockWith(
            name: startOperation.name,
            operationKey: startOperation.operationKey,
            stepType: .end
        )
        let longTask = DurationEvent(id: .mockRandom(), type: .longTask, start: 0, duration: 100)
        _ = profiler.receive(message: .payload(OperationMessage(attributes: mockRandomAttributes(), operation: startOperation)), from: core)
        _ = profiler.receive(message: .payload(OperationMessage(attributes: mockRandomAttributes(), operation: endOperation)), from: core)
        _ = profiler.receive(message: .payload(LongTaskMessage(attributes: mockRandomAttributes(), longTask: longTask)), from: core)

        // When
        core.context = .mockWith(applicationStateHistory: .mockWith(
            initialState: .active,
            date: dateProvider.now.addingTimeInterval(-1),
            transitions: [(state: .background, date: dateProvider.now)]
        ))
        waitForProfileWrite {
            _ = profiler.receive(message: .context(core.context), from: core)
        }

        // Then
        let metadata = try XCTUnwrap(core.metadata.first as? ProfileAttachments)
        let rumEvents = try typedRUMEvents(from: metadata)
        XCTAssertEqual(eventIDs(ofType: "long_task", in: rumEvents), [longTask.id])
        withExtendedLifetime(profiler) {}
    }

    func testCustomProfiler_applicationDidEnterBackground_includesAppHangsInProfile() throws {
        // Given
        let dateProvider = DateProviderMock()
        let profiler = customProfiler(dateProvider: dateProvider)
        dd_profiler_start_testing(100, false, 5.seconds.dd.toInt64Nanoseconds, 0)

        let startOperation = Vital.mockWith(name: "operation", date: dateProvider.now)
        let endOperation = Vital.mockWith(
            name: startOperation.name,
            operationKey: startOperation.operationKey,
            stepType: .end
        )
        let hang = DurationEvent(id: .mockRandom(), type: .error, start: 0, duration: 500)
        _ = profiler.receive(message: .payload(OperationMessage(attributes: mockRandomAttributes(), operation: startOperation)), from: core)
        _ = profiler.receive(message: .payload(OperationMessage(attributes: mockRandomAttributes(), operation: endOperation)), from: core)
        _ = profiler.receive(message: .payload(AppHangMessage(attributes: mockRandomAttributes(), hang: hang)), from: core)

        // When
        core.context = .mockWith(applicationStateHistory: .mockWith(
            initialState: .active,
            date: dateProvider.now.addingTimeInterval(-1),
            transitions: [(state: .background, date: dateProvider.now)]
        ))
        waitForProfileWrite {
            _ = profiler.receive(message: .context(core.context), from: core)
        }

        // Then
        let metadata = try XCTUnwrap(core.metadata.first as? ProfileAttachments)
        let rumEvents = try typedRUMEvents(from: metadata)
        XCTAssertEqual(eventIDs(ofType: "error", in: rumEvents), [hang.id])
        withExtendedLifetime(profiler) {}
    }

    func testCustomProfiler_applicationWillEnterForeground_doesNotRestartProfiler() {
        // Given
        let dateProvider = DateProviderMock()
        dd_profiler_start_testing(0, false, 5.seconds.dd.toInt64Nanoseconds, 0)
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_NOT_STARTED)

        let profiler = customProfiler(dateProvider: dateProvider)

        // Send background context to stop the profiler
        core.context = .mockWith(applicationStateHistory: .mockWith(
            initialState: .active,
            date: dateProvider.now.addingTimeInterval(-1),
            transitions: [(state: .background, date: dateProvider.now)]
        ))
        _ = profiler.receive(message: .context(core.context), from: core)
        flushQueue()

        // When - enter foreground with no recent operations
        core.context = .mockWith(applicationStateHistory: .mockWith(
            initialState: .active,
            date: dateProvider.now.addingTimeInterval(-2),
            transitions: [
                (state: .background, date: dateProvider.now.addingTimeInterval(-1)),
                (state: .inactive, date: dateProvider.now)
            ]
        ))
        _ = profiler.receive(message: .context(core.context), from: core)
        flushQueue()

        // Then - custom profiler does not restart without recent operations (unlike continuous)
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_NOT_STARTED)
        withExtendedLifetime(profiler) {}
    }
}

// MARK: - Singleton Guard

extension DatadogProfilerTests {
    func testSingletonGuard_secondInstanceIsObserver() {
        // Given
        let first = continuousProfiler()
        XCTAssertTrue(DatadogProfiler.isInstantiated)
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_NOT_CREATED)

        // When
        let second = DatadogProfiler(
            core: core,
            profilingSamplerProvider: profilingSamplerProvider(isContinuousProfiling: true),
            quotaChecker: quotaChecker()
        )

        // Then - first still processes messages normally, and later instances do not coordinate continuous profiling.
        XCTAssertEqual(first.role, .coordinator)
        XCTAssertEqual(second.role, .observer)
        let hang = DurationEvent(id: .mockRandom(), type: .error, start: 0, duration: 500)
        XCTAssertTrue(first.receive(message: .payload(AppHangMessage(attributes: mockRandomAttributes(), hang: hang)), from: core))
        XCTAssertFalse(second.receive(message: .payload(AppHangMessage(attributes: mockRandomAttributes(), hang: hang)), from: core))
        XCTAssertNotNil(first)
    }

    func testSingletonGuard_instanceBecomesActiveAfterPreviousDeallocates() {
        // Given
        var first: DatadogProfiler? = continuousProfiler()
        XCTAssertTrue(DatadogProfiler.isInstantiated)
        XCTAssertNotNil(first)
        first = nil
        XCTAssertFalse(DatadogProfiler.isInstantiated, "Singleton guard should be released after dealloc")

        // When
        let second = continuousProfiler()

        // Then
        XCTAssertTrue(DatadogProfiler.isInstantiated)
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_NOT_CREATED)
        let hang = DurationEvent(id: .mockRandom(), type: .error, start: 0, duration: 500)
        XCTAssertTrue(second.receive(message: .payload(AppHangMessage(attributes: mockRandomAttributes(), hang: hang)), from: core))
        XCTAssertNotNil(second)
    }

    func testSingletonGuard_isThreadSafe() {
        // Given
        let iterations = 100
        let expectation = expectation(description: "All concurrent creations complete")
        expectation.expectedFulfillmentCount = iterations
        var profilers: [DatadogProfiler?] = []
        let lock = NSLock()

        // When - many instances created concurrently
        DispatchQueue.concurrentPerform(iterations: iterations) { _ in
            let profiler = DatadogProfiler(
                core: core,
                profilingSamplerProvider: profilingSamplerProvider(isContinuousProfiling: true),
                quotaChecker: quotaChecker()
            )
            lock.lock()
            profilers.append(profiler)
            lock.unlock()
            expectation.fulfill()
        }

        // Then
        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(profilers.compactMap { $0 }.filter { $0.role == .coordinator }.count, 1, "Exactly one instance should coordinate profiling")
        XCTAssertEqual(profilers.compactMap { $0 }.filter { $0.role == .observer }.count, iterations - 1)
        XCTAssertTrue(DatadogProfiler.isInstantiated)
    }
}

// MARK: - Telemetry

extension DatadogProfilerTests {
    func testContinuousProfiler_sendsProfilingSessionMetric_whenProfileIsWritten() throws {
        // Given
        let telemetry = TelemetryMock()
        let telemetryController = ProfilingTelemetryController(telemetry: telemetry)
        let dateProvider = DateProviderMock()
        let profilingSamplerProvider = profilingSamplerProvider(isContinuousProfiling: true)
        profilingSamplerProvider.updateWith(
            deterministicSampler: DeterministicSampler(uuid: .mockRandom(), samplingRate: .maxSampleRate)
        )
        let profiler = continuousProfiler(
            profilingSamplerProvider: profilingSamplerProvider,
            telemetryController: telemetryController,
            dateProvider: dateProvider
        )
        let longTask = DurationEvent(id: .mockRandom(), type: .longTask, start: 0, duration: 100)
        dd_profiler_start_testing(100, false, 5.seconds.dd.toInt64Nanoseconds, 0)
        _ = profiler.receive(message: .payload(LongTaskMessage(attributes: mockRandomAttributes(), longTask: longTask)), from: core)

        // When
        core.context = .mockWith(applicationStateHistory: .mockWith(
            initialState: .active,
            date: dateProvider.now.addingTimeInterval(-1),
            transitions: [(state: .background, date: dateProvider.now)]
        ))
        waitForProfileWrite(timeout: 0.3) {
            _ = profiler.receive(message: .context(core.context), from: core)
        }

        // Then
        let metric = try firstProfilingSessionMetric(from: telemetry)
        XCTAssertEqual(metric.startReason, ProfilingSessionMetric.StartReason.continuous.rawValue)
        XCTAssertEqual(metric.cycleIndex, 0)
        XCTAssertNotNil(metric.duration)
        XCTAssertNotNil(metric.fileSize)
        XCTAssertNil(metric.errorCode)
        XCTAssertNil(metric.errorMessage)

        let metricTelemetry = try XCTUnwrap(telemetry.messages.lastMetric(named: ProfilingSessionMetric.Constants.name))
        XCTAssertEqual(metricTelemetry.sampleRate, 20)
        withExtendedLifetime(profiler) {}
    }

    func testContinuousProfiler_sendsProfilingSessionMetric_whenProfileIsDropped() throws {
        // Given
        let telemetry = TelemetryMock()
        let telemetryController = ProfilingTelemetryController(telemetry: telemetry)
        let dateProvider = DateProviderMock()
        let profilingSamplerProvider = profilingSamplerProvider(isContinuousProfiling: true)
        profilingSamplerProvider.updateWith(
            deterministicSampler: DeterministicSampler(uuid: .mockRandom(), samplingRate: .maxSampleRate)
        )
        let profiler = continuousProfiler(
            profilingSamplerProvider: profilingSamplerProvider,
            telemetryController: telemetryController,
            dateProvider: dateProvider
        )
        dd_profiler_start_testing(100, false, 5.seconds.dd.toInt64Nanoseconds, 0)

        // When
        core.context = .mockWith(applicationStateHistory: .mockWith(
            initialState: .active,
            date: dateProvider.now.addingTimeInterval(-1),
            transitions: [(state: .background, date: dateProvider.now)]
        ))
        waitForProfileWrite(expectingWrite: false, timeout: 0.3) {
            _ = profiler.receive(message: .context(core.context), from: core)
        }

        // Then
        let metric = try firstProfilingSessionMetric(from: telemetry)
        XCTAssertEqual(metric.startReason, ProfilingSessionMetric.StartReason.continuous.rawValue)
        XCTAssertEqual(metric.cycleIndex, 0)
        XCTAssertNil(metric.duration)
        XCTAssertNil(metric.fileSize)
        XCTAssertEqual(metric.errorMessage, ProfilingSessionMetric.Constants.noProfiledEventsErrorMessage)
        XCTAssertNil(metric.errorCode)
        XCTAssertTrue(core.metadata.isEmpty)
        withExtendedLifetime(profiler) {}
    }

    func testCustomProfiler_sendsProfilingSessionMetric_whenProfileIsWritten() throws {
        // Given
        let telemetry = TelemetryMock()
        let telemetryController = ProfilingTelemetryController(telemetry: telemetry)
        let initialDate = Date().addingTimeInterval(-(DatadogProfiler.Constants.minProfileDuration + 3))
        let dateProvider = DateProviderMock(now: initialDate)
        core.context = .mockWith(applicationStateHistory: .mockAppInForeground(since: initialDate.addingTimeInterval(-1)))
        let profiler = customProfiler(telemetryController: telemetryController, dateProvider: dateProvider)
        shareCurrentContext(with: profiler)
        dd_profiler_start_testing(100, false, 5.seconds.dd.toInt64Nanoseconds, 0)

        let startOperation = Vital.mockWith(stepType: .start, date: dateProvider.now)
        _ = profiler.receive(message: .payload(OperationMessage(attributes: mockRandomAttributes(), operation: startOperation)), from: core)
        flushQueue()

        dateProvider.now = dateProvider.now.addingTimeInterval(DatadogProfiler.Constants.minProfileDuration + 1)
        let endOperation = Vital.mockWith(
            name: startOperation.name,
            operationKey: startOperation.operationKey,
            stepType: .end
        )

        // When
        _ = profiler.receive(message: .payload(OperationMessage(attributes: mockRandomAttributes(), operation: endOperation)), from: core)
        waitUntil(timeout: 1.0) {
            dd_profiler_get_status() == DD_PROFILER_STATUS_STOPPED && core.metadata.isEmpty == false
        }
        waitUntil(timeout: 1.0) {
            telemetry.messages.lastMetric(named: ProfilingSessionMetric.Constants.name) != nil
        }

        // Then
        let metric = try lastProfilingSessionMetric(from: telemetry)
        XCTAssertEqual(metric.startReason, ProfilingSessionMetric.StartReason.rumOperation.rawValue)
        XCTAssertNil(metric.cycleIndex)
        XCTAssertNotNil(metric.duration)
        XCTAssertNotNil(metric.fileSize)
        XCTAssertEqual(metric.stoppedReason, ProfilingContext.Status.StopReason.manual.rawValue)
        XCTAssertNil(metric.errorCode)
        XCTAssertNil(metric.errorMessage)
        withExtendedLifetime(profiler) {}
    }
}

// MARK: - Profiling Quota

extension DatadogProfilerTests {
    func testQuotaIsCheckedAsSoonAsContextIsShared() {
        // Given
        let quotaChecker = ProfilingQuotaCheckerMock()
        let sessionID: UUID = .mockAny()
        core.context = .mockWith(
            applicationStateHistory: .mockAppInForeground(),
            additionalContext: [RUMCoreContext.mockWith(sessionID: sessionID, sessionSampleRate: .maxSampleRate)]
        )
        let profilingSamplerProvider = profilingSamplerProvider(isContinuousProfiling: true)
        let profiler = continuousProfiler(
            profilingSamplerProvider: profilingSamplerProvider,
            quotaChecker: quotaChecker
        )
        dd_profiler_start_testing(100, false, 5.seconds.dd.toInt64Nanoseconds, 0)
        connectMessageReceiver(
            to: profiler,
            profilingSamplerProvider: profilingSamplerProvider,
            quotaChecker: quotaChecker
        )

        // Then
        XCTAssertEqual(
            quotaChecker.receivedContexts.compactMap { $0.additionalContext(ofType: RUMCoreContext.self)?.sessionID },
            [sessionID.uuidString.lowercased()]
        )
        withExtendedLifetime(profiler) {}
    }

    func testQuotaRejection_stopsAndDoesNotWriteContinuousProfile() {
        // Given
        let quotaChecker = ProfilingQuotaCheckerMock()
        quotaChecker.receiveHandler = { _ in
            .init(decision: .quotaKO, reason: .quotaExceeded)
        }
        let profilingSamplerProvider = profilingSamplerProvider(isContinuousProfiling: true)
        profilingSamplerProvider.updateWith(
            deterministicSampler: DeterministicSampler(uuid: .mockRandom(), samplingRate: .maxSampleRate)
        )
        let profiler = continuousProfiler(
            profilingSamplerProvider: profilingSamplerProvider,
            quotaChecker: quotaChecker
        )
        core.context = .mockWith(
            applicationStateHistory: .mockAppInForeground(),
            additionalContext: [RUMCoreContext.mockWith(sessionSampleRate: .maxSampleRate)]
        )
        dd_profiler_start_testing(100, false, Int64.max, 0)
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_RUNNING)
        let rejectedTrace = UnsafeMutablePointer<stack_trace_t>.allocate(capacity: 1)
        rejectedTrace.pointee = .mockWith(tid: 1, addresses: [0x100001000])
        dd_pprof_add_samples(dd_profiler_get_profile(), rejectedTrace, 1)
        dd_free(rejectedTrace)
        XCTAssertGreaterThan(dd_pprof_sample_count(dd_profiler_get_profile()), 0)
        _ = profiler.receive(
            message: .payload(TTIDMessage(attributes: mockRandomAttributes(), ttid: .mockWith(stepType: nil))),
            from: core
        )
        connectMessageReceiver(
            to: profiler,
            profilingSamplerProvider: profilingSamplerProvider,
            quotaChecker: quotaChecker
        )

        waitUntil(timeout: 1.0) {
            dd_profiler_get_status() == DD_PROFILER_STATUS_STOPPED
        }

        let longTask = DurationEvent(id: .mockRandom(), type: .longTask, start: 0, duration: 100)
        _ = profiler.receive(message: .payload(LongTaskMessage(attributes: mockRandomAttributes(), longTask: longTask)), from: core)
        flushQueue()

        // When
        waitForProfileWrite(expectingWrite: false, timeout: 0.15) {}

        // Then
        XCTAssertTrue(core.metadata.isEmpty)
        XCTAssertEqual(quotaChecker.receivedContexts.count, 1)
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_STOPPED)
        XCTAssertEqual(dd_pprof_sample_count(dd_profiler_get_profile()), 0)

        withExtendedLifetime(profiler) {}
    }

    func testQuotaRejectionBeforeAppLaunchVital_stopsNativeProfilerAndCleansObserverState() {
        // Given
        let quotaChecker = ProfilingQuotaCheckerMock()
        quotaChecker.receiveHandler = { _ in
            .init(decision: .quotaKO, reason: .quotaExceeded)
        }
        let observerCore = PassthroughCoreMock()
        let profilingSamplerProvider = profilingSamplerProvider(isContinuousProfiling: true)
        profilingSamplerProvider.updateWith(
            deterministicSampler: DeterministicSampler(uuid: .mockRandom(), samplingRate: .maxSampleRate)
        )
        let profiler = continuousProfiler(
            profilingSamplerProvider: profilingSamplerProvider,
            quotaChecker: quotaChecker
        )
        let observer = continuousProfiler(
            core: observerCore,
            continuousProfilingSampled: true,
            isAppLaunchProfilingEnabled: true
        )
        core.context = .mockWith(
            applicationStateHistory: .mockAppInForeground(),
            additionalContext: [RUMCoreContext.mockWith(sessionSampleRate: .maxSampleRate)]
        )
        dd_profiler_start_testing(100, false, 5.seconds.dd.toInt64Nanoseconds, 0)

        // When - quota rejects before TTID has been harvested.
        connectMessageReceiver(
            to: profiler,
            profilingSamplerProvider: profilingSamplerProvider,
            quotaChecker: quotaChecker
        )

        // Then - continuous, custom and app-launch profiling are disabled for the rejected session.
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_STOPPED)

        // When - the observer accumulates data after the quota callback cleanup.
        _ = observer.receive(
            message: .payload(TTIDMessage(attributes: mockRandomAttributes(), ttid: .mockWith(stepType: nil))),
            from: observerCore
        )
        flushQueue()
        XCTAssertTrue(observer.hasEventsOfInterest)

        // When - the coordinator processes TTID with quota already rejected.
        _ = profiler.receive(
            message: .payload(TTIDMessage(attributes: mockRandomAttributes(), ttid: .mockWith(stepType: nil))),
            from: core
        )
        flushQueue()

        // Then - app launch does not restart profiling after quota rejection.
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_STOPPED)
        XCTAssertFalse(observer.hasEventsOfInterest)
        withExtendedLifetime(profiler) {}
        withExtendedLifetime(observer) {}
    }

    func testQuotaRejectionAfterAppLaunchVital_doesNotFlushAppLaunchProfileOnSampleOutContext() {
        // Given
        let telemetry = TelemetryMock()
        let telemetryController = ProfilingTelemetryController(telemetry: telemetry)
        let quotaChecker = ProfilingQuotaCheckerMock()
        let observerCore = PassthroughCoreMock()
        let profilingSamplerProvider = profilingSamplerProvider(isContinuousProfiling: true)
        let profiler = continuousProfiler(
            profilingSamplerProvider: profilingSamplerProvider,
            isAppLaunchProfilingEnabled: true,
            telemetryController: telemetryController,
            quotaChecker: quotaChecker
        )
        let observer = continuousProfiler(
            core: observerCore,
            continuousProfilingSampled: true,
            isAppLaunchProfilingEnabled: true
        )
        core.context = .mockWith(
            applicationStateHistory: .mockAppInForeground(),
            additionalContext: [RUMCoreContext.mockWith(sessionSampleRate: .maxSampleRate)]
        )
        dd_profiler_start_testing(100, false, 5.seconds.dd.toInt64Nanoseconds, 0)

        // When - TTID is harvested while quota is still pending.
        _ = profiler.receive(
            message: .payload(TTIDMessage(attributes: mockRandomAttributes(), ttid: .mockWith(stepType: nil))),
            from: core
        )
        flushQueue()

        // Then - pending quota remains fail-open, so TTID itself does not drop the profile.
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_RUNNING)
        XCTAssertTrue(core.metadata.isEmpty)
        XCTAssertNil(telemetry.messages.lastMetric(named: ProfilingSessionMetric.Constants.name))

        _ = observer.receive(
            message: .payload(TTIDMessage(attributes: mockRandomAttributes(), ttid: .mockWith(stepType: nil))),
            from: observerCore
        )
        _ = observer.receive(
            message: .payload(LongTaskMessage(
                attributes: mockRandomAttributes(),
                longTask: .init(id: .mockRandom(), type: .longTask, start: 0, duration: 100)
            )),
            from: observerCore
        )
        _ = observer.receive(
            message: .payload(AppHangMessage(
                attributes: mockRandomAttributes(),
                hang: .init(id: .mockRandom(), type: .error, start: 0, duration: 500)
            )),
            from: observerCore
        )
        flushQueue()
        XCTAssertTrue(observer.hasEventsOfInterest)

        // When - quota rejects asynchronously before the RUM sampling decision arrives.
        quotaChecker.quotaResult = .init(decision: .quotaKO, reason: .quotaExceeded)
        quotaChecker.onQuotaResultUpdate?(quotaChecker.quotaResult)
        flushQueue()

        // Then - the rejected shared profile and observer correlation data are discarded.
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_STOPPED)
        XCTAssertFalse(observer.hasEventsOfInterest)

        // When - the later RUM sampling decision samples continuous profiling out.
        profilingSamplerProvider.updateWith(
            deterministicSampler: DeterministicSampler(seed: 1, samplingRate: 0)
        )
        core.context = .mockWith(
            applicationStateHistory: .mockAppInForeground(),
            additionalContext: [RUMCoreContext.mockWith(sessionSampleRate: 0)]
        )
        _ = profiler.receive(message: .context(core.context), from: core)
        flushQueue()

        // Then - the context path does not flush or report a second app-launch drop.
        XCTAssertTrue(core.metadata.isEmpty)
        XCTAssertNil(telemetry.messages.lastMetric(named: ProfilingSessionMetric.Constants.name))
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_STOPPED)

        // When - quota resets for a later session, but the rejected app-launch data is gone.
        quotaChecker.quotaResult = nil
        quotaChecker.onQuotaResultUpdate?(nil)
        _ = profiler.receive(message: .context(core.context), from: core)
        flushQueue()

        // Then - stale TTID state alone is not enough to write an app-launch profile.
        XCTAssertTrue(core.metadata.isEmpty)
        XCTAssertNil(telemetry.messages.lastMetric(named: ProfilingSessionMetric.Constants.name))
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_STOPPED)
        withExtendedLifetime(profiler) {}
        withExtendedLifetime(observer) {}
    }

    func testQuotaRejectionBeforeAppLaunchVital_doesNotRestartNativeProfiler_whenAppIsBackgrounded() {
        // Given
        let quotaChecker = ProfilingQuotaCheckerMock()
        let profilingSamplerProvider = profilingSamplerProvider(isContinuousProfiling: true)
        profilingSamplerProvider.updateWith(
            deterministicSampler: DeterministicSampler(uuid: .mockRandom(), samplingRate: .maxSampleRate)
        )
        let dateProvider = DateProviderMock()
        let profiler = continuousProfiler(
            profilingSamplerProvider: profilingSamplerProvider,
            dateProvider: dateProvider,
            quotaChecker: quotaChecker
        )
        let rumContext = RUMCoreContext.mockWith(sessionSampleRate: .maxSampleRate)
        core.context = .mockWith(
            applicationStateHistory: .mockAppInForeground(since: dateProvider.now.addingTimeInterval(-1)),
            additionalContext: [rumContext]
        )
        connectMessageReceiver(
            to: profiler,
            profilingSamplerProvider: profilingSamplerProvider,
            quotaChecker: quotaChecker
        )
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_RUNNING)

        // When - the app backgrounds while quota is still pending.
        core.context = .mockWith(
            applicationStateHistory: .mockWith(
                initialState: .active,
                date: dateProvider.now.addingTimeInterval(-1),
                transitions: [(state: .background, date: dateProvider.now)]
            ),
            additionalContext: [rumContext]
        )
        flushQueue()
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_STOPPED)

        // When - quota rejects before TTID is harvested.
        quotaChecker.receiveHandler = { _ in
            .init(decision: .quotaKO, reason: .quotaExceeded)
        }
        _ = core.messageReceiver.receive(message: .context(core.context), from: core)
        flushQueue()

        // Then - app-launch preservation does not override background profiling conditions.
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_STOPPED)
        withExtendedLifetime(profiler) {}
    }

    func testQuotaRejectionBeforeAppLaunchVital_stopsNativeProfilerImmediately_whenAppLaunchVitalIsNotReceived() {
        // Given
        let quotaChecker = ProfilingQuotaCheckerMock()
        quotaChecker.receiveHandler = { _ in
            .init(decision: .quotaKO, reason: .quotaExceeded)
        }
        let profilingSamplerProvider = profilingSamplerProvider(isContinuousProfiling: true)
        profilingSamplerProvider.updateWith(
            deterministicSampler: DeterministicSampler(uuid: .mockRandom(), samplingRate: .maxSampleRate)
        )
        let dateProvider = DateProviderMock()
        let profiler = continuousProfiler(
            profilingSamplerProvider: profilingSamplerProvider,
            dateProvider: dateProvider,
            quotaChecker: quotaChecker
        )
        core.context = .mockWith(
            applicationStateHistory: .mockAppInForeground(),
            additionalContext: [RUMCoreContext.mockWith(sessionSampleRate: .maxSampleRate)]
        )
        dd_profiler_start_testing(100, false, 5.seconds.dd.toInt64Nanoseconds, 0)

        // When - quota rejects before TTID and no TTID message is ever received.
        connectMessageReceiver(
            to: profiler,
            profilingSamplerProvider: profilingSamplerProvider,
            quotaChecker: quotaChecker
        )

        // Then - quota rejection is enough to stop the native profiler; no app-launch fallback timer is needed.
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_STOPPED)
        XCTAssertTrue(core.metadata.isEmpty)
        withExtendedLifetime(profiler) {}
    }

    func testQuotaResultReset_restartsContinuousProfile_whenAppStateIsUnchanged() {
        // Given
        let quotaChecker = ProfilingQuotaCheckerMock()
        quotaChecker.receiveHandler = { _ in
            .init(decision: .quotaKO, reason: .quotaExceeded)
        }
        let profilingSamplerProvider = profilingSamplerProvider(isContinuousProfiling: true)
        profilingSamplerProvider.updateWith(
            deterministicSampler: DeterministicSampler(uuid: .mockRandom(), samplingRate: .maxSampleRate)
        )
        let firstSessionID: UUID = .mockAny()
        core.context = .mockWith(
            applicationStateHistory: .mockAppInForeground(),
            additionalContext: [RUMCoreContext.mockWith(sessionID: firstSessionID, sessionSampleRate: .maxSampleRate)]
        )
        let profiler = continuousProfiler(
            profilingSamplerProvider: profilingSamplerProvider,
            quotaChecker: quotaChecker
        )
        dd_profiler_start_testing(100, false, 5.seconds.dd.toInt64Nanoseconds, 0)
        _ = profiler.receive(
            message: .payload(TTIDMessage(attributes: mockRandomAttributes(), ttid: .mockWith(stepType: nil))),
            from: core
        )
        connectMessageReceiver(
            to: profiler,
            profilingSamplerProvider: profilingSamplerProvider,
            quotaChecker: quotaChecker
        )
        waitUntil(timeout: 1.0) {
            dd_profiler_get_status() == DD_PROFILER_STATUS_STOPPED
        }

        quotaChecker.receiveHandler = { _ in
            .init(decision: .quotaOK, reason: .quotaOk)
        }
        let secondSessionID: UUID = .mockAny()

        // When - RUM rotates session while the app stays active.
        core.context = .mockWith(
            applicationStateHistory: .mockAppInForeground(),
            additionalContext: [RUMCoreContext.mockWith(sessionID: secondSessionID, sessionSampleRate: .maxSampleRate)]
        )

        // Then
        waitUntil(timeout: 1.0) {
            dd_profiler_get_status() == DD_PROFILER_STATUS_RUNNING
        }
        flushQueue()
        let runningProfilingContext = core.context.additionalContext(ofType: ProfilingContext.self)
        XCTAssertEqual(runningProfilingContext?.status, .running)
        XCTAssertNil(runningProfilingContext?.quotaReason)
        XCTAssertEqual(
            quotaChecker.receivedContexts.compactMap { $0.additionalContext(ofType: RUMCoreContext.self)?.sessionID },
            [firstSessionID.uuidString.lowercased(), secondSessionID.uuidString.lowercased()]
        )
        withExtendedLifetime(profiler) {}
    }

    func testObserverQuotaAndConsent_updateLocalProfilingContext_withoutStoppingCoordinator() throws {
        // Given
        let observerCore = PassthroughCoreMock()
        let observerQuotaChecker = ProfilingQuotaCheckerMock()
        let coordinator = continuousProfiler(continuousProfilingSampled: true)
        let observer = continuousProfiler(
            core: observerCore,
            continuousProfilingSampled: true,
            quotaChecker: observerQuotaChecker
        )
        XCTAssertEqual(coordinator.role, .coordinator)
        XCTAssertEqual(observer.role, .observer)
        XCTAssertEqual(dd_profiler_start(), 1)

        // When
        observerQuotaChecker.quotaResult = .init(decision: .quotaKO, reason: .quotaExceeded)
        observerQuotaChecker.onQuotaResultUpdate?(observerQuotaChecker.quotaResult)
        flushQueue()

        // Then
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_RUNNING)
        var profilingContext = try XCTUnwrap(observerCore.context.additionalContext(ofType: ProfilingContext.self))
        XCTAssertEqual(profilingContext.status, .stopped(reason: .manual))
        XCTAssertEqual(profilingContext.quotaReason, .quotaExceeded)

        // When - consent is revoked before quota resets for the observer's next session.
        var observerContext = observerCore.context
        observerContext.trackingConsent = .notGranted
        observerCore.context = observerContext
        _ = observer.receive(message: .context(observerContext), from: observerCore)
        flushQueue()

        observerQuotaChecker.quotaResult = nil
        observerQuotaChecker.onQuotaResultUpdate?(nil)
        flushQueue()

        // Then - the observer remains stopped by consent while the coordinator keeps running.
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_RUNNING)
        profilingContext = try XCTUnwrap(observerCore.context.additionalContext(ofType: ProfilingContext.self))
        XCTAssertEqual(profilingContext.status, .stopped(reason: .manual))
        XCTAssertNil(profilingContext.quotaReason)

        // When - consent is granted again.
        observerContext = observerCore.context
        observerContext.trackingConsent = .granted
        observerCore.context = observerContext
        _ = observer.receive(message: .context(observerContext), from: observerCore)
        flushQueue()

        // Then - the observer publishes the shared native profiler status again.
        profilingContext = try XCTUnwrap(observerCore.context.additionalContext(ofType: ProfilingContext.self))
        XCTAssertEqual(profilingContext.status, .running)
        XCTAssertNil(profilingContext.quotaReason)
        withExtendedLifetime(coordinator) {}
        withExtendedLifetime(observer) {}
    }

    func testQuotaRejection_discardsRejectedRUMEventsBeforeNextAdmittedProfile() throws {
        // Given
        let telemetry = TelemetryMock()
        let telemetryController = ProfilingTelemetryController(telemetry: telemetry)
        let quotaChecker = ProfilingQuotaCheckerMock()
        quotaChecker.quotaResult = .init(decision: .quotaKO, reason: .quotaExceeded)
        let dateProvider = DateProviderMock()
        let profilingSamplerProvider = profilingSamplerProvider(isContinuousProfiling: true)
        profilingSamplerProvider.updateWith(
            deterministicSampler: DeterministicSampler(uuid: .mockRandom(), samplingRate: .maxSampleRate)
        )
        let profiler = continuousProfiler(
            profilingSamplerProvider: profilingSamplerProvider,
            telemetryController: telemetryController,
            dateProvider: dateProvider,
            quotaChecker: quotaChecker
        )
        _ = profiler.receive(
            message: .payload(TTIDMessage(attributes: mockRandomAttributes(), ttid: .mockWith(stepType: nil))),
            from: core
        )
        flushQueue()

        let rejectedLongTask = DurationEvent(id: .mockRandom(), type: .longTask, start: 0, duration: 100)
        _ = profiler.receive(
            message: .payload(LongTaskMessage(attributes: mockRandomAttributes(), longTask: rejectedLongTask)),
            from: core
        )
        flushQueue()

        // When - the stopped profiler has no native profile to flush for the rejected session.
        core.context = .mockWith(applicationStateHistory: .mockWith(
            initialState: .active,
            date: dateProvider.now.addingTimeInterval(-1),
            transitions: [(state: .background, date: dateProvider.now)]
        ))
        waitForProfileWrite(expectingWrite: false) {
            _ = profiler.receive(message: .context(core.context), from: core)
        }

        // Then - the rejected profile is not written, and the rejected RUM event is discarded.
        XCTAssertTrue(core.metadata.isEmpty)
        let noProfileMetric = try lastProfilingSessionMetric(from: telemetry)
        XCTAssertEqual(
            noProfileMetric.errorMessage,
            ProfilingSessionMetric.Constants.noProfileErrorMessage
        )

        // When - a later session is admitted and writes a profile.
        quotaChecker.quotaResult = .init(decision: .quotaOK, reason: .quotaOk)
        dateProvider.now = dateProvider.now.addingTimeInterval(1)
        core.context = .mockWith(applicationStateHistory: .mockWith(
            initialState: .background,
            date: dateProvider.now.addingTimeInterval(-1),
            transitions: [(state: .inactive, date: dateProvider.now)]
        ))
        _ = profiler.receive(message: .context(core.context), from: core)
        flushQueue()
        dd_profiler_start_testing(100, false, 5.seconds.dd.toInt64Nanoseconds, 0)

        let admittedLongTask = DurationEvent(id: .mockRandom(), type: .longTask, start: 0, duration: 100)
        _ = profiler.receive(
            message: .payload(LongTaskMessage(attributes: mockRandomAttributes(), longTask: admittedLongTask)),
            from: core
        )

        dateProvider.now = dateProvider.now.addingTimeInterval(1)
        core.context = .mockWith(applicationStateHistory: .mockWith(
            initialState: .active,
            date: dateProvider.now.addingTimeInterval(-1),
            transitions: [(state: .background, date: dateProvider.now)]
        ))
        waitForProfileWrite {
            _ = profiler.receive(message: .context(core.context), from: core)
        }

        // Then - only the admitted session RUM event is attached.
        let metadata = try XCTUnwrap(core.metadata.first as? ProfileAttachments)
        let rumEvents = try typedRUMEvents(from: metadata)
        XCTAssertEqual(eventIDs(ofType: "long_task", in: rumEvents), [admittedLongTask.id])
        withExtendedLifetime(profiler) {}
    }

    func testCustomProfiler_stopsAndDoesNotWriteProfile_whenQuotaIsRejected() throws {
        // Given
        let quotaChecker = ProfilingQuotaCheckerMock()
        let initialDate = Date().addingTimeInterval(-(DatadogProfiler.Constants.minProfileDuration + 3))
        let dateProvider = DateProviderMock(now: initialDate)
        let profilingSamplerProvider = profilingSamplerProvider(isContinuousProfiling: false)
        core.context = .mockWith(
            applicationStateHistory: .mockAppInForeground(since: initialDate.addingTimeInterval(-1)),
            additionalContext: [RUMCoreContext.mockWith(sessionSampleRate: .maxSampleRate)]
        )
        let profiler = continuousProfiler(
            profilingSamplerProvider: profilingSamplerProvider,
            profilingInterval: 0.05,
            dateProvider: dateProvider,
            quotaChecker: quotaChecker
        )
        connectMessageReceiver(
            to: profiler,
            profilingSamplerProvider: profilingSamplerProvider,
            quotaChecker: quotaChecker
        )
        _ = profiler.receive(
            message: .payload(TTIDMessage(attributes: mockRandomAttributes(), ttid: .mockWith(stepType: nil))),
            from: core
        )
        flushQueue()
        dd_profiler_start_testing(100, false, 5.seconds.dd.toInt64Nanoseconds, 0)

        let startOp: Vital = .mockWith(stepType: .start, date: dateProvider.now)
        _ = profiler.receive(message: .payload(OperationMessage(attributes: mockRandomAttributes(), operation: startOp)), from: core)
        flushQueue()
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_RUNNING)

        quotaChecker.receiveHandler = { _ in
            .init(decision: .quotaKO, reason: .quotaExceeded)
        }

        // When
        core.context = core.context
        waitUntil(timeout: 1.0) {
            dd_profiler_get_status() == DD_PROFILER_STATUS_STOPPED
        }

        // Then
        XCTAssertTrue(core.metadata.isEmpty)
        XCTAssertEqual(quotaChecker.receivedContexts.count, 2)
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_STOPPED)
        let profilingContext = try XCTUnwrap(core.context.additionalContext(ofType: ProfilingContext.self))
        XCTAssertEqual(profilingContext.quotaReason, .quotaExceeded)
        withExtendedLifetime(profiler) {}
    }
}

// MARK: - Observer Profiling

extension DatadogProfilerTests {
    func testObserver_preservesOngoingOperationAcrossAppLaunchAndContinuousProfileFlushes() throws {
        // Given
        let dateProvider = DateProviderMock()
        let observerCore = PassthroughCoreMock()
        let coordinatorSamplerProvider = profilingSamplerProvider(isContinuousProfiling: true)
        coordinatorSamplerProvider.updateWith(
            deterministicSampler: DeterministicSampler(uuid: .mockRandom(), samplingRate: 0)
        )
        let coordinator = continuousProfiler(
            profilingSamplerProvider: coordinatorSamplerProvider,
            isAppLaunchProfilingEnabled: true,
            dateProvider: dateProvider
        )
        let observer = continuousProfiler(
            core: observerCore,
            continuousProfilingSampled: true,
            isAppLaunchProfilingEnabled: true,
            dateProvider: dateProvider
        )
        let coordinatorTTID = Vital.mockWith(id: "coordinator-ttid-id", name: "time_to_initial_display", stepType: nil)
        let observerTTID = Vital.mockWith(id: "observer-ttid-id", name: "time_to_initial_display", stepType: nil)
        let operationStart = Vital.mockWith(
            id: "observer-operation-id",
            name: "operation",
            stepType: .start,
            date: dateProvider.now
        )

        XCTAssertEqual(coordinator.role, .coordinator)
        XCTAssertEqual(observer.role, .observer)
        XCTAssertEqual(dd_profiler_start(), 1)

        _ = observer.receive(
            message: .payload(TTIDMessage(attributes: mockRandomAttributes(), ttid: observerTTID)),
            from: observerCore
        )
        _ = observer.receive(
            message: .payload(OperationMessage(attributes: mockRandomAttributes(), operation: operationStart)),
            from: observerCore
        )
        flushQueue()
        XCTAssertTrue(observerCore.events.isEmpty)

        // When - the coordinator broadcasts an app-launch profile while the observer operation is ongoing.
        waitForProfileWrite(on: observerCore, timeout: 1.0) {
            _ = coordinator.receive(
                message: .payload(TTIDMessage(attributes: mockRandomAttributes(), ttid: coordinatorTTID)),
                from: core
            )
        }

        // Then - the app-launch profile contains the unresolved operation start.
        let appLaunchMetadata = try XCTUnwrap(observerCore.metadata.first as? ProfileAttachments)
        XCTAssertEqual(
            Set(try eventIDs(ofType: "vital", from: appLaunchMetadata)),
            Set(["observer-ttid-id", "observer-operation-id"])
        )
        let appLaunchOperation = try XCTUnwrap(
            typedRUMEvents(from: appLaunchMetadata).first { $0["id"] as? String == operationStart.id }
        )
        XCTAssertNil(appLaunchOperation["duration_ns"])
        XCTAssertTrue(try XCTUnwrap(observerCore.events.first as? ProfileEvent).tags.contains("operation:launch"))

        // When - continuous profiling starts and flushes while the operation remains ongoing.
        coordinatorSamplerProvider.updateWith(
            deterministicSampler: DeterministicSampler(uuid: .mockRandom(), samplingRate: .maxSampleRate)
        )
        core.context = .mockWith(applicationStateHistory: .mockAppInForeground(since: dateProvider.now))
        _ = coordinator.receive(message: .context(core.context), from: core)
        flushQueue()
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_RUNNING)

        core.context = .mockWith(applicationStateHistory: .mockWith(
            initialState: .active,
            date: dateProvider.now.addingTimeInterval(-1),
            transitions: [(state: .background, date: dateProvider.now)]
        ))
        waitForProfileWrite(on: observerCore, timeout: 1.0) {
            _ = coordinator.receive(message: .context(core.context), from: core)
        }

        // Then - the continuous profile still contains the unresolved operation start.
        XCTAssertEqual(observerCore.metadata.count, 2)
        let ongoingMetadata = try XCTUnwrap(observerCore.metadata.last as? ProfileAttachments)
        XCTAssertEqual(try eventIDs(ofType: "vital", from: ongoingMetadata), ["observer-operation-id"])
        let ongoingOperation = try XCTUnwrap(
            typedRUMEvents(from: ongoingMetadata).first { $0["id"] as? String == operationStart.id }
        )
        XCTAssertNil(ongoingOperation["duration_ns"])
        XCTAssertTrue(try XCTUnwrap(observerCore.events.last as? ProfileEvent).tags.contains("operation:continuous"))

        // When - the operation ends during the next profile window.
        core.context = .mockWith(applicationStateHistory: .mockAppInForeground(since: dateProvider.now))
        _ = coordinator.receive(message: .context(core.context), from: core)
        flushQueue()
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_RUNNING)

        dateProvider.now = dateProvider.now.addingTimeInterval(1)
        let operationEnd = Vital.mockWith(
            name: operationStart.name,
            operationKey: operationStart.operationKey,
            stepType: .end,
            date: dateProvider.now
        )
        _ = observer.receive(
            message: .payload(OperationMessage(attributes: mockRandomAttributes(), operation: operationEnd)),
            from: observerCore
        )

        core.context = .mockWith(applicationStateHistory: .mockWith(
            initialState: .active,
            date: dateProvider.now.addingTimeInterval(-1),
            transitions: [(state: .background, date: dateProvider.now)]
        ))
        waitForProfileWrite(on: observerCore, timeout: 1.0) {
            _ = coordinator.receive(message: .context(core.context), from: core)
        }

        // Then - the next profile contains the same operation with its completed duration.
        XCTAssertEqual(observerCore.metadata.count, 3)
        let completedMetadata = try XCTUnwrap(observerCore.metadata.last as? ProfileAttachments)
        XCTAssertEqual(try eventIDs(ofType: "vital", from: completedMetadata), ["observer-operation-id"])
        let completedOperation = try XCTUnwrap(
            typedRUMEvents(from: completedMetadata).first { $0["id"] as? String == operationStart.id }
        )
        XCTAssertEqual(completedOperation["duration_ns"] as? Int64, 1.seconds.dd.toInt64Nanoseconds)
        XCTAssertTrue(try XCTUnwrap(observerCore.events.last as? ProfileEvent).tags.contains("operation:continuous"))
    }

    func testObserver_writesContinuousProfileWithLocalTTIDOnItsQueue_whenCoordinatorFlushes() throws {
        // Given
        let dateProvider = DateProviderMock()
        let observerCore = PassthroughCoreMock()
        let coordinatorQueue = DispatchQueue(label: "test.app-launch-coordinator-profiler")
        let coordinatorQueueKey = DispatchSpecificKey<Bool>()
        coordinatorQueue.setSpecific(key: coordinatorQueueKey, value: true)
        let observerQueue = DispatchQueue(label: "test.app-launch-observer-profiler")
        let observerQueueKey = DispatchSpecificKey<Bool>()
        observerQueue.setSpecific(key: observerQueueKey, value: true)
        let coordinator = continuousProfiler(
            continuousProfilingSampled: true,
            isAppLaunchProfilingEnabled: true,
            queue: coordinatorQueue,
            dateProvider: dateProvider
        )
        let observer = continuousProfiler(
            core: observerCore,
            continuousProfilingSampled: true,
            isAppLaunchProfilingEnabled: true,
            queue: observerQueue,
            dateProvider: dateProvider
        )
        let observerTTID = Vital.mockWith(id: "observer-ttid-id", name: "time_to_initial_display", stepType: nil)

        XCTAssertEqual(coordinator.role, .coordinator)
        XCTAssertEqual(observer.role, .observer)
        XCTAssertEqual(dd_profiler_start(), 1)

        _ = observer.receive(
            message: .payload(TTIDMessage(attributes: mockRandomAttributes(), ttid: observerTTID)),
            from: observerCore
        )
        observerQueue.sync {}
        XCTAssertTrue(observerCore.events.isEmpty)

        let writeExpectation = expectation(description: "observer profile write")
        observerCore.onEventWriteContext = { _ in
            XCTAssertFalse(DispatchQueue.getSpecific(key: coordinatorQueueKey) == true)
            XCTAssertTrue(DispatchQueue.getSpecific(key: observerQueueKey) == true)
            writeExpectation.fulfill()
        }
        defer { observerCore.onEventWriteContext = nil }

        // When - coordinator flushes the shared native profile.
        core.context = .mockWith(applicationStateHistory: .mockWith(
            initialState: .active,
            date: dateProvider.now.addingTimeInterval(-1),
            transitions: [(state: .background, date: dateProvider.now)]
        ))
        _ = coordinator.receive(message: .context(core.context), from: core)
        waitForExpectations(timeout: 1.0)

        // Then
        XCTAssertTrue(core.events.isEmpty)
        let observerMetadata = try XCTUnwrap(observerCore.metadata.first as? ProfileAttachments)
        XCTAssertEqual(try eventIDs(ofType: "vital", from: observerMetadata), ["observer-ttid-id"])
        let observerEvent = try XCTUnwrap(observerCore.events.first as? ProfileEvent)
        XCTAssertTrue(observerEvent.tags.contains("operation:continuous"))
    }

    func testObserver_writesStandaloneAppLaunchProfile_whenContinuousSamplingRejects() throws {
        // Given
        let dateProvider = DateProviderMock()
        let observerCore = PassthroughCoreMock()
        let observerTTID = Vital.mockWith(id: "observer-ttid-id", name: "time_to_initial_display", stepType: nil)
        let coordinator = continuousProfiler(
            continuousProfilingSampled: true,
            isAppLaunchProfilingEnabled: true,
            dateProvider: dateProvider
        )
        let observer = continuousProfiler(
            core: observerCore,
            continuousProfilingSampled: false,
            isAppLaunchProfilingEnabled: true,
            dateProvider: dateProvider
        )

        XCTAssertEqual(coordinator.role, .coordinator)
        XCTAssertEqual(observer.role, .observer)
        XCTAssertEqual(dd_profiler_start(), 1)

        _ = observer.receive(
            message: .payload(TTIDMessage(attributes: mockRandomAttributes(), ttid: observerTTID)),
            from: observerCore
        )

        // When - coordinator flushes the shared native profile.
        core.context = .mockWith(applicationStateHistory: .mockWith(
            initialState: .active,
            date: dateProvider.now.addingTimeInterval(-1),
            transitions: [(state: .background, date: dateProvider.now)]
        ))
        waitForProfileWrite(on: observerCore, timeout: 1.0) {
            _ = coordinator.receive(message: .context(core.context), from: core)
        }

        // Then - the observer cannot write continuous, so it uses the shared first-minute profile for app launch.
        let observerMetadata = try XCTUnwrap(observerCore.metadata.first as? ProfileAttachments)
        XCTAssertEqual(try eventIDs(ofType: "vital", from: observerMetadata), ["observer-ttid-id"])
        let observerEvent = try XCTUnwrap(observerCore.events.first as? ProfileEvent)
        XCTAssertTrue(observerEvent.tags.contains("operation:launch"))
    }

    func testObserver_writesAppLaunchProfile_whenCoordinatorFlushesCustomProfile() throws {
        // Given
        let initialDate = Date().addingTimeInterval(-(DatadogProfiler.Constants.minProfileDuration + 3))
        let dateProvider = DateProviderMock(now: initialDate)
        let observerCore = PassthroughCoreMock()
        let coordinator = customProfiler(isAppLaunchProfilingEnabled: false, dateProvider: dateProvider)
        let observer = customProfiler(core: observerCore, isAppLaunchProfilingEnabled: true, dateProvider: dateProvider)
        let startOperation = Vital.mockWith(
            id: "coordinator-operation-id",
            name: "operation",
            stepType: .start,
            date: dateProvider.now
        )
        let coordinatorTTID = Vital.mockWith(id: "coordinator-ttid-id", name: "time_to_initial_display", stepType: nil)
        let observerTTID = Vital.mockWith(id: "observer-ttid-id", name: "time_to_initial_display", stepType: nil)

        XCTAssertEqual(coordinator.role, .coordinator)
        XCTAssertEqual(observer.role, .observer)
        dd_profiler_start_testing(100, false, 5.seconds.dd.toInt64Nanoseconds, 0)

        _ = coordinator.receive(
            message: .payload(OperationMessage(attributes: mockRandomAttributes(), operation: startOperation)),
            from: core
        )

        _ = coordinator.receive(
            message: .payload(TTIDMessage(attributes: mockRandomAttributes(), ttid: coordinatorTTID)),
            from: core
        )
        _ = observer.receive(
            message: .payload(TTIDMessage(attributes: mockRandomAttributes(), ttid: observerTTID)),
            from: observerCore
        )
        flushQueue()
        XCTAssertTrue(observerCore.events.isEmpty)

        dateProvider.now = dateProvider.now.addingTimeInterval(DatadogProfiler.Constants.minProfileDuration + 1)
        let endOperation = Vital.mockWith(
            name: startOperation.name,
            operationKey: startOperation.operationKey,
            stepType: .end,
            date: dateProvider.now
        )

        // When - the coordinator completes and flushes its custom profile.
        waitForProfileWrite(on: observerCore, timeout: 1.0) {
            _ = coordinator.receive(
                message: .payload(OperationMessage(attributes: mockRandomAttributes(), operation: endOperation)),
                from: core
            )
        }

        // Then - the observer reuses it as an app-launch profile with its own TTID.
        let coordinatorEvent = try XCTUnwrap(core.events.first as? ProfileEvent)
        XCTAssertTrue(coordinatorEvent.tags.contains("operation:custom"))
        let observerMetadata = try XCTUnwrap(observerCore.metadata.first as? ProfileAttachments)
        XCTAssertEqual(try eventIDs(ofType: "vital", from: observerMetadata), ["observer-ttid-id"])
        let observerEvent = try XCTUnwrap(observerCore.events.first as? ProfileEvent)
        XCTAssertTrue(observerEvent.tags.contains("operation:launch"))
    }

    func testObserver_doesNotWriteStandaloneAppLaunchProfile_whenAppLaunchProfilingIsDisabled() {
        // Given
        let dateProvider = DateProviderMock()
        let observerCore = PassthroughCoreMock()
        let coordinator = continuousProfiler(
            continuousProfilingSampled: false,
            isAppLaunchProfilingEnabled: true,
            dateProvider: dateProvider
        )
        let observer = continuousProfiler(
            core: observerCore,
            continuousProfilingSampled: true,
            isAppLaunchProfilingEnabled: false,
            dateProvider: dateProvider
        )

        XCTAssertEqual(coordinator.role, .coordinator)
        XCTAssertEqual(observer.role, .observer)
        XCTAssertEqual(dd_profiler_start(), 1)

        _ = observer.receive(
            message: .payload(TTIDMessage(attributes: mockRandomAttributes(), ttid: appLaunchVital)),
            from: observerCore
        )

        // When - coordinator cuts and broadcasts a standalone app-launch profile.
        waitForProfileWrite(on: observerCore, expectingWrite: false, timeout: 0.15) {
            _ = coordinator.receive(
                message: .payload(TTIDMessage(attributes: mockRandomAttributes(), ttid: appLaunchVital)),
                from: core
            )
        }

        // Then
        XCTAssertTrue(observerCore.events.isEmpty)
    }

    func testObserver_writesStandaloneAppLaunchProfile_whenCoordinatorReceivesTTIDBeforeObserver() throws {
        // Given
        let dateProvider = DateProviderMock()
        let observerCore = PassthroughCoreMock()
        let coordinator = customProfiler(isAppLaunchProfilingEnabled: false, dateProvider: dateProvider)
        let observer = customProfiler(core: observerCore, isAppLaunchProfilingEnabled: true, dateProvider: dateProvider)
        let coordinatorTTID = Vital.mockWith(id: "coordinator-ttid-id", name: "time_to_initial_display", stepType: nil)
        let observerTTID = Vital.mockWith(id: "observer-ttid-id", name: "time_to_initial_display", stepType: nil)

        XCTAssertEqual(coordinator.role, .coordinator)
        XCTAssertEqual(observer.role, .observer)
        XCTAssertEqual(dd_profiler_start(), 1)

        // When - the coordinator cuts the native profile before the observer receives its TTID.
        waitForProfileWrite(on: observerCore, timeout: 1.0) {
            XCTAssertTrue(coordinator.receive(
                message: .payload(TTIDMessage(attributes: mockRandomAttributes(), ttid: coordinatorTTID)),
                from: core
            ))
            flushQueue()
            XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_STOPPED)
            XCTAssertFalse(observer.receive(
                message: .payload(TTIDMessage(attributes: mockRandomAttributes(), ttid: observerTTID)),
                from: observerCore
            ))
        }

        // Then - the observer still writes the coordinator-harvested launch profile with its local TTID.
        XCTAssertTrue(core.events.isEmpty)
        let observerMetadata = try XCTUnwrap(observerCore.metadata.first as? ProfileAttachments)
        XCTAssertEqual(try eventIDs(ofType: "vital", from: observerMetadata), ["observer-ttid-id"])
        let observerEvent = try XCTUnwrap(observerCore.events.first as? ProfileEvent)
        XCTAssertTrue(observerEvent.tags.contains("operation:launch"))
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_STOPPED)
    }

    func testObserver_discardsStandaloneAppLaunchData_whenCoordinatorFlushesNoNativeProfile() throws {
        // Given
        let initialDate = Date().addingTimeInterval(-(DatadogProfiler.Constants.minProfileDuration + 3))
        let dateProvider = DateProviderMock(now: initialDate)
        let observerCore = PassthroughCoreMock()
        let coordinator = customProfiler(isAppLaunchProfilingEnabled: true, dateProvider: dateProvider)
        let observer = customProfiler(core: observerCore, isAppLaunchProfilingEnabled: true, dateProvider: dateProvider)
        let observerTTID = Vital.mockWith(id: "observer-ttid-id", name: "time_to_initial_display", stepType: nil)
        let coordinatorTTID = Vital.mockWith(id: "coordinator-ttid-id", name: "time_to_initial_display", stepType: nil)

        _ = observer.receive(
            message: .payload(TTIDMessage(attributes: mockRandomAttributes(), ttid: observerTTID)),
            from: observerCore
        )

        // When - standalone app-launch harvest runs without a native profile to share.
        waitForProfileWrite(on: observerCore, expectingWrite: false, timeout: 0.3) {
            _ = coordinator.receive(
                message: .payload(TTIDMessage(attributes: mockRandomAttributes(), ttid: coordinatorTTID)),
                from: core
            )
            flushQueue()
        }

        // When - the same coordinator later broadcasts a custom profile.
        dd_profiler_start_testing(100, false, 5.seconds.dd.toInt64Nanoseconds, 0)
        let startOperation = Vital.mockWith(
            id: "coordinator-operation-id",
            name: "operation",
            stepType: .start,
            date: dateProvider.now
        )
        _ = coordinator.receive(
            message: .payload(OperationMessage(attributes: mockRandomAttributes(), operation: startOperation)),
            from: core
        )
        flushQueue()

        dateProvider.now = dateProvider.now.addingTimeInterval(DatadogProfiler.Constants.minProfileDuration + 1)
        let endOperation = Vital.mockWith(
            name: startOperation.name,
            operationKey: startOperation.operationKey,
            stepType: .end,
            date: dateProvider.now
        )

        waitForProfileWrite(timeout: 1.0) {
            _ = coordinator.receive(
                message: .payload(OperationMessage(attributes: mockRandomAttributes(), operation: endOperation)),
                from: core
            )
        }

        // Then - the observer does not attach its stale TTID to the later broadcast.
        let coordinatorEvent = try XCTUnwrap(core.events.first as? ProfileEvent)
        XCTAssertTrue(coordinatorEvent.tags.contains("operation:custom"))
        XCTAssertTrue(observerCore.events.isEmpty)
        withExtendedLifetime(observer) {}
    }
}

// MARK: - Application Launch Profiling

extension DatadogProfilerTests {
    func testReceiveTTIDMessage_whenProfilerSampledOut_reportsMissingProfileWithoutWriting() throws {
        // Given
        let telemetry = TelemetryMock()
        core = PassthroughCoreMock(context: .mockWith(
            launchInfo: .mockWith(launchReason: .userLaunch)
        ))
        let profiler = customProfiler(
            isAppLaunchProfilingEnabled: true,
            telemetryController: ProfilingTelemetryController(telemetry: telemetry)
        )
        _ = profiler.receive(message: .context(core.context), from: core)
        flushQueue()
        dd_profiler_start_testing(0, false, 5.seconds.dd.toInt64Nanoseconds, 0)
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_NOT_STARTED)

        // When
        let result = profiler.receive(
            message: .payload(TTIDMessage(attributes: mockRandomAttributes(), ttid: appLaunchVital)),
            from: core
        )
        flushQueue()

        // Then
        XCTAssertTrue(result)
        XCTAssertTrue(core.events.isEmpty)
        XCTAssertTrue(core.metadata.isEmpty)

        let metric = try lastProfilingSessionMetric(from: telemetry)
        XCTAssertEqual(metric.startReason, ProfilingSessionMetric.StartReason.applicationLaunch.rawValue)
        XCTAssertEqual(metric.appStartInfo, "user_launch")
        XCTAssertNil(metric.duration)
        XCTAssertNil(metric.fileSize)
        XCTAssertEqual(metric.errorMessage, ProfilingSessionMetric.Constants.noProfileErrorMessage)
        XCTAssertNotNil(metric.errorCode)
    }

    func testReceiveTTIDMessage_whenProfilerPrewarmed_doesNotWriteProfile() {
        // Given
        let profiler = customProfiler(isAppLaunchProfilingEnabled: true)
        dd_profiler_start_testing(100, true, 5.seconds.dd.toInt64Nanoseconds, 0)
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_PREWARMED)

        // When
        let result = profiler.receive(
            message: .payload(TTIDMessage(attributes: mockRandomAttributes(), ttid: appLaunchVital)),
            from: core
        )
        flushQueue()

        // Then
        XCTAssertTrue(result)
        XCTAssertTrue(core.events.isEmpty)
    }

    // MARK: - App-launch profile writes

    func testReceiveTTIDMessage_withValidProfileData_createsCorrectProfileEvent() throws {
        // Given
        let telemetry = TelemetryMock()
        let ttidVital = Vital.mockWith(
            id: "ttid-id",
            name: "time_to_initial_display",
            operationKey: nil,
            stepType: nil,
            duration: 1_000_000_000
        )
        let ttfdVital = Vital.mockWith(
            id: "ttfd-id",
            name: "time_to_full_display",
            operationKey: nil,
            stepType: nil,
            duration: 2_000_000_000
        )
        core = PassthroughCoreMock(
            context: .mockWith(
                service: "test-service",
                env: "staging",
                version: "1.2.3",
                source: "ios",
                sdkVersion: "4.5.6",
                os: .mockWith(version: "26.1"),
                launchInfo: .mockWith(launchReason: .backgroundLaunch)
            )
        )
        let profiler = customProfiler(
            isAppLaunchProfilingEnabled: true,
            telemetryController: ProfilingTelemetryController(telemetry: telemetry)
        )
        _ = profiler.receive(message: .context(core.context), from: core)
        flushQueue()
        XCTAssertEqual(dd_profiler_start(), 1)
        Thread.sleep(forTimeInterval: 0.05)
        _ = profiler.receive(
            message: .payload(OperationMessage(attributes: mockRandomAttributes(), operation: ttfdVital)),
            from: core
        )
        flushQueue()
        XCTAssertTrue(core.events.isEmpty)

        // When
        var result = false
        waitForProfileWrite {
            result = profiler.receive(
                message: .payload(TTIDMessage(attributes: mockRandomAttributes(), ttid: ttidVital)),
                from: core
            )
        }

        // Then
        XCTAssertTrue(result)
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_STOPPED)
        let profilingContext = try XCTUnwrap(core.context.additionalContext(ofType: ProfilingContext.self))
        XCTAssertEqual(profilingContext.status, .stopped(reason: .manual))

        XCTAssertEqual(core.events.count, 1)
        let event = try XCTUnwrap(core.events.first as? ProfileEvent)
        let metadata = try XCTUnwrap(core.metadata.first as? ProfileAttachments)

        XCTAssertTrue(metadata.rumEvents != nil)
        XCTAssertEqual(Set(try eventIDs(ofType: "vital", from: metadata)), Set(["ttid-id", "ttfd-id"]))
        XCTAssertEqual(event.family, "ios")
        XCTAssertEqual(event.runtime, "ios")
        XCTAssertEqual(event.version, "4")
        XCTAssertEqual(event.attachments, [ProfileAttachments.Constants.pprofFilename, ProfileAttachments.Constants.rumEventsFilename])

        let expectedTags = [
            "service:test-service",
            "version:1.2.3",
            "sdk_version:4.5.6",
            "profiler_version:4.5.6",
            "runtime_version:26.1",
            "env:staging",
            "source:ios",
            "language:swift",
            "format:pprof",
            "remote_symbols:yes",
            "operation:launch"
        ].joined(separator: ",")
        XCTAssertEqual(event.tags, expectedTags)

        XCTAssertNotNil(event.start)
        XCTAssertNotNil(event.end)
        XCTAssertTrue(event.end >= event.start)
        let attributeVitalIDs = try XCTUnwrap(event.additionalAttributes?[RUMCoreContext.IDs.vitalID] as? [String])
        XCTAssertEqual(Set(attributeVitalIDs), Set(["ttid-id", "ttfd-id"]))

        let metric = try lastProfilingSessionMetric(from: telemetry)
        XCTAssertEqual(metric.startReason, ProfilingSessionMetric.StartReason.applicationLaunch.rawValue)
        XCTAssertEqual(metric.appStartInfo, "background_launch")
        XCTAssertNotNil(metric.duration)
        XCTAssertNotNil(metric.fileSize)
        XCTAssertEqual(metric.stoppedReason, ProfilingContext.Status.StopReason.manual.rawValue)
        XCTAssertNil(metric.errorCode)
        XCTAssertNil(metric.errorMessage)

        let metricTelemetry = try XCTUnwrap(telemetry.messages.lastMetric(named: ProfilingSessionMetric.Constants.name))
        XCTAssertEqual(metricTelemetry.sampleRate, 20)

        // When - more RUM data and a duplicate TTID arrive after app-launch was harvested.
        _ = profiler.receive(
            message: .payload(OperationMessage(attributes: mockRandomAttributes(), operation: startOperationVital)),
            from: core
        )
        _ = profiler.receive(
            message: .payload(TTIDMessage(attributes: mockRandomAttributes(), ttid: ttidVital)),
            from: core
        )
        flushQueue()

        // Then - app-launch is emitted only once.
        XCTAssertEqual(core.events.count, 1)
    }

    func testReceiveTTIDMessage_correctsAttachedVitalTimestampWithServerTimeOffset() throws {
        // Given
        let profiler = customProfiler(isAppLaunchProfilingEnabled: true)
        let serverTimeOffset: TimeInterval = 2
        let launchDate = Date(timeIntervalSince1970: 10)
        let launchVital = Vital.mockWith(
            id: "launch-vital-id",
            name: "launch-vital-name",
            operationKey: nil,
            stepType: nil,
            date: launchDate,
            serverTimeOffset: serverTimeOffset
        )
        dd_profiler_start_testing(100, false, 5.seconds.dd.toInt64Nanoseconds, 0)
        Thread.sleep(forTimeInterval: 0.05)

        // When
        waitForProfileWrite {
            _ = profiler.receive(
                message: .payload(TTIDMessage(attributes: mockRandomAttributes(), ttid: launchVital)),
                from: core
            )
        }

        // Then
        let metadata = try XCTUnwrap(core.metadata.first as? ProfileAttachments)
        let vitals = try typedRUMEvents(from: metadata).filter { $0["type"] as? String == "vital" }
        let start = try XCTUnwrap(vitals.first?["start_ns"] as? Int64)
        XCTAssertEqual(start, launchDate.addingTimeInterval(serverTimeOffset).timeIntervalSince1970.dd.toInt64Nanoseconds)
    }
}

// MARK: - Profiling Context Status

extension DatadogProfilerTests {
    func testProfilingContextStatus_mapsCorrectlyFromDDProfilerStatus() {
        let cases: [(dd_profiler_status_t, ProfilingContext.Status)] = [
            (DD_PROFILER_STATUS_NOT_STARTED, .stopped(reason: .notStarted)),
            (DD_PROFILER_STATUS_RUNNING, .running),
            (DD_PROFILER_STATUS_STOPPED, .stopped(reason: .manual)),
            (DD_PROFILER_STATUS_TIMEOUT, .stopped(reason: .timeout)),
            (DD_PROFILER_STATUS_PREWARMED, .stopped(reason: .prewarmed)),
            (DD_PROFILER_STATUS_ALLOCATION_FAILED, .error(reason: .memoryAllocationFailed)),
        ]

        for (cStatus, swiftStatus) in cases {
            XCTAssertEqual(.init(cStatus), swiftStatus, "Status mapping for \(cStatus) should be \(swiftStatus)")
        }

        XCTAssertEqual(dd_profiler_start(), 1)
        XCTAssertEqual(ProfilingContext.Status.current, .running)
    }
}

// MARK: - Profiling Defaults

extension DatadogProfilerTests {
    func testProfilingDefaults_reflectStoredValueAndCanBeDeletedRepeatedly() throws {
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: DD_PROFILING_USER_DEFAULTS_SUITE_NAME))

        // No stored value defaults to disabled.
        XCTAssertFalse(dd_is_profiling_enabled())

        // Values are shared by all instances of the profiling defaults suite.
        userDefaults.setValue(true, forKey: DD_PROFILING_IS_ENABLED_KEY)
        let otherUserDefaults = try XCTUnwrap(UserDefaults(suiteName: DD_PROFILING_USER_DEFAULTS_SUITE_NAME))
        XCTAssertEqual(otherUserDefaults.value(forKey: DD_PROFILING_IS_ENABLED_KEY) as? Bool, true)
        XCTAssertTrue(dd_is_profiling_enabled())

        userDefaults.setValue(false, forKey: DD_PROFILING_IS_ENABLED_KEY)
        XCTAssertFalse(dd_is_profiling_enabled())

        // Deletion removes the stored key and remains idempotent.
        userDefaults.setValue(true, forKey: DD_PROFILING_IS_ENABLED_KEY)
        dd_delete_profiling_defaults()
        dd_delete_profiling_defaults()
        dd_delete_profiling_defaults()
        XCTAssertFalse(dd_is_profiling_enabled())
        XCTAssertNil(userDefaults.value(forKey: DD_PROFILING_IS_ENABLED_KEY))
    }
}

// MARK: - Application Launch Quota

extension DatadogProfilerTests {
    func testReceiveTTIDMessage_whenQuotaIsRejected_dropsProfileAndSendsProfileDroppedMetric() throws {
        // Given
        let telemetry = TelemetryMock()
        let quotaChecker = ProfilingQuotaCheckerMock()
        quotaChecker.quotaResult = .init(decision: .quotaKO, reason: .quotaExceeded)
        core = PassthroughCoreMock(context: .mockWith(
            launchInfo: .mockWith(launchReason: .userLaunch)
        ))
        let profiler = customProfiler(
            isAppLaunchProfilingEnabled: true,
            telemetryController: ProfilingTelemetryController(telemetry: telemetry),
            quotaChecker: quotaChecker
        )
        _ = profiler.receive(message: .context(core.context), from: core)
        flushQueue()

        XCTAssertEqual(dd_profiler_start(), 1)
        Thread.sleep(forTimeInterval: 0.05)
        let rejectedLaunchProfile = try XCTUnwrap(dd_profiler_get_profile())

        // When
        _ = profiler.receive(message: .payload(TTIDMessage(attributes: mockRandomAttributes(), ttid: appLaunchVital)), from: core)
        flushQueue()

        // Then
        XCTAssertTrue(core.events.isEmpty)
        XCTAssertTrue(core.metadata.isEmpty)
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_STOPPED)
        XCTAssertNotEqual(dd_profiler_get_profile(), rejectedLaunchProfile)

        let profilingContext = try XCTUnwrap(core.context.additionalContext(ofType: ProfilingContext.self))
        XCTAssertEqual(profilingContext.quotaReason, .quotaExceeded)

        let metric = try lastProfilingSessionMetric(from: telemetry)
        XCTAssertEqual(metric.startReason, ProfilingSessionMetric.StartReason.applicationLaunch.rawValue)
        XCTAssertEqual(metric.appStartInfo, "user_launch")
        XCTAssertNil(metric.duration)
        XCTAssertNil(metric.fileSize)
        XCTAssertEqual(
            metric.errorMessage,
            "\(ProfilingSessionMetric.Constants.quotaErrorMessage) Quota reason: quota_exceeded."
        )
    }
}

// MARK: - Private

private extension DatadogProfilerTests {
    func waitForProfileWrite(
        on targetCore: PassthroughCoreMock? = nil,
        expectingWrite: Bool = true,
        timeout: TimeInterval = 0.1,
        action: () -> Void
    ) {
        let expectation = expectingWrite
            ? expectation(description: "profile write")
            : invertedExpectation(description: "unexpected profile write")
        let targetCore = targetCore ?? core
        targetCore?.onEventWriteContext = { _ in expectation.fulfill() }
        defer { targetCore?.onEventWriteContext = nil }

        action()

        waitForExpectations(timeout: timeout)
    }

    func flushQueue() {
        profilerQueue.sync {}
    }

    func typedRUMEvents(from metadata: ProfileAttachments) throws -> [[String: Any]] {
        let rumEventsData = try XCTUnwrap(metadata.rumEvents)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: rumEventsData) as? [[String: Any]])
    }

    func eventIDs(ofType type: String, in rumEvents: [[String: Any]]) -> [String] {
        rumEvents
            .filter { $0["type"] as? String == type }
            .compactMap { $0["id"] as? String }
    }

    func eventIDs(ofType type: String, from metadata: ProfileAttachments) throws -> [String] {
        eventIDs(ofType: type, in: try typedRUMEvents(from: metadata))
    }

    var startOperationVital: Vital {
        .mockWith(stepType: .start)
    }

    var appLaunchVital: Vital {
        .mockWith(stepType: nil)
    }

    func continuousProfiler(
        core: PassthroughCoreMock? = nil,
        profilingSamplerProvider: ProfilingSamplerProvider = ProfilingSamplerProvider(continuousSampleRate: .maxSampleRate),
        continuousProfilingSampled: Bool? = nil,
        profilingConditions: ProfilingConditions = ProfilingConditions(),
        profilingInterval: TimeInterval = .infinity,
        isAppLaunchProfilingEnabled: Bool = false,
        queue: DispatchQueue? = nil,
        telemetryController: ProfilingTelemetryController = .init(),
        dateProvider: DateProvider = DateProviderMock(),
        quotaChecker: ProfilingQuotaChecking = ProfilingQuotaCheckerMock()
    ) -> DatadogProfiler {
        if let continuousProfilingSampled {
            profilingSamplerProvider.updateWith(
                deterministicSampler: DeterministicSampler(
                    uuid: .mockRandom(),
                    samplingRate: continuousProfilingSampled ? .maxSampleRate : 0
                )
            )
        }

        return DatadogProfiler(
            core: core ?? self.core,
            profilingSamplerProvider: profilingSamplerProvider,
            quotaChecker: quotaChecker,
            queue: queue ?? profilerQueue,
            telemetryController: telemetryController,
            profilingConditions: profilingConditions,
            profilingInterval: profilingInterval,
            isAppLaunchProfilingEnabled: isAppLaunchProfilingEnabled,
            dateProvider: dateProvider
        )
    }

    func customProfiler(
        core: PassthroughCoreMock? = nil,
        profilingConditions: ProfilingConditions = ProfilingConditions(),
        profilingInterval: TimeInterval = .infinity,
        isAppLaunchProfilingEnabled: Bool = false,
        queue: DispatchQueue? = nil,
        telemetryController: ProfilingTelemetryController = .init(),
        dateProvider: DateProvider = DateProviderMock(),
        quotaChecker: ProfilingQuotaChecking = ProfilingQuotaCheckerMock()
    ) -> DatadogProfiler {
        DatadogProfiler(
            core: core ?? self.core,
            profilingSamplerProvider: profilingSamplerProvider(isContinuousProfiling: false),
            quotaChecker: quotaChecker,
            queue: queue ?? profilerQueue,
            telemetryController: telemetryController,
            profilingConditions: profilingConditions,
            profilingInterval: profilingInterval,
            isAppLaunchProfilingEnabled: isAppLaunchProfilingEnabled,
            dateProvider: dateProvider
        )
    }

    func profilingSamplerProvider(isContinuousProfiling: Bool) -> ProfilingSamplerProvider {
        ProfilingSamplerProvider(continuousSampleRate: isContinuousProfiling ? .maxSampleRate : 0)
    }

    func quotaChecker() -> ProfilingQuotaCheckerMock {
        let quotaChecker = ProfilingQuotaCheckerMock()
        quotaChecker.receiveHandler = { _ in
            .init(decision: .quotaOK, reason: .quotaOk)
        }
        return quotaChecker
    }

    func shareCurrentContext(with profiler: DatadogProfiler) {
        _ = profiler.receive(message: .context(core.context), from: core)
        flushQueue()
    }

    func lastProfilingSessionMetric(from telemetry: TelemetryMock) throws -> ProfilingSessionMetric.Attributes {
        let metricTelemetry = try XCTUnwrap(telemetry.messages.lastMetric(named: ProfilingSessionMetric.Constants.name))
        return try XCTUnwrap(metricTelemetry.attributes[ProfilingSessionMetric.Constants.sessionKey] as? ProfilingSessionMetric.Attributes)
    }

    func firstProfilingSessionMetric(from telemetry: TelemetryMock) throws -> ProfilingSessionMetric.Attributes {
        let metricTelemetry = try XCTUnwrap(telemetry.messages.firstMetric(named: ProfilingSessionMetric.Constants.name))
        return try XCTUnwrap(metricTelemetry.attributes[ProfilingSessionMetric.Constants.sessionKey] as? ProfilingSessionMetric.Attributes)
    }

    func connectMessageReceiver(
        to profiler: DatadogProfiler,
        profilingSamplerProvider: ProfilingSamplerProvider,
        quotaChecker: ProfilingQuotaChecking? = nil
    ) {
        var receivers: [FeatureMessageReceiver] = [
            ProfilingContextMessageReceiver(profilingSamplerProvider: profilingSamplerProvider),
            profiler
        ]
        if let quotaChecker {
            receivers.append(quotaChecker)
        }

        let messageReceiver = CombinedFeatureMessageReceiver(receivers)
        core.messageReceiver = messageReceiver
        _ = messageReceiver.receive(message: .context(core.context), from: core)
        flushQueue()
    }

    func waitUntil(
        timeout: TimeInterval,
        pollInterval: TimeInterval = 0.01,
        file: StaticString = #filePath,
        line: UInt = #line,
        condition: () -> Bool
    ) {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if condition() {
                return
            }

            Thread.sleep(forTimeInterval: pollInterval)
        }

        XCTFail("Condition was not met within \(timeout) seconds.", file: file, line: line)
    }
}
#endif // !os(watchOS)
