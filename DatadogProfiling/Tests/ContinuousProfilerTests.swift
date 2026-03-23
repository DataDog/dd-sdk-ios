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

final class ContinuousProfilerTests: XCTestCase {
    private var core: PassthroughCoreMock!  // swiftlint:disable:this implicitly_unwrapped_optional
    private var notificationCenter: MockNotificationCenter! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUp() {
        super.setUp()
        core = PassthroughCoreMock(context: .mockWith(applicationStateHistory: .mockAppInForeground()))
        notificationCenter = MockNotificationCenter()
        dd_profiler_stop()
        dd_profiler_destroy()
    }

    override func tearDown() {
        dd_profiler_stop()
        dd_profiler_destroy()
        dd_delete_profiling_defaults()
        notificationCenter = nil
        core = nil
        super.tearDown()
    }

    // MARK: - receive(message:from:)

    func testReceiveRUMEvents() {
        // Given
        let profiler = continuousProfiler()
        let startFeatureOperation: Vital = .mockWith(name: "operation")
        let endOperation: Vital = .mockWith(id: .mockRandom(), name: "operation", stepType: .end)
        let launchVital: Vital = .mockWith(stepType: nil)

        // When
        var result = profiler.receive(
            message: .payload(OperationMessage(attributes: mockRandomAttributes(), operation: startFeatureOperation)),
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

    func testReceiveApplicationLaunchVital_clearsOngoingRUMVitals() {
        // Given
        let profiler = continuousProfiler()
        let startFeatureOperation: Vital = .mockWith(name: "operation")
        let launchVital: Vital = .mockWith(stepType: nil)

        XCTAssertEqual(dd_profiler_start(), 1)

        // Accumulate a RUM operation
        _ = profiler.receive(message: .payload(OperationMessage(attributes: mockRandomAttributes(), operation: startFeatureOperation)), from: core)

        // When
        XCTAssertFalse(profiler.receive(message: .payload(TTIDMessage(attributes: mockRandomAttributes(), ttid: launchVital)), from: core))

        // Then
        if let metadata = core.metadata.first as? ProfileAttachments,
           let rumEventsData = metadata.rumEvents,
           let rumEvents = try? JSONDecoder().decode(RUMEvents.self, from: rumEventsData) {
            XCTAssertTrue(rumEvents.vitals.isEmpty, "State should be cleared on app launch since AppLaunchProfiler handled them")
        }
    }

    func testReceiveLongTask() {
        // Given
        let profiler = continuousProfiler()
        let longTask = DurationEvent(id: .mockRandom(), start: 0, duration: 100)

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
        let hang = DurationEvent(id: .mockRandom(), start: 0, duration: 500)

        // When
        let result = profiler.receive(
            message: .payload(AppHangMessage(attributes: mockRandomAttributes(), hang: hang)),
            from: core
        )

        // Then
        XCTAssertTrue(result, "App hangs should be consumed by continuous profiler after app launch")
    }

    // MARK: - Notifications

    func testApplicationDidEnterBackground_stopsProfiler() {
        // Given
        let dateProvider = DateProviderMock()
        let profiler = continuousProfiler(dateProvider: dateProvider)
        XCTAssertEqual(dd_profiler_start(), 1)
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_RUNNING)

        // When
        // Transition context to background while retaining foreground history
        core.context = .mockWith(applicationStateHistory: .mockWith(
            initialState: .active,
            date: dateProvider.now.addingTimeInterval(-1),
            transitions: [(state: .background, date: dateProvider.now)]
        ))
        notificationCenter.post(name: ApplicationNotifications.didEnterBackground, object: nil)

        // Then
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_STOPPED)
        withExtendedLifetime(profiler) {}
    }

