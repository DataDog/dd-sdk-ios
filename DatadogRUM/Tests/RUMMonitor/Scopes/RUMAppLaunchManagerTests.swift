/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogInternal
@testable import DatadogRUM
@testable import TestUtilities

final class RUMAppLaunchManagerTests: XCTestCase {
    private var manager: RUMAppLaunchManager! // swiftlint:disable:this implicitly_unwrapped_optional
    private var appStateManager: AppStateManaging! // swiftlint:disable:this implicitly_unwrapped_optional
    private var mockParent: RUMContextProviderMock! // swiftlint:disable:this implicitly_unwrapped_optional
    private var mockDependencies: RUMScopeDependencies! // swiftlint:disable:this implicitly_unwrapped_optional
    private var mockWriter: FileWriterMock! // swiftlint:disable:this implicitly_unwrapped_optional
    private var mockContext: DatadogContext! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUp() {
        super.setUp()
        appStateManager = AppStateManagerMock()
        mockParent = RUMContextProviderMock()
        mockDependencies = .mockWith(appStateManager: appStateManager)
        mockWriter = FileWriterMock()
        mockContext = .mockWith(
            launchInfo: .mockWith(
                launchReason: .userLaunch,
                processLaunchDate: Date()
            )
        )

        manager = RUMAppLaunchManager(
            parent: mockParent,
            dependencies: mockDependencies
        )
    }

    override func tearDown() {
        manager = nil
        mockParent = nil
        mockDependencies = nil
        mockWriter = nil
        mockContext = nil
        super.tearDown()
    }

    // MARK: - Process Command Tests

    func testTTIDCommand_createsAppLaunchVitalEvent() throws {
        // Given
        let ttid = 2.0
        let command: RUMTimeToInitialDisplayCommand = .mockWith(
            time: mockContext.launchInfo.processLaunchDate.addingTimeInterval(ttid)
        )

        // When
        manager.process(command, context: mockContext, writer: mockWriter)

        // Then
        let vitalEvents = mockWriter.events(ofType: RUMVitalEvent.self)
        XCTAssertEqual(vitalEvents.count, 1)

        let event = try XCTUnwrap(vitalEvents.first)
        XCTAssertNil(event.view)

        guard case let .appLaunchProperties(value: vital) = event.vital else {
            return XCTFail("Expected event.vital to be .appLaunchProperties, but got \(event.vital)")
        }
        XCTAssertEqual(vital.type, "app_launch")
        XCTAssertEqual(vital.appLaunchMetric, .ttid)
        XCTAssertEqual(vital.name, "time_to_initial_display")
        XCTAssertNotNil(vital.id)
        XCTAssertEqual(vital.isPrewarmed, false)
        XCTAssertEqual(vital.duration, Double(ttid.toInt64Nanoseconds))
        XCTAssertEqual(vital.startupType, .coldStart)

        // Common properties
        XCTAssertNil(event.account)
        XCTAssertNil(event.buildId)
        XCTAssertNotNil(event.buildVersion)
        XCTAssertNil(event.ciTest)
        XCTAssertNotNil(event.connectivity)
        XCTAssertNil(event.container)
        XCTAssertNotNil(event.context)
        XCTAssertNotNil(event.ddtags)
        XCTAssertNotNil(event.device)
        XCTAssertNil(event.display)
        XCTAssertNotNil(event.os)
        XCTAssertNotNil(event.service)
        XCTAssertEqual(event.source, .ios)
        XCTAssertNil(event.synthetics)
        XCTAssertNil(event.usr)
        XCTAssertNotNil(event.version)
    }

    func testTTIDCommand_createsAppLaunchVitalEventForPreWarmingLaunches() throws {
        // Given
        let processLaunchDate = Date()
        let runtimeLoadDate = processLaunchDate.addingTimeInterval(1)
        let ttid = 3.0
        mockContext = .mockWith(
            launchInfo: .mockWith(
                launchReason: .prewarming,
                processLaunchDate: processLaunchDate,
                runtimeLoadDate: runtimeLoadDate
            )
        )
        let command: RUMTimeToInitialDisplayCommand = .mockWith(time: runtimeLoadDate.addingTimeInterval(ttid))

        // When
        manager.process(command, context: mockContext, writer: mockWriter)

        // Then
        let vitalEvents = mockWriter.events(ofType: RUMVitalEvent.self)
        XCTAssertEqual(vitalEvents.count, 1)

        let event = try XCTUnwrap(vitalEvents.first)
        XCTAssertNil(event.view)

        guard case let .appLaunchProperties(value: vital) = event.vital else {
            return XCTFail("Expected event.vital to be .appLaunchProperties, but got \(event.vital)")
        }
        XCTAssertEqual(vital.type, "app_launch")
        XCTAssertEqual(vital.appLaunchMetric, .ttid)
        XCTAssertEqual(vital.name, "time_to_initial_display")
        XCTAssertEqual(vital.isPrewarmed, true)
        XCTAssertEqual(vital.duration, Double(ttid.toInt64Nanoseconds))
        XCTAssertEqual(vital.startupType, .coldStart)
    }

