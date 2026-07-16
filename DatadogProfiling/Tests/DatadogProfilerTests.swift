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

    func testReceiveTTFDMessage_afterApplicationLaunchVital() {
        // Given
        let profiler = continuousProfiler()
        let launchVital: Vital = .mockWith(stepType: nil)

        _ = profiler.receive(
            message: .payload(TTIDMessage(attributes: mockRandomAttributes(), ttid: launchVital)),
            from: core
        )

        // When
        let result = profiler.receive(
            message: .payload(OperationMessage(
                attributes: mockRandomAttributes(),
                operation: .mockWith(stepType: nil, duration: 2_000_000_000)
            )),
            from: core
        )

        // Then
        XCTAssertTrue(result, "Operation messages should be consumed by continuous profiler after app launch")
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
        waitForProfileWrite {
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

        let attributes: [AttributeKey: AttributeValue] = [
            RUMCoreContext.IDs.sessionID: "long-task-session-id",
            RUMCoreContext.IDs.viewID: ["long-task-view-id"]
        ]
        let longTask = DurationEvent(id: .mockRandom(), type: .longTask, start: 0, duration: 100)
        _ = profiler.receive(message: .payload(LongTaskMessage(attributes: attributes, longTask: longTask)), from: core)
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
        let event = try XCTUnwrap(core.events.first as? ProfileEvent)
        XCTAssertEqual(event.additionalAttributes?[RUMCoreContext.IDs.sessionID] as? String, "long-task-session-id")
        XCTAssertEqual(event.additionalAttributes?[RUMCoreContext.IDs.viewID] as? [String], ["long-task-view-id"])
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
            RUMCoreContext.IDs.viewID: ["app-hang-view-id"]
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
        XCTAssertEqual(event.additionalAttributes?[RUMCoreContext.IDs.viewID] as? [String], ["app-hang-view-id"])
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

    func testReceiveContext_stopsContinuousProfiler_whenSessionIsSampledOut() {
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
        _ = profiler.receive(
            message: .payload(TTIDMessage(attributes: mockRandomAttributes(), ttid: .mockWith())),
            from: core
        )
        flushQueue()

        // When
        core.context = .mockWith(
            applicationStateHistory: .mockAppInForeground(),
            additionalContext: [RUMCoreContext.mockWith(sessionSampleRate: 0)]
        )
        flushQueue()

        // Then
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_STOPPED)
        withExtendedLifetime(profiler) {}
    }

    func testReceiveContext_keepsNativeProfilerRunning_whenSessionIsSampledOutBeforeAppLaunchVital() {
        // Given
        core = PassthroughCoreMock(context: .mockWith(applicationStateHistory: .mockAppInBackground()))
        let profilingSamplerProvider = profilingSamplerProvider(isContinuousProfiling: true)
        let profiler = continuousProfiler(profilingSamplerProvider: profilingSamplerProvider)
        connectMessageReceiver(to: profiler, profilingSamplerProvider: profilingSamplerProvider)
        core.context = .mockWith(applicationStateHistory: .mockAppInForeground())
        flushQueue()
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_RUNNING)

        // When - the RUM session samples out before AppLaunchProfiler can harvest TTID.
        core.context = .mockWith(
            applicationStateHistory: .mockAppInForeground(),
            additionalContext: [RUMCoreContext.mockWith(sessionSampleRate: 0)]
        )
        flushQueue()

        // Then - app-launch profiling keeps the shared native profiler alive.
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_RUNNING)

        // When - TTID is processed.
        _ = profiler.receive(
            message: .payload(TTIDMessage(attributes: mockRandomAttributes(), ttid: .mockWith())),
            from: core
        )
        flushQueue()

        // Then - the sampled-out continuous profiler can stop after app-launch harvesting.
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_STOPPED)
        withExtendedLifetime(profiler) {}
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
            message: .payload(TTIDMessage(attributes: mockRandomAttributes(), ttid: .mockWith())),
            from: core
        )
        flushQueue()

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
        _ = profiler.receive(message: .payload(OperationMessage(attributes: mockRandomAttributes(), operation: startOp)), from: core)
        flushQueue()

        dateProvider.now = dateProvider.now.addingTimeInterval(DatadogProfiler.Constants.minProfileDuration + 1)

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
        let profiler = customProfiler(dateProvider: dateProvider)
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
        let profiler = customProfiler(dateProvider: dateProvider)
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
            profilingSamplerProvider: profilingSamplerProvider(isContinuousProfiling: true),
            quotaChecker: quotaChecker()
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
        waitForProfileWrite(expectingWrite: false) {
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
            message: .payload(TTIDMessage(attributes: mockRandomAttributes(), ttid: .mockWith())),
            from: core
        )
        flushQueue()
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

    func testQuotaRejectionBeforeAppLaunchVital_stopsNativeProfilerImmediately() {
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
        dd_profiler_start_testing(100, false, 5.seconds.dd.toInt64Nanoseconds, 0)

        // When - quota rejects before TTID has been harvested.
        connectMessageReceiver(
            to: profiler,
            profilingSamplerProvider: profilingSamplerProvider,
            quotaChecker: quotaChecker
        )

        // Then - continuous, custom and app-launch profiling are disabled for the rejected session.
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_STOPPED)

        // When - TTID is processed.
        _ = profiler.receive(
            message: .payload(TTIDMessage(attributes: mockRandomAttributes(), ttid: .mockWith())),
            from: core
        )
        flushQueue()

        // Then - app launch does not restart profiling after quota rejection.
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_STOPPED)
        withExtendedLifetime(profiler) {}
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
        flushQueue()

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
            message: .payload(TTIDMessage(attributes: mockRandomAttributes(), ttid: .mockWith())),
            from: core
        )
        flushQueue()
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
        let runningProfilingContext = core.context.additionalContext(ofType: ProfilingContext.self)
        XCTAssertEqual(runningProfilingContext?.status, .running)
        XCTAssertNil(runningProfilingContext?.quotaReason)
        XCTAssertEqual(
            quotaChecker.receivedContexts.compactMap { $0.additionalContext(ofType: RUMCoreContext.self)?.sessionID },
            [firstSessionID.uuidString.lowercased(), secondSessionID.uuidString.lowercased()]
        )
        withExtendedLifetime(profiler) {}
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
            message: .payload(TTIDMessage(attributes: mockRandomAttributes(), ttid: .mockWith())),
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
        let noProfileMetric = try firstProfilingSessionMetric(from: telemetry)
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
        flushQueue()

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
            message: .payload(TTIDMessage(attributes: mockRandomAttributes(), ttid: .mockWith())),
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
        dateProvider: DateProvider = DateProviderMock(),
        quotaChecker: ProfilingQuotaChecking = ProfilingQuotaCheckerMock()
    ) -> DatadogProfiler {
        return DatadogProfiler(
            core: core,
            profilingSamplerProvider: profilingSamplerProvider,
            quotaChecker: quotaChecker,
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
        dateProvider: DateProvider = DateProviderMock(),
        quotaChecker: ProfilingQuotaChecking = ProfilingQuotaCheckerMock()
    ) -> DatadogProfiler {
        DatadogProfiler(
            core: core,
            profilingSamplerProvider: profilingSamplerProvider(isContinuousProfiling: false),
            quotaChecker: quotaChecker,
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
