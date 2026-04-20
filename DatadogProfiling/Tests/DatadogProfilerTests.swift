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

        // When
        var result = profiler.receive(
            message: .payload(OperationMessage(attributes: mockRandomAttributes(), operation: startOperation)),
            from: core
        )

        // Then
        XCTAssertFalse(result, "Continuous profiler and AppLaunch profiler consume RUM operations")

        // When
        result = profiler.receive(
            message: .payload(OperationMessage(attributes: mockRandomAttributes(), operation: endOperation)),
            from: core
        )

        // Then
        XCTAssertFalse(result, "Continuous profiler and AppLaunch profiler consume RUM operations")

        // When
        result = profiler.receive(
            message: .payload(TTIDMessage(attributes: mockRandomAttributes(), ttid: launchVital)),
            from: core
        )

        // Then
        XCTAssertFalse(result, "Continuous profiler and AppLaunch profiler consume app launch vitals")
    }

    func testReceiveLongTask() {
        // Given
        let profiler = continuousProfiler()
        let longTask = DurationEvent(id: .mockRandom(), type: .longTask, start: 0, duration: 100)

        // When
        let result = profiler.receive(
            message: .payload(LongTaskMessage(attributes: mockRandomAttributes(), longTask: longTask)),
            from: core
        )

        // Then
        XCTAssertTrue(result, "Long tasks should be consumed by continuous profiler after app launch")
    }

    func testReceiveAppHang() {
        // Given
        let profiler = continuousProfiler()
        let hang = DurationEvent(id: .mockRandom(), type: .error, start: 0, duration: 500)

        // When
        let result = profiler.receive(
            message: .payload(AppHangMessage(attributes: mockRandomAttributes(), hang: hang)),
            from: core
        )

        // Then
        XCTAssertTrue(result, "App hangs should be consumed by continuous profiler after app launch")
    }

    func testReceiveApplicationLaunchVital_capturesOngoingRUMVitals() throws {
        // Given
        let dateProvider = DateProviderMock()
        let profiler = continuousProfiler(dateProvider: dateProvider)
        let completedOperationStart = Vital.mockWith(name: "completed-operation")
        let completedOperationEnd = Vital.mockWith(
            name: completedOperationStart.name,
            operationKey: completedOperationStart.operationKey,
            stepType: .end
        )
        let ongoingOperationStart = Vital.mockWith(name: "ongoing-operation", stepType: .start)
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

        // When - receive TTID to clean up completed events, then transition to background to flush profile
        core.context = .mockWith(applicationStateHistory: .mockWith(
            initialState: .active,
            date: dateProvider.now.addingTimeInterval(-1),
            transitions: [(state: .background, date: dateProvider.now)]
        ))
        waitForProfileWrite {
            XCTAssertFalse(
                profiler.receive(
                    message: .payload(TTIDMessage(attributes: mockRandomAttributes(), ttid: launchVital)),
                    from: core
                )
            )
            _ = profiler.receive(message: .context(core.context), from: core)
        }

        // Then
        let metadata = try XCTUnwrap(core.metadata.first as? ProfileAttachments)
        let rumEvents = try typedRUMEvents(from: metadata)
        let vitalIDs = eventIDs(ofType: "vital", in: rumEvents)
        XCTAssertEqual(vitalIDs, [ongoingOperationStart.id], "Only ongoing operations should remain after TTID")
        XCTAssertTrue(
            eventIDs(ofType: "error", in: rumEvents).isEmpty,
            "App hangs handled by AppLaunchProfiler should not be re-attached"
        )
        XCTAssertTrue(
            eventIDs(ofType: "long_task", in: rumEvents).isEmpty,
            "Long tasks handled by AppLaunchProfiler should not be re-attached"
        )
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
        waitForProfileWrite {
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

        let longTask = DurationEvent(id: .mockRandom(), type: .longTask, start: 0, duration: 100)
        _ = profiler.receive(message: .payload(LongTaskMessage(attributes: mockRandomAttributes(), longTask: longTask)), from: core)
        flushQueue()

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

    func testApplicationDidEnterBackground_includesAppHangsInProfile() throws {
        // Given
        let dateProvider = DateProviderMock()
        let profilingSamplerProvider = profilingSamplerProvider(isContinuousProfiling: true)
        profilingSamplerProvider.updateWith(
            deterministicSampler: DeterministicSampler(uuid: .mockRandom(), samplingRate: .maxSampleRate)
        )
        let profiler = continuousProfiler(profilingSamplerProvider: profilingSamplerProvider, dateProvider: dateProvider)
        dd_profiler_start_testing(100, false, 5.seconds.dd.toInt64Nanoseconds, 0)

        let hang = DurationEvent(id: .mockRandom(), type: .error, start: 0, duration: 500)
        XCTAssertTrue(profiler.receive(message: .payload(AppHangMessage(attributes: mockRandomAttributes(), hang: hang)), from: core))

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
        let profiler = continuousProfiler(profilingSamplerProvider: profilingSamplerProvider)
        connectMessageReceiver(to: profiler, profilingSamplerProvider: profilingSamplerProvider)
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_NOT_CREATED)

        // When
        core.context = .mockWith(applicationStateHistory: .mockAppInForeground())
        flushQueue()

        // Then
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_RUNNING)
        withExtendedLifetime(profiler) {}
    }

    func testReceiveContextWhenContinuousProfilingSamplesOut_andVitalIsOngoing() {
        // Given
        core = PassthroughCoreMock(context: .mockWith(applicationStateHistory: .mockAppInBackground()))
        let profilingSamplerProvider = profilingSamplerProvider(isContinuousProfiling: true)
        let profiler = continuousProfiler(profilingSamplerProvider: profilingSamplerProvider)
        connectMessageReceiver(to: profiler, profilingSamplerProvider: profilingSamplerProvider)
        let startOperation = Vital.mockWith(stepType: .start)
        core.context = .mockWith(
            applicationStateHistory: .mockAppInForeground(),
            additionalContext: [RUMCoreContext.mockWith(sessionSampleRate: .maxSampleRate)]
        )
        flushQueue()
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_RUNNING)
        _ = profiler.receive(
            message: .payload(OperationMessage(attributes: mockRandomAttributes(), operation: startOperation)),
            from: core
        )

        // When
        core.context = .mockWith(
            applicationStateHistory: .mockAppInForeground(),
            additionalContext: [RUMCoreContext.mockWith(sessionSampleRate: 0)]
        )
        flushQueue()

        // Then
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_RUNNING)
        withExtendedLifetime(profiler) {}
    }

    func testReceiveOperationStartWhenContinuousProfilingSamplesOut_andVitalStarts() {
        // Given
        let profilingSamplerProvider = profilingSamplerProvider(isContinuousProfiling: true)
        profilingSamplerProvider.updateWith(
            deterministicSampler: DeterministicSampler(uuid: .mockRandom(), samplingRate: 0)
        )
        let profiler = continuousProfiler(profilingSamplerProvider: profilingSamplerProvider)
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_NOT_CREATED)

        let startOperation = Vital.mockWith(stepType: .start)

        // When
        _ = profiler.receive(
            message: .payload(OperationMessage(attributes: mockRandomAttributes(), operation: startOperation)),
            from: core
        )
        flushQueue()

        // Then
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_RUNNING)
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
        waitForProfileWrite(expectingWrite: false, timeout: 0.15) {}

        // Then
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_STOPPED)
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
        dd_profiler_start_testing(0, false, 5.seconds.dd.toInt64Nanoseconds, 0)
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_NOT_STARTED)

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
        waitForProfileWrite {
            _ = profiler.receive(
                message: .payload(OperationMessage(attributes: mockRandomAttributes(), operation: endOperation)),
                from: core
            )
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
        waitForProfileWrite {
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
        flushQueue()

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
        flushQueue()

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

    func testCustomProfiler_startsProfilerOnFirstRUMOperationStart() {
        // Given
        dd_profiler_start_testing(0, false, 5.seconds.dd.toInt64Nanoseconds, 0)
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_NOT_STARTED)

        let dateProvider = DateProviderMock()
        let profiler = customProfiler(dateProvider: dateProvider)
        shareCurrentContext(with: profiler)

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

        // Then
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_RUNNING, "Custom profiler should start on first RUM operation")
        withExtendedLifetime(profiler) {}
    }

    func testCustomProfiler_doesNotRestartRunningProfilerOnOperation() {
        // Given
        dd_profiler_start_testing(100, false, 5.seconds.dd.toInt64Nanoseconds, 0)
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_RUNNING)

        let dateProvider = DateProviderMock()
        let profiler = customProfiler(dateProvider: dateProvider)
        shareCurrentContext(with: profiler)

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

        // Then - profiler stays running without error
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_RUNNING)
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
        // Put profiler in NOT_STARTED state (fresh instance, never started) so the custom profiler can start it
        dd_profiler_start_testing(0, false, 5.seconds.dd.toInt64Nanoseconds, 0)
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_NOT_STARTED)

        let startOp: Vital = .mockWith(stepType: .start, date: dateProvider.now)
        // Custom profiler auto-starts on first .start operation
        _ = profiler.receive(message: .payload(OperationMessage(attributes: mockRandomAttributes(), operation: startOp)), from: core)
        flushQueue()
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_RUNNING)

        // Advance dateProvider by minProfileDuration+1 — the result is still in the past,
        // so fireTimer(after: 0) sets a past fireDate and the timer fires immediately.
        dateProvider.now = dateProvider.now.addingTimeInterval(DatadogProfiler.Constants.minProfileDuration + 1)

        let endOp: Vital = .mockWith(name: startOp.name, operationKey: startOp.operationKey, stepType: .end)

        // When - operations complete, profiler stops and writes via timer (no background notification needed)
        waitForProfileWrite {
            _ = profiler.receive(message: .payload(OperationMessage(attributes: mockRandomAttributes(), operation: endOp)), from: core)
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
        dd_profiler_start_testing(0, false, 5.seconds.dd.toInt64Nanoseconds, 0)

        let startOp = Vital.mockWith(id: "start-id", name: "operation", stepType: .start, date: dateProvider.now)
        _ = profiler.receive(message: .payload(OperationMessage(attributes: mockRandomAttributes(), operation: startOp)), from: core)
        flushQueue()

        dateProvider.now = dateProvider.now.addingTimeInterval(DatadogProfiler.Constants.minProfileDuration + 1)

        let endOp = Vital.mockWith(id: "end-id", name: startOp.name, operationKey: startOp.operationKey, stepType: .end)

        // When
        waitForProfileWrite {
            _ = profiler.receive(message: .payload(OperationMessage(attributes: mockRandomAttributes(), operation: endOp)), from: core)
        }

        // Then
        let metadata = try XCTUnwrap(core.metadata.first as? ProfileAttachments)
        let rumEvents = try typedRUMEvents(from: metadata)
        let vitalIDs = eventIDs(ofType: "vital", in: rumEvents)
        XCTAssertTrue(vitalIDs.contains("start-id"))
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
        dd_profiler_start_testing(0, false, 5.seconds.dd.toInt64Nanoseconds, 0)

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
        let profiler = customProfiler(dateProvider: dateProvider)
        shareCurrentContext(with: profiler)
        dd_profiler_start_testing(0, false, 5.seconds.dd.toInt64Nanoseconds, 0)

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
        let profiler = customProfiler(dateProvider: dateProvider)
        shareCurrentContext(with: profiler)
        dd_profiler_start_testing(0, false, 5.seconds.dd.toInt64Nanoseconds, 0)

        let startOp: Vital = .mockWith(stepType: .start, date: dateProvider.now)
        _ = profiler.receive(message: .payload(OperationMessage(attributes: mockRandomAttributes(), operation: startOp)), from: core)
        flushQueue()

        // Advance past customProfilingCutOffTime
        dateProvider.now = dateProvider.now.addingTimeInterval(DatadogProfiler.Constants.customProfilingCutOffTime + 1)

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
        flushQueue()

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
        flushQueue()

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
    func testSingletonGuard() {
        // When
        let profiler = continuousProfiler()

        // Then
        XCTAssertTrue(DatadogProfiler.isInstantiated)
        XCTAssertNotNil(profiler)
    }

    func testSingletonGuard_secondInstanceIsIgnored() {
        // Given
        let first = continuousProfiler()
        XCTAssertTrue(DatadogProfiler.isInstantiated)
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_NOT_CREATED)

        // When
        let second = DatadogProfiler(
            core: core,
            profilingSamplerProvider: profilingSamplerProvider(isContinuousProfiling: true)
        )
        XCTAssertNil(second)

        // Then - first still processes messages normally
        let hang = DurationEvent(id: .mockRandom(), type: .error, start: 0, duration: 500)
        XCTAssertTrue(first.receive(message: .payload(AppHangMessage(attributes: mockRandomAttributes(), hang: hang)), from: core))
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
                profilingSamplerProvider: profilingSamplerProvider(isContinuousProfiling: true)
            )
            lock.lock()
            profilers.append(profiler)
            lock.unlock()
            expectation.fulfill()
        }

        // Then
        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(profilers.compactMap { $0 }.count, 1, "Exactly one instance should have been created")
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
        flushQueue()

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

    func testContinuousProfiler_sendsProfilingSessionMetric_whenProfileIsNotWritten() throws {
        // Given
        let telemetry = TelemetryMock()
        let telemetryController = ProfilingTelemetryController(telemetry: telemetry)
        let profilingSamplerProvider = profilingSamplerProvider(isContinuousProfiling: true)
        profilingSamplerProvider.updateWith(
            deterministicSampler: DeterministicSampler(uuid: .mockRandom(), samplingRate: .maxSampleRate)
        )
        let profiler = continuousProfiler(
            profilingSamplerProvider: profilingSamplerProvider,
            profilingInterval: 0.05,
            telemetryController: telemetryController
        )
        dd_profiler_start_testing(100, false, 5.seconds.dd.toInt64Nanoseconds, 0)

        // When
        waitForProfileWrite(expectingWrite: false, timeout: 0.15) {}

        // Then
        let metric = try firstProfilingSessionMetric(from: telemetry)
        XCTAssertEqual(metric.startReason, ProfilingSessionMetric.StartReason.continuous.rawValue)
        XCTAssertEqual(metric.cycleIndex, 0)
        XCTAssertNil(metric.duration)
        XCTAssertNil(metric.fileSize)
        XCTAssertEqual(metric.errorMessage, ProfilingSessionMetric.Constants.profileNotWrittenErrorMessage)
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
        dd_profiler_start_testing(0, false, 5.seconds.dd.toInt64Nanoseconds, 0)

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
        waitForProfileWrite {
            _ = profiler.receive(message: .payload(OperationMessage(attributes: mockRandomAttributes(), operation: endOperation)), from: core)
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

// MARK: - Private

private extension DatadogProfilerTests {
    func waitForProfileWrite(
        expectingWrite: Bool = true,
        timeout: TimeInterval = 0.1,
        action: () -> Void
    ) {
        let expectation = expectingWrite
            ? expectation(description: "profile write")
            : invertedExpectation(description: "unexpected profile write")
        core.onEventWriteContext = { _ in expectation.fulfill() }
        defer { core.onEventWriteContext = nil }

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

    func continuousProfiler(
        profilingSamplerProvider: ProfilingSamplerProvider = ProfilingSamplerProvider(continuousSampleRate: .maxSampleRate),
        profilingConditions: ProfilingConditions = ProfilingConditions(),
        profilingInterval: TimeInterval = .infinity,
        telemetryController: ProfilingTelemetryController = .init(),
        dateProvider: DateProvider = DateProviderMock()
    ) -> DatadogProfiler {
        DatadogProfiler(
            core: core,
            profilingSamplerProvider: profilingSamplerProvider,
            queue: profilerQueue,
            telemetryController: telemetryController,
            profilingConditions: profilingConditions,
            profilingInterval: profilingInterval,
            dateProvider: dateProvider
        )! // swiftlint:disable:this force_unwrapping
    }

    func customProfiler(
        profilingConditions: ProfilingConditions = ProfilingConditions(),
        profilingInterval: TimeInterval = .infinity,
        telemetryController: ProfilingTelemetryController = .init(),
        dateProvider: DateProvider = DateProviderMock()
    ) -> DatadogProfiler {
        DatadogProfiler(
            core: core,
            profilingSamplerProvider: profilingSamplerProvider(isContinuousProfiling: false),
            queue: profilerQueue,
            telemetryController: telemetryController,
            profilingConditions: profilingConditions,
            profilingInterval: profilingInterval,
            dateProvider: dateProvider
        )! // swiftlint:disable:this force_unwrapping
    }

    func profilingSamplerProvider(isContinuousProfiling: Bool) -> ProfilingSamplerProvider {
        ProfilingSamplerProvider(continuousSampleRate: isContinuousProfiling ? .maxSampleRate : 0)
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
}
#endif // !os(watchOS)