    func testTTIDCommand_createsAppLaunchVitalEventForWarmStart() throws {
        // Given
        let appStateInfo: AppStateInfo = .mockAny()
        (appStateManager as? AppStateManagerMock)?.previousAppStateInfo = appStateInfo
        (appStateManager as? AppStateManagerMock)?.currentAppStateInfo = appStateInfo // similar AppStateInfo with the previous AppStateInfo
        let ttid = 1.0
        let command: RUMTimeToInitialDisplayCommand = .mockWith(time: mockContext.launchInfo.processLaunchDate.addingTimeInterval(ttid))

        // When
        manager.process(command, context: mockContext, writer: mockWriter)

        // Then
        let vitalEvents = mockWriter.events(ofType: RUMVitalEvent.self)
        XCTAssertEqual(vitalEvents.count, 1)

        let event = try XCTUnwrap(vitalEvents.first)
        XCTAssertNil(event.view)

        guard case let .appLaunchProperties(value: vital) = event.vital else {
            return XCTFail("Expected event.vital to be .appLaunchProperties, but got \(event.vital)")
        }
        XCTAssertEqual(vital.type, "app_launch")
        XCTAssertEqual(vital.appLaunchMetric, .ttid)
        XCTAssertEqual(vital.name, "time_to_initial_display")
        XCTAssertEqual(vital.isPrewarmed, false)
        XCTAssertEqual(vital.duration, Double(ttid.toInt64Nanoseconds))
        XCTAssertEqual(vital.startupType, .warmStart)
    }

    func testTTIDCommand_isCapturedOnlyOnce() throws {
        // Given
        let firstCommand: RUMTimeToInitialDisplayCommand = .mockWith(
            time: mockContext.launchInfo.processLaunchDate.addingTimeInterval(1)
        )
        let secondCommand: RUMTimeToInitialDisplayCommand = .mockWith(
            time: mockContext.launchInfo.processLaunchDate.addingTimeInterval(2)
        )
        let thirdCommand: RUMTimeToInitialDisplayCommand = .mockWith(
            time: mockContext.launchInfo.processLaunchDate.addingTimeInterval(3)
        )

        // When
        manager.process(firstCommand, context: mockContext, writer: mockWriter)
        manager.process(secondCommand, context: mockContext, writer: mockWriter)
        manager.process(thirdCommand, context: mockContext, writer: mockWriter)

        // Then
        let vitalEvents = mockWriter.events(ofType: RUMVitalEvent.self)
        XCTAssertEqual(vitalEvents.count, 1)
    }

    func testTTIDCommand_isIgnoredWhenTheDurationIsTooBig() throws {
        // Given
        let command: RUMTimeToInitialDisplayCommand = .mockWith(
            time: mockContext.launchInfo.processLaunchDate.addingTimeInterval(RUMAppLaunchManager.Constants.maxTTIDDuration + 1)
        )

        // When
        manager.process(command, context: mockContext, writer: mockWriter)

        // Then
        let vitalEvents = mockWriter.events(ofType: RUMVitalEvent.self)
        XCTAssertEqual(vitalEvents.count, 0)
    }

    func testTTIDCommand_isIgnoredWhenTheAppIsLaunchedInBackground() throws {
        // Given
        mockContext = .mockWith(launchInfo: .mockWith(launchReason: .backgroundLaunch, processLaunchDate: Date()))
        let command: RUMTimeToInitialDisplayCommand = .mockWith(
            time: mockContext.launchInfo.processLaunchDate.addingTimeInterval(1)
        )

        // When
        manager.process(command, context: mockContext, writer: mockWriter)

        // Then
        let vitalEvents = mockWriter.events(ofType: RUMVitalEvent.self)
        XCTAssertEqual(vitalEvents.count, 0)
    }

    func testTTIDCommand_isIgnoredWhenTheAppHasUncertainLaunchReason() throws {
        // Given
        mockContext = .mockWith(launchInfo: .mockWith(launchReason: .uncertain, processLaunchDate: Date()))
        let command: RUMTimeToInitialDisplayCommand = .mockWith(
            time: mockContext.launchInfo.processLaunchDate.addingTimeInterval(1)
        )

        // When
        manager.process(command, context: mockContext, writer: mockWriter)

        // Then
        let vitalEvents = mockWriter.events(ofType: RUMVitalEvent.self)
        XCTAssertEqual(vitalEvents.count, 0)
    }
}
