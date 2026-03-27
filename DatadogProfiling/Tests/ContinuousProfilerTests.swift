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
        core = PassthroughCoreMock()
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
        let startOperation: Vital = .mockWith(name: "operation", type: .rumOperation(.start))
        let endOperation: Vital = .mockWith(id: .mockRandom(), name: "operation", type: .rumOperation(.end))
        let launchVital: Vital = .mockWith(type: .applicationLaunch)

        // When
        var result = profiler.receive(
            message: .payload(RUMMessage(context: mockRandomAttributes(), event: startOperation)),
            from: core
        )

        // Then
        XCTAssertFalse(result, "Continuous profiler and AppLaunch profiler consume RUM operations")

        // When
        result = profiler.receive(
            message: .payload(RUMMessage(context: mockRandomAttributes(), event: endOperation)),
            from: core
        )

        // Then
        XCTAssertFalse(result, "Continuous profiler and AppLaunch profiler consume RUM operations")

        // When
        result = profiler.receive(
            message: .payload(RUMMessage(context: mockRandomAttributes(), event: launchVital)),
            from: core
        )

        // Then
        XCTAssertFalse(result, "Continuous profiler and AppLaunch profiler consume app launch vitals")
    }

    func testReceiveApplicationLaunchVital_clearsOngoingRUMVitals() {
        // Given
        let profiler = continuousProfiler()
        let startOperation: Vital = .mockWith(name: "operation", type: .rumOperation(.start))
        let launchVital: Vital = .mockWith(type: .applicationLaunch)

        XCTAssertEqual(dd_profiler_start(), 1)

        // Accumulate a RUM operation
        _ = profiler.receive(message: .payload(RUMMessage(context: mockRandomAttributes(), event: startOperation)), from: core)

        // When
        XCTAssertFalse(profiler.receive(message: .payload(RUMMessage(context: mockRandomAttributes(), event: launchVital)), from: core))

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
        let longTask = DurationEvent<RUMLongTaskEvent>(id: .mockRandom(), start: 0, duration: 100)

        // When
        let result = profiler.receive(
            message: .payload(RUMMessage(context: mockRandomAttributes(), event: longTask)),
            from: core
        )

        // Then
        XCTAssertTrue(result, "Long tasks should be consumed by continuous profiler")
    }

    func testReceiveAppHang() {
        // Given
        let profiler = continuousProfiler()
        let hang = DurationEvent<RUMErrorEvent>(id: .mockRandom(), start: 0, duration: 500)

        // When
        let result = profiler.receive(
            message: .payload(RUMMessage(context: mockRandomAttributes(), event: hang)),
            from: core
        )

        // Then
        XCTAssertTrue(result, "App hangs should be consumed by continuous profiler")
    }

    // MARK: - Notifications

    func testApplicationDidEnterBackground_stopsProfilerAndSendsProfile() {
        // Given
        let profiler = continuousProfiler()
        XCTAssertEqual(dd_profiler_start(), 1)
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_RUNNING)

        // When
        notificationCenter.post(name: ApplicationNotifications.didEnterBackground, object: nil)

        // Then — profiler should be stopped after backgrounding
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_STOPPED)
        withExtendedLifetime(profiler) {}
    }

    func testApplicationDidEnterBackground_includesAccumulatedVitalsInProfile() throws {
        // Given
        let profiler = continuousProfiler()
        XCTAssertEqual(dd_profiler_start(), 1)

        let startOperation = Vital.mockWith(id: .mockRandom(), name: "operation", type: .rumOperation(.start))
        let endOperation = Vital.mockWith(id: .mockRandom(), name: "operation", operationKey: startOperation.operationKey, type: .rumOperation(.end))
        _ = profiler.receive(message: .payload(RUMMessage(context: mockRandomAttributes(), event: startOperation)), from: core)
        _ = profiler.receive(message: .payload(RUMMessage(context: mockRandomAttributes(), event: endOperation)), from: core)

        // When
        notificationCenter.post(name: ApplicationNotifications.didEnterBackground, object: nil)

        // Then
        let metadata = try XCTUnwrap(core.metadata.first as? ProfileAttachments)
        let rumEvents = try XCTUnwrap(JSONDecoder().decode(RUMEvents.self, from: XCTUnwrap(metadata.rumEvents)))
        let vitalIDs = rumEvents.vitals.map(\.id)
        XCTAssertTrue(vitalIDs.contains(startOperation.id))
        XCTAssertTrue(vitalIDs.contains(endOperation.id))
        withExtendedLifetime(profiler) {}
    }

    func testApplicationDidEnterBackground_includesLongTasksInProfile() throws {
        // Given
        let profiler = continuousProfiler()
        XCTAssertEqual(dd_profiler_start(), 1)

        let longTask = DurationEvent<RUMLongTaskEvent>(id: .mockRandom(), start: 0, duration: 100)
        _ = profiler.receive(message: .payload(RUMMessage(context: mockRandomAttributes(), event: longTask)), from: core)

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

        let hang = DurationEvent<RUMErrorEvent>(id: .mockRandom(), start: 0, duration: 500)
        XCTAssertTrue(profiler.receive(message: .payload(RUMMessage(context: mockRandomAttributes(), event: hang)), from: core))

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

        let startOperation = Vital.mockWith(name: "operation", type: .rumOperation(.start))
        let endOperation = Vital.mockWith(name: "operation", operationKey: startOperation.operationKey, type: .rumOperation(.end))
        _ = profiler.receive(message: .payload(RUMMessage(context: mockRandomAttributes(), event: startOperation)), from: core)
        _ = profiler.receive(message: .payload(RUMMessage(context: mockRandomAttributes(), event: endOperation)), from: core)

        // When
        notificationCenter.post(name: ApplicationNotifications.didEnterBackground, object: nil)

        // Then
        XCTAssertFalse(core.metadata.isEmpty)
        withExtendedLifetime(profiler) {}
    }

    func testWritesProfile_whenLongTasksAccumulated() {
        // Given
        let profiler = continuousProfiler()
        let longTask = DurationEvent<RUMLongTaskEvent>(id: .mockRandom(), start: 0, duration: 100)
        XCTAssertEqual(dd_profiler_start(), 1)

        _ = profiler.receive(message: .payload(RUMMessage(context: mockRandomAttributes(), event: longTask)), from: core)

        // When
        notificationCenter.post(name: ApplicationNotifications.didEnterBackground, object: nil)

        // Then
        XCTAssertFalse(core.metadata.isEmpty)
        withExtendedLifetime(profiler) {}
    }

    func testWritesProfile_whenAppHangsAccumulated() {
        // Given
        let profiler = continuousProfiler()
        let hang = DurationEvent<RUMErrorEvent>(id: .mockRandom(), start: 0, duration: 500)
        XCTAssertEqual(dd_profiler_start(), 1)

        _ = profiler.receive(message: .payload(RUMMessage(context: mockRandomAttributes(), event: hang)), from: core)

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
        profilingConditions: ProfilingConditions = ProfilingConditions(blockers: []),
        profilingInterval: TimeInterval = .infinity
    ) -> ContinuousProfiler {
        ContinuousProfiler(
            core: core,
            profilingConditions: profilingConditions,
            profilingInterval: profilingInterval,
            notificationCenter: notificationCenter
        )
    }
}

#endif // !os(watchOS)