    func testApplicationDidEnterBackground_doesNothing_whenAppWasNeverInForeground() {
        // Given
        let profiler = continuousProfiler()
        XCTAssertEqual(dd_profiler_start(), 1)

        // App was only ever in background (e.g. UIScene based app)
        core.context = .mockWith(applicationStateHistory: .mockAppInBackground())

        // When
        notificationCenter.post(name: ApplicationNotifications.didEnterBackground, object: nil)

        // Then
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_RUNNING)
        XCTAssertTrue(core.metadata.isEmpty)
        withExtendedLifetime(profiler) {}
    }

    func testApplicationDidEnterBackground_includesAccumulatedVitalsInProfile() throws {
        // Given
        let profiler = continuousProfiler()
        XCTAssertEqual(dd_profiler_start(), 1)

        let startFeatureOperation = Vital.mockWith(id: .mockRandom(), name: "operation")
        let endOperation = Vital.mockWith(id: .mockRandom(), name: "operation", operationKey: startFeatureOperation.operationKey, stepType: .end)
        _ = profiler.receive(message: .payload(OperationMessage(attributes: mockRandomAttributes(), operation: startFeatureOperation)), from: core)
        _ = profiler.receive(message: .payload(OperationMessage(attributes: mockRandomAttributes(), operation: endOperation)), from: core)

        // When
        notificationCenter.post(name: ApplicationNotifications.didEnterBackground, object: nil)

        // Then
        let metadata = try XCTUnwrap(core.metadata.first as? ProfileAttachments)
        let rumEvents = try XCTUnwrap(JSONDecoder().decode(RUMEvents.self, from: XCTUnwrap(metadata.rumEvents)))
        let vitalIDs = rumEvents.vitals.map(\.id)
        XCTAssertTrue(vitalIDs.contains(startFeatureOperation.id))
        XCTAssertTrue(vitalIDs.contains(endOperation.id))
        withExtendedLifetime(profiler) {}
    }

    func testApplicationDidEnterBackground_includesLongTasksInProfile() throws {
        // Given
        let profiler = continuousProfiler()
        XCTAssertEqual(dd_profiler_start(), 1)

        let longTask = DurationEvent(id: .mockRandom(), start: 0, duration: 100)
        _ = profiler.receive(message: .payload(LongTaskMessage(attributes: mockRandomAttributes(), longTask: longTask)), from: core)

        // When
        notificationCenter.post(name: ApplicationNotifications.didEnterBackground, object: nil)

        // Then
        let metadata = try XCTUnwrap(core.metadata.first as? ProfileAttachments)
        let rumEvents = try XCTUnwrap(JSONDecoder().decode(RUMEvents.self, from: XCTUnwrap(metadata.rumEvents)))
        XCTAssertEqual(rumEvents.longTasks?.map(\.id), [longTask.id])
        withExtendedLifetime(profiler) {}
    }

    func testApplicationDidEnterBackground_includesAppHangsInProfile() throws {
        // Given
        let profiler = continuousProfiler()
        XCTAssertEqual(dd_profiler_start(), 1)

        let hang = DurationEvent(id: .mockRandom(), start: 0, duration: 500)
        XCTAssertTrue(profiler.receive(message: .payload(AppHangMessage(attributes: mockRandomAttributes(), hang: hang)), from: core))

        // When
        notificationCenter.post(name: ApplicationNotifications.didEnterBackground, object: nil)

        // Then
        let metadata = try XCTUnwrap(core.metadata.first as? ProfileAttachments)
        let rumEvents = try XCTUnwrap(JSONDecoder().decode(RUMEvents.self, from: XCTUnwrap(metadata.rumEvents)))
        XCTAssertEqual(rumEvents.hangs?.map(\.id), [hang.id])
        withExtendedLifetime(profiler) {}
    }

    // MARK: - canWriteProfile

    func testDoesNotWriteProfile_whenNoEventsAccumulated() {
        // Given
        let profiler = continuousProfiler()
        XCTAssertEqual(dd_profiler_start(), 1)

        // When
        notificationCenter.post(name: ApplicationNotifications.didEnterBackground, object: nil)

        // Then
        XCTAssertTrue(core.metadata.isEmpty)
        withExtendedLifetime(profiler) {}
    }

    func testWritesProfile_whenRUMOperationsAccumulated() {
        // Given
        let profiler = continuousProfiler()
        XCTAssertEqual(dd_profiler_start(), 1)

        let startFeatureOperation = Vital.mockWith(name: "operation")
        let endOperation = Vital.mockWith(name: "operation", operationKey: startFeatureOperation.operationKey, stepType: .end)
        _ = profiler.receive(message: .payload(OperationMessage(attributes: mockRandomAttributes(), operation: startFeatureOperation)), from: core)
        _ = profiler.receive(message: .payload(OperationMessage(attributes: mockRandomAttributes(), operation: endOperation)), from: core)

        // When
        notificationCenter.post(name: ApplicationNotifications.didEnterBackground, object: nil)

        // Then
        XCTAssertFalse(core.metadata.isEmpty)
        withExtendedLifetime(profiler) {}
    }

    func testWritesProfile_whenLongTasksAccumulated() {
        // Given
        let profiler = continuousProfiler()
        let longTask = DurationEvent(id: .mockRandom(), start: 0, duration: 100)
        XCTAssertEqual(dd_profiler_start(), 1)

        _ = profiler.receive(message: .payload(LongTaskMessage(attributes: mockRandomAttributes(), longTask: longTask)), from: core)

        // When
        notificationCenter.post(name: ApplicationNotifications.didEnterBackground, object: nil)

        // Then
        XCTAssertFalse(core.metadata.isEmpty)
        withExtendedLifetime(profiler) {}
    }

    func testWritesProfile_whenAppHangsAccumulated() {
        // Given
        let profiler = continuousProfiler()
        let hang = DurationEvent(id: .mockRandom(), start: 0, duration: 500)
        XCTAssertEqual(dd_profiler_start(), 1)

        _ = profiler.receive(message: .payload(AppHangMessage(attributes: mockRandomAttributes(), hang: hang)), from: core)

        // When
        notificationCenter.post(name: ApplicationNotifications.didEnterBackground, object: nil)

        // Then
        XCTAssertFalse(core.metadata.isEmpty)
        withExtendedLifetime(profiler) {}
    }

    func testApplicationWillEnterForeground_restartsProfilerAfterBackground() {
        // Given
        XCTAssertEqual(dd_profiler_start(), 1)
        dd_profiler_stop()
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_STOPPED)

        let profiler = continuousProfiler()

        // When
        notificationCenter.post(name: ApplicationNotifications.willEnterForeground, object: nil)

        // Then
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_RUNNING)
        withExtendedLifetime(profiler) {}
    }

    private func continuousProfiler(
        profilingConditions: ProfilingConditions = ProfilingConditions(),
        profilingInterval: TimeInterval = .infinity,
        dateProvider: DateProvider = DateProviderMock()
    ) -> ContinuousProfiler {
        ContinuousProfiler(
            core: core,
            isContinuousProfiling: true,
            profilingConditions: profilingConditions,
            profilingInterval: profilingInterval,
            notificationCenter: notificationCenter,
            dateProvider: dateProvider
        )
    }

    private func customProfiler(
        profilingConditions: ProfilingConditions = ProfilingConditions(),
        profilingInterval: TimeInterval = .infinity,
        dateProvider: DateProvider = DateProviderMock()
    ) -> ContinuousProfiler {
        ContinuousProfiler(
            core: core,
            isContinuousProfiling: false,
            profilingConditions: profilingConditions,
            profilingInterval: profilingInterval,
            notificationCenter: notificationCenter,
            dateProvider: dateProvider
        )
    }
}

// MARK: - Custom Profiling

extension ContinuousProfilerTests {
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
        XCTAssertEqual(dd_profiler_start(), 1)
        dd_profiler_stop()
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_STOPPED)

        let profiler = customProfiler()

        // When
        _ = profiler.receive(message: .payload(OperationMessage(attributes: mockRandomAttributes(), operation: .mockWith(stepType: .start))), from: core)

        // Then
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_RUNNING, "Custom profiler should start on first RUM operation")
        withExtendedLifetime(profiler) {}
    }

    func testCustomProfiler_doesNotRestartRunningProfilerOnOperation() {
        // Given
        XCTAssertEqual(dd_profiler_start(), 1)
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_RUNNING)

        let profiler = customProfiler()

        // When
        _ = profiler.receive(message: .payload(OperationMessage(attributes: mockRandomAttributes(), operation: .mockWith(stepType: .start))), from: core)

        // Then - profiler stays running without error
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_RUNNING)
        withExtendedLifetime(profiler) {}
    }

    func testCustomProfiler_beforeReceivingAppLaunchVital() {
        // Given
        let profiler = customProfiler()
        let longTask = DurationEvent(id: .mockRandom(), start: 0, duration: 100)
        let hang = DurationEvent(id: .mockRandom(), start: 0, duration: 500)
        let operation: Vital = .mockWith(stepType: .start)

        // Then
        XCTAssertTrue(profiler.receive(message: .payload(LongTaskMessage(attributes: mockRandomAttributes(), longTask: longTask)), from: core))
        XCTAssertTrue(profiler.receive(message: .payload(AppHangMessage(attributes: mockRandomAttributes(), hang: hang)), from: core))
        XCTAssertFalse(profiler.receive(message: .payload(OperationMessage(attributes: mockRandomAttributes(), operation: operation)), from: core))
        withExtendedLifetime(profiler) {}
    }

    func testCustomProfiler_doesNotWriteProfile_whenNoEventsAccumulated() {
        // Given
        let profiler = customProfiler()
        XCTAssertEqual(dd_profiler_start(), 1)

        // When - background notification with no accumulated events
        notificationCenter.post(name: ApplicationNotifications.didEnterBackground, object: nil)

        // Then
        XCTAssertTrue(core.metadata.isEmpty)
        withExtendedLifetime(profiler) {}
    }

    func testCustomProfiler_writesProfile_whenRUMOperationsAccumulated() {
        // Given
        let profiler = customProfiler()
        XCTAssertEqual(dd_profiler_start(), 1)

        let startOp: Vital = .mockAny()
        let endOp: Vital = .mockWith(name: startOp.name, operationKey: startOp.operationKey, stepType: .end)
        _ = profiler.receive(message: .payload(OperationMessage(attributes: mockRandomAttributes(), operation: startOp)), from: core)
        _ = profiler.receive(message: .payload(OperationMessage(attributes: mockRandomAttributes(), operation: endOp)), from: core)

        // When
        notificationCenter.post(name: ApplicationNotifications.didEnterBackground, object: nil)

        // Then
        XCTAssertFalse(core.metadata.isEmpty)
        withExtendedLifetime(profiler) {}
    }

    func testCustomProfiler_keepsProfilerRunning_whenOperationsIsRecent() {
        // Given
        let dateProvider = DateProviderMock(now: Date())
        let profiler = customProfiler(dateProvider: dateProvider)
        XCTAssertEqual(dd_profiler_start(), 1)

        let startOp: Vital = .mockWith(date: dateProvider.now.addingTimeInterval(1))
        _ = profiler.receive(message: .payload(OperationMessage(attributes: mockRandomAttributes(), operation: startOp)), from: core)

        // When - app launch vital received while operation is still recent
        let launchVital: Vital = .mockWith()
        _ = profiler.receive(message: .payload(TTIDMessage(attributes: mockRandomAttributes(), ttid: launchVital)), from: core)

        // Then - profiler keeps running since operation is within cutoff window
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_RUNNING)
        withExtendedLifetime(profiler) {}
    }

    func testCustomProfiler_stopsProfiler_whenOperationsExpired() {
        // Given
        let dateProvider = DateProviderMock(now: Date())
        let profiler = customProfiler(dateProvider: dateProvider)
        XCTAssertEqual(dd_profiler_start(), 1)

        let startOp: Vital = .mockWith(stepType: .start)
        _ = profiler.receive(message: .payload(OperationMessage(attributes: mockRandomAttributes(), operation: startOp)), from: core)

        // Advance past customProfilingCutOffTime
        dateProvider.now = dateProvider.now.addingTimeInterval(ContinuousProfiler.Constants.customProfilingCutOffTime + 1)

        // When - app launch vital received after cutoff
        let launchVital = Vital.mockWith()
        _ = profiler.receive(message: .payload(TTIDMessage(attributes: mockRandomAttributes(), ttid: launchVital)), from: core)

        // Then - profiler stops since no recent operations remain
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_STOPPED)
        withExtendedLifetime(profiler) {}
    }

    func testCustomProfiler_applicationDidEnterBackground_stopsProfilerAndSendsProfile() {
        // Given
        let profiler = customProfiler()
        XCTAssertEqual(dd_profiler_start(), 1)
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_RUNNING)

        // When
        notificationCenter.post(name: ApplicationNotifications.didEnterBackground, object: nil)

        // Then
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_STOPPED)
        withExtendedLifetime(profiler) {}
    }

    func testCustomProfiler_applicationDidEnterBackground_includesLongTasksInProfile() throws {
        // Given
        let profiler = customProfiler()
        XCTAssertEqual(dd_profiler_start(), 1)

        let longTask = DurationEvent(id: .mockRandom(), start: 0, duration: 100)
        _ = profiler.receive(message: .payload(LongTaskMessage(attributes: mockRandomAttributes(), longTask: longTask)), from: core)

        // When
        notificationCenter.post(name: ApplicationNotifications.didEnterBackground, object: nil)

        // Then
        let metadata = try XCTUnwrap(core.metadata.first as? ProfileAttachments)
        let rumEvents = try XCTUnwrap(JSONDecoder().decode(RUMEvents.self, from: XCTUnwrap(metadata.rumEvents)))
        XCTAssertEqual(rumEvents.longTasks?.map(\.id), [longTask.id])
        withExtendedLifetime(profiler) {}
    }

    func testCustomProfiler_applicationDidEnterBackground_includesAppHangsInProfile() throws {
        // Given
        let profiler = customProfiler()
        XCTAssertEqual(dd_profiler_start(), 1)

        let hang = DurationEvent(id: .mockRandom(), start: 0, duration: 500)
        _ = profiler.receive(message: .payload(AppHangMessage(attributes: mockRandomAttributes(), hang: hang)), from: core)

        // When
        notificationCenter.post(name: ApplicationNotifications.didEnterBackground, object: nil)

        // Then
        let metadata = try XCTUnwrap(core.metadata.first as? ProfileAttachments)
        let rumEvents = try XCTUnwrap(JSONDecoder().decode(RUMEvents.self, from: XCTUnwrap(metadata.rumEvents)))
        XCTAssertEqual(rumEvents.hangs?.map(\.id), [hang.id])
        withExtendedLifetime(profiler) {}
    }

    func testCustomProfiler_applicationWillEnterForeground_doesNotRestartProfiler() {
        // Given
        XCTAssertEqual(dd_profiler_start(), 1)
        dd_profiler_stop()
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_STOPPED)

        let profiler = customProfiler()

        // When
        notificationCenter.post(name: ApplicationNotifications.willEnterForeground, object: nil)

        // Then - custom profiler does not restart without recent operations (unlike continuous)
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_STOPPED)
        withExtendedLifetime(profiler) {}
    }
}
#endif // !os(watchOS)
