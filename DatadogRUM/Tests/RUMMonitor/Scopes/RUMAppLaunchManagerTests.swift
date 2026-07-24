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
            dependencies: mockDependencies,
            telemetryController: .init()
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

    // MARK: - TTID

    func testTTIDCommand_createsAppLaunchVitalEvent() throws {
        // Given
        let ttid = 2.0
        let activeView: RUMViewScope = .mockWith(path: "ViewPath", name: "ViewName")
        let quotaReason: DDProfiling.QuotaReason = .mockRandom()
        let command: RUMTimeToInitialDisplayCommand = .mockWith(
            time: mockContext.launchInfo.processLaunchDate.addingTimeInterval(ttid)
        )

        // When
        mockContext.set(additionalContext: ProfilingContext(status: .running, quotaReason: quotaReason))
        manager.process(command, context: mockContext, writer: mockWriter, activeView: activeView)

        // Then
        let vitalEvents = mockWriter.events(ofType: RUMVitalAppLaunchEvent.self)
        XCTAssertEqual(vitalEvents.count, 1)

        let event = try XCTUnwrap(vitalEvents.first)
        XCTAssertNotNil(event.view)

        XCTAssertEqual(event.view.name, "ViewName")
        XCTAssertEqual(event.view.url, "ViewPath")
        XCTAssertEqual(event.vital.type, "app_launch")
        XCTAssertEqual(event.vital.appLaunchMetric, .ttid)
        XCTAssertEqual(event.vital.name, "time_to_initial_display")
        XCTAssertNotNil(event.vital.id)
        XCTAssertEqual(event.vital.isPrewarmed, false)
        XCTAssertEqual(event.vital.duration, Double(ttid.dd.toInt64Nanoseconds))
        XCTAssertEqual(event.vital.startupType, .coldStart)

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

        // Profiling Status
        XCTAssertEqual(event.dd.profiling?.status, .running)
        XCTAssertEqual(event.dd.profiling?.quotaReason, quotaReason)
    }

    func testTTIDCommand_appliesServerTimeOffsetToAppLaunchEventAndProfilerMessage() throws {
        // Given
        let featureScope = FeatureScopeMock()
        mockDependencies = .mockWith(featureScope: featureScope, appStateManager: appStateManager)
        manager = RUMAppLaunchManager(
            parent: mockParent,
            dependencies: mockDependencies,
            telemetryController: .init()
        )
        mockContext.serverTimeOffset = 2
        let command: RUMTimeToInitialDisplayCommand = .mockWith(
            time: mockContext.launchInfo.processLaunchDate.addingTimeInterval(1)
        )

        // When
        manager.process(command, context: mockContext, writer: mockWriter)

        // Then
        let event = try XCTUnwrap(mockWriter.events(ofType: RUMVitalAppLaunchEvent.self).first)
        XCTAssertEqual(
            event.date,
            mockContext.launchInfo.processLaunchDate
                .addingTimeInterval(mockContext.serverTimeOffset)
                .timeIntervalSince1970
                .dd
                .toInt64Milliseconds
        )

        let message = try XCTUnwrap(
            featureScope.messagesSent().compactMap { $0.asPayload as? TTIDMessage }.first
        )
        XCTAssertEqual(message.ttid.serverTimeOffset, mockContext.serverTimeOffset)
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
        let vitalEvents = mockWriter.events(ofType: RUMVitalAppLaunchEvent.self)
        XCTAssertEqual(vitalEvents.count, 1)

        let event = try XCTUnwrap(vitalEvents.first)
        XCTAssertNotNil(event.view)

        XCTAssertEqual(event.vital.type, "app_launch")
        XCTAssertEqual(event.vital.appLaunchMetric, .ttid)
        XCTAssertEqual(event.vital.name, "time_to_initial_display")
        XCTAssertEqual(event.vital.isPrewarmed, true)
        XCTAssertEqual(event.vital.duration, Double(ttid.dd.toInt64Nanoseconds))
        XCTAssertEqual(event.vital.startupType, .coldStart)
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
        let vitalEvents = mockWriter.events(ofType: RUMVitalAppLaunchEvent.self)
        XCTAssertEqual(vitalEvents.count, 1)

        let event = try XCTUnwrap(vitalEvents.first)
        XCTAssertNotNil(event.view)

        XCTAssertEqual(event.vital.type, "app_launch")
        XCTAssertEqual(event.vital.appLaunchMetric, .ttid)
        XCTAssertEqual(event.vital.name, "time_to_initial_display")
        XCTAssertEqual(event.vital.isPrewarmed, false)
        XCTAssertEqual(event.vital.duration, Double(ttid.dd.toInt64Nanoseconds))
        XCTAssertEqual(event.vital.startupType, .warmStart)
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
        let vitalEvents = mockWriter.events(ofType: RUMVitalAppLaunchEvent.self)
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
        let vitalEvents = mockWriter.events(ofType: RUMVitalAppLaunchEvent.self)
        XCTAssertEqual(vitalEvents.count, 0)
    }

    func testTTIDCommand_isIgnoredWhenTheDurationBetweenProcessLaunchAndMainIsTooBig() throws {
        // Given
        let processLaunchDate = Date()
        /// It is possible to observe large gaps between process launch and SDK initialization in sessions that are not prewarmed.
        let runtimeLoadDate = processLaunchDate.addingTimeInterval(RUMAppLaunchManager.Constants.maxTTIDDuration)
        mockContext = .mockWith(
            launchInfo: .mockWith(
                launchReason: .userLaunch,
                processLaunchDate: processLaunchDate,
                runtimeLoadDate: runtimeLoadDate
            )
        )
        let command: RUMTimeToInitialDisplayCommand = .mockWith(
            time: runtimeLoadDate.addingTimeInterval(0.1)
        )

        // When
        manager.process(command, context: mockContext, writer: mockWriter)

        // Then
        let vitalEvents = mockWriter.events(ofType: RUMVitalAppLaunchEvent.self)
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
        let vitalEvents = mockWriter.events(ofType: RUMVitalAppLaunchEvent.self)
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
        let vitalEvents = mockWriter.events(ofType: RUMVitalAppLaunchEvent.self)
        XCTAssertEqual(vitalEvents.count, 0)
    }

    // MARK: - TTFD

    func testTTFDCommand_createsAppLaunchVitalEvents() throws {
        // Given
        let ttfd = 2.0
        let activeView: RUMViewScope = .mockWith(path: "ViewPath", name: "ViewName")
        // The TTFD is only reported if the TTID is available
        let ttidCommand: RUMTimeToInitialDisplayCommand = .mockWith(
            time: mockContext.launchInfo.processLaunchDate.addingTimeInterval(0.1)
        )
        let ttfdCommand: RUMTimeToFullDisplayCommand = .mockWith(
            time: mockContext.launchInfo.processLaunchDate.addingTimeInterval(ttfd)
        )

        // When
        manager.process(ttidCommand, context: mockContext, writer: mockWriter, activeView: activeView)
        manager.process(ttfdCommand, context: mockContext, writer: mockWriter, activeView: activeView)

        // Then
        let vitalEvents = mockWriter.events(ofType: RUMVitalAppLaunchEvent.self)
        XCTAssertEqual(vitalEvents.count, 2)

        let event = try XCTUnwrap(vitalEvents.last)
        XCTAssertNotNil(event.view)

        XCTAssertEqual(event.view.name, "ViewName")
        XCTAssertEqual(event.view.url, "ViewPath")
        XCTAssertEqual(event.vital.type, "app_launch")
        XCTAssertEqual(event.vital.appLaunchMetric, .ttfd)
        XCTAssertEqual(event.vital.name, "time_to_full_display")
        XCTAssertNotNil(event.vital.id)
        XCTAssertEqual(event.vital.isPrewarmed, false)
        XCTAssertEqual(event.vital.duration, Double(ttfd.dd.toInt64Nanoseconds))
        XCTAssertEqual(event.vital.startupType, .coldStart)

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

    func testTTFDCommand_createsAppLaunchVitalEventWithProfilingAndSendsOperationMessage() throws {
        // Given
        let featureScope = FeatureScopeMock()
        mockDependencies = .mockWith(featureScope: featureScope, appStateManager: appStateManager)
        mockContext.set(additionalContext: ProfilingContext(
            status: .error(reason: .memoryAllocationFailed),
            quotaReason: .quotaExceeded
        ))
        manager = RUMAppLaunchManager(
            parent: mockParent,
            dependencies: mockDependencies,
            telemetryController: .init()
        )

        let ttfd = 2.0
        let ttidCommand: RUMTimeToInitialDisplayCommand = .mockWith(
            time: mockContext.launchInfo.processLaunchDate.addingTimeInterval(0.1)
        )
        let ttfdCommand: RUMTimeToFullDisplayCommand = .mockWith(
            time: mockContext.launchInfo.processLaunchDate.addingTimeInterval(ttfd)
        )

        // When
        manager.process(ttidCommand, context: mockContext, writer: mockWriter)
        manager.process(ttfdCommand, context: mockContext, writer: mockWriter)

        // Then
        let event = try XCTUnwrap(mockWriter.events(ofType: RUMVitalAppLaunchEvent.self).last)
        XCTAssertEqual(event.vital.appLaunchMetric, .ttfd)
        XCTAssertEqual(event.dd.profiling?.status, .error)
        XCTAssertEqual(event.dd.profiling?.errorReason, .unexpectedException)
        XCTAssertEqual(event.dd.profiling?.quotaReason, .quotaExceeded)

        let message = try XCTUnwrap(
            featureScope.messagesSent().compactMap { $0.asPayload as? OperationMessage }.first
        )
        XCTAssertEqual(message.operation.id, event.vital.id)
        XCTAssertEqual(message.operation.name, "time_to_full_display")
        XCTAssertNil(message.operation.stepType)
        XCTAssertEqual(message.operation.duration, ttfd.dd.toInt64Nanoseconds)
        XCTAssertNotNil(message.attributes[RUMCoreContext.IDs.applicationID])
        XCTAssertNotNil(message.attributes[RUMCoreContext.IDs.sessionID])
    }

    func testTTFDCommand_whenReceivedBeforeTTID_sendsOperationMessageBeforeTTIDMessage() throws {
        // Given
        let featureScope = FeatureScopeMock()
        mockDependencies = .mockWith(featureScope: featureScope, appStateManager: appStateManager)
        manager = RUMAppLaunchManager(
            parent: mockParent,
            dependencies: mockDependencies,
            telemetryController: .init()
        )

        let ttid = 1.0
        let ttfd = 2.0
        let ttfdCommand: RUMTimeToFullDisplayCommand = .mockWith(
            time: mockContext.launchInfo.processLaunchDate.addingTimeInterval(ttfd)
        )
        let ttidCommand: RUMTimeToInitialDisplayCommand = .mockWith(
            time: mockContext.launchInfo.processLaunchDate.addingTimeInterval(ttid)
        )

        // When
        manager.process(ttfdCommand, context: mockContext, writer: mockWriter)
        manager.process(ttidCommand, context: mockContext, writer: mockWriter)

        // Then
        let vitalEvents = mockWriter.events(ofType: RUMVitalAppLaunchEvent.self)
        XCTAssertEqual(vitalEvents.count, 2)
        XCTAssertEqual(vitalEvents.map(\.vital.appLaunchMetric), [.ttid, .ttfd])

        let ttfdEvent = try XCTUnwrap(vitalEvents.last)

        let messages = featureScope.messagesSent()
        XCTAssertEqual(messages.count, 2)

        let ttfdMessage = try XCTUnwrap(messages.first?.asPayload as? OperationMessage)
        let ttidMessage = try XCTUnwrap(messages.last?.asPayload as? TTIDMessage)
        XCTAssertEqual(ttfdMessage.operation.id, ttfdEvent.vital.id)
        XCTAssertEqual(ttfdMessage.operation.name, "time_to_full_display")
        XCTAssertNil(ttfdMessage.operation.stepType)
        XCTAssertEqual(ttfdMessage.operation.duration, ttfd.dd.toInt64Nanoseconds)
        XCTAssertNotNil(ttfdMessage.attributes[RUMCoreContext.IDs.applicationID])
        XCTAssertNotNil(ttfdMessage.attributes[RUMCoreContext.IDs.sessionID])
        XCTAssertEqual(ttidMessage.ttid.name, "time_to_initial_display")
        XCTAssertNotNil(ttidMessage.attributes[RUMCoreContext.IDs.applicationID])
        XCTAssertNotNil(ttidMessage.attributes[RUMCoreContext.IDs.sessionID])
    }

    func testTTFDCommand_whenReceivedAfterTTIDBeforeStartupType_reusesTTFDVitalIDAndAttributes() throws {
        // Given
        let featureScope = FeatureScopeMock()
        let appStateManager = AppStateManagerMock()
        appStateManager.shouldDeferPreviousAppStateInfoCallback = true
        mockDependencies = .mockWith(featureScope: featureScope, appStateManager: appStateManager)
        manager = RUMAppLaunchManager(
            parent: mockParent,
            dependencies: mockDependencies,
            telemetryController: .init()
        )

        let ttid = 1.0
        let ttfd = 2.0
        let ttidCommand: RUMTimeToInitialDisplayCommand = .mockWith(
            time: mockContext.launchInfo.processLaunchDate.addingTimeInterval(ttid),
            globalAttributes: ["command": "ttid"]
        )
        let ttfdCommand: RUMTimeToFullDisplayCommand = .mockWith(
            time: mockContext.launchInfo.processLaunchDate.addingTimeInterval(ttfd),
            globalAttributes: [
                "command": "ttfd",
                "overridden": "global"
            ],
            attributes: [
                "overridden": "local",
                "ttfd": "attribute"
            ]
        )

        // When
        manager.process(ttidCommand, context: mockContext, writer: mockWriter)
        manager.process(ttfdCommand, context: mockContext, writer: mockWriter)

        // Then
        let messages = featureScope.messagesSent()
        XCTAssertEqual(messages.count, 2)

        let ttidMessage = try XCTUnwrap(messages.first?.asPayload as? TTIDMessage)
        let ttfdMessage = try XCTUnwrap(messages.last?.asPayload as? OperationMessage)
        XCTAssertEqual(ttidMessage.ttid.name, "time_to_initial_display")
        XCTAssertEqual(ttfdMessage.operation.name, "time_to_full_display")
        XCTAssertNil(ttfdMessage.operation.stepType)
        XCTAssertEqual(ttfdMessage.operation.duration, ttfd.dd.toInt64Nanoseconds)
        XCTAssertNotNil(ttfdMessage.attributes[RUMCoreContext.IDs.applicationID])
        XCTAssertNotNil(ttfdMessage.attributes[RUMCoreContext.IDs.sessionID])

        XCTAssertEqual(mockWriter.events(ofType: RUMVitalAppLaunchEvent.self).count, 0)

        appStateManager.completePreviousAppStateInfo()

        let vitalEvents = mockWriter.events(ofType: RUMVitalAppLaunchEvent.self)
        XCTAssertEqual(vitalEvents.count, 2)
        XCTAssertEqual(vitalEvents.map(\.vital.appLaunchMetric), [.ttid, .ttfd])

        let ttfdEvent = try XCTUnwrap(vitalEvents.last)
        XCTAssertEqual(ttfdEvent.vital.id, ttfdMessage.operation.id)
        XCTAssertEqual(ttfdEvent.context?.contextInfo as? [String: String], [
            "command": "ttfd",
            "overridden": "local",
            "ttfd": "attribute"
        ])
    }

    func testTTFDCommand_createsAppLaunchVitalEventsForPreWarmingLaunches() throws {
        // Given
        let processLaunchDate = Date()
        let runtimeLoadDate = processLaunchDate.addingTimeInterval(1)
        let ttfd = 3.0
        mockContext = .mockWith(
            launchInfo: .mockWith(
                launchReason: .prewarming,
                processLaunchDate: processLaunchDate,
                runtimeLoadDate: runtimeLoadDate
            )
        )
        // The TTFD is only reported if the TTID is available
        let ttidCommand: RUMTimeToInitialDisplayCommand = .mockWith(
            time: runtimeLoadDate.addingTimeInterval(0.1)
        )
        let ttfdCommand: RUMTimeToFullDisplayCommand = .mockWith(
            time: runtimeLoadDate.addingTimeInterval(ttfd)
        )

        // When
        manager.process(ttidCommand, context: mockContext, writer: mockWriter)
        manager.process(ttfdCommand, context: mockContext, writer: mockWriter)

        // Then
        let vitalEvents = mockWriter.events(ofType: RUMVitalAppLaunchEvent.self)
        XCTAssertEqual(vitalEvents.count, 2)

        let event = try XCTUnwrap(vitalEvents.last)
        XCTAssertNotNil(event.view)

        XCTAssertEqual(event.vital.type, "app_launch")
        XCTAssertEqual(event.vital.appLaunchMetric, .ttfd)
        XCTAssertEqual(event.vital.name, "time_to_full_display")
        XCTAssertEqual(event.vital.isPrewarmed, true)
        XCTAssertEqual(event.vital.duration, Double(ttfd.dd.toInt64Nanoseconds))
        XCTAssertEqual(event.vital.startupType, .coldStart)
    }

    func testTTFDCommand_createsAppLaunchVitalEventsForWarmStart() throws {
        // Given
        let appStateInfo: AppStateInfo = .mockAny()
        (appStateManager as? AppStateManagerMock)?.previousAppStateInfo = appStateInfo
        (appStateManager as? AppStateManagerMock)?.currentAppStateInfo = appStateInfo // similar AppStateInfo with the previous AppStateInfo
        let ttfd = 1.0
        // The TTFD is only reported if the TTID is available
        let ttidCommand: RUMTimeToInitialDisplayCommand = .mockWith(
            time: mockContext.launchInfo.processLaunchDate.addingTimeInterval(0.1)
        )
        let ttfdCommand: RUMTimeToFullDisplayCommand = .mockWith(
            time: mockContext.launchInfo.processLaunchDate.addingTimeInterval(ttfd)
        )

        // When
        manager.process(ttidCommand, context: mockContext, writer: mockWriter)
        manager.process(ttfdCommand, context: mockContext, writer: mockWriter)

        // Then
        let vitalEvents = mockWriter.events(ofType: RUMVitalAppLaunchEvent.self)
        XCTAssertEqual(vitalEvents.count, 2)

        let event = try XCTUnwrap(vitalEvents.last)
        XCTAssertNotNil(event.view)

        XCTAssertEqual(event.vital.type, "app_launch")
        XCTAssertEqual(event.vital.appLaunchMetric, .ttfd)
        XCTAssertEqual(event.vital.name, "time_to_full_display")
        XCTAssertEqual(event.vital.isPrewarmed, false)
        XCTAssertEqual(event.vital.duration, Double(ttfd.dd.toInt64Nanoseconds))
        XCTAssertEqual(event.vital.startupType, .warmStart)
    }

    func testTTFDCommand_isCapturedOnlyOnce() throws {
        // Given
        // The TTFD is only reported if the TTID is available
        let ttidCommand: RUMTimeToInitialDisplayCommand = .mockWith(
            time: mockContext.launchInfo.processLaunchDate.addingTimeInterval(0.1)
        )
        let firstTTFDCommand: RUMTimeToFullDisplayCommand = .mockWith(
            time: mockContext.launchInfo.processLaunchDate.addingTimeInterval(1)
        )
        let secondTTFDCommand: RUMTimeToFullDisplayCommand = .mockWith(
            time: mockContext.launchInfo.processLaunchDate.addingTimeInterval(2)
        )
        let thirdTTFDCommand: RUMTimeToFullDisplayCommand = .mockWith(
            time: mockContext.launchInfo.processLaunchDate.addingTimeInterval(3)
        )

        // When
        manager.process(ttidCommand, context: mockContext, writer: mockWriter)
        manager.process(firstTTFDCommand, context: mockContext, writer: mockWriter)
        manager.process(secondTTFDCommand, context: mockContext, writer: mockWriter)
        manager.process(thirdTTFDCommand, context: mockContext, writer: mockWriter)

        // Then
        let vitalEvents = mockWriter.events(ofType: RUMVitalAppLaunchEvent.self)
        XCTAssertEqual(vitalEvents.count, 2)
        XCTAssertEqual(vitalEvents.first?.vital.appLaunchMetric, .ttid)
        XCTAssertEqual(vitalEvents.last?.vital.appLaunchMetric, .ttfd)
    }

    func testTTFDCommand_isIgnoredWhenTheDurationIsTooBig() throws {
        // Given
        // The TTFD is only reported if the TTID is available
        let ttidCommand: RUMTimeToInitialDisplayCommand = .mockWith(
            time: mockContext.launchInfo.processLaunchDate.addingTimeInterval(0.1)
        )
        let ttfdCommand: RUMTimeToFullDisplayCommand = .mockWith(
            time: mockContext.launchInfo.processLaunchDate.addingTimeInterval(RUMAppLaunchManager.Constants.maxTTFDDuration + 1)
        )

        // When
        manager.process(ttidCommand, context: mockContext, writer: mockWriter)
        manager.process(ttfdCommand, context: mockContext, writer: mockWriter)

        // Then
        let vitalEvents = mockWriter.events(ofType: RUMVitalAppLaunchEvent.self)
        XCTAssertEqual(vitalEvents.count, 1)
        XCTAssertEqual(vitalEvents.first?.vital.appLaunchMetric, .ttid)
    }

    func testTTFDCommand_isIgnoredWhenTheDurationBetweenProcessLaunchAndMainIsTooBig() throws {
        // Given
        let processLaunchDate = Date()
        /// It is possible to observe large gaps between process launch and SDK initialization in sessions that are not prewarmed.
        let runtimeLoadDate = processLaunchDate.addingTimeInterval(RUMAppLaunchManager.Constants.maxTTFDDuration)
        mockContext = .mockWith(
            launchInfo: .mockWith(
                launchReason: .userLaunch,
                processLaunchDate: processLaunchDate,
                runtimeLoadDate: runtimeLoadDate
            )
        )
        // The TTFD is only reported if the TTID is available
        let ttidCommand: RUMTimeToInitialDisplayCommand = .mockWith(
            time: runtimeLoadDate.addingTimeInterval(0.1)
        )
        let ttfdCommand: RUMTimeToFullDisplayCommand = .mockWith(
            time: ttidCommand.time.addingTimeInterval(0.1)
        )

        // When
        manager.process(ttidCommand, context: mockContext, writer: mockWriter)
        manager.process(ttfdCommand, context: mockContext, writer: mockWriter)

        // Then
        let vitalEvents = mockWriter.events(ofType: RUMVitalAppLaunchEvent.self)
        // Both TTID and TTFD exceed the max durations
        XCTAssertEqual(vitalEvents.count, 0)
    }

    func testTTFDCommand_isIgnoredWhenTheAppIsLaunchedInBackground() throws {
        // Given
        mockContext = .mockWith(launchInfo: .mockWith(launchReason: .backgroundLaunch, processLaunchDate: Date()))
        // The TTFD is only reported if the TTID is available
        let ttidCommand: RUMTimeToInitialDisplayCommand = .mockAny()
        let ttfdCommand: RUMTimeToFullDisplayCommand = .mockWith(
            time: mockContext.launchInfo.processLaunchDate.addingTimeInterval(1)
        )

        // When
        manager.process(ttidCommand, context: mockContext, writer: mockWriter)
        manager.process(ttfdCommand, context: mockContext, writer: mockWriter)

        // Then
        let vitalEvents = mockWriter.events(ofType: RUMVitalAppLaunchEvent.self)
        XCTAssertEqual(vitalEvents.count, 0)
    }

    func testTTFDCommand_isIgnoredWhenTheAppHasUncertainLaunchReason() throws {
        // Given
        mockContext = .mockWith(launchInfo: .mockWith(launchReason: .uncertain, processLaunchDate: Date()))
        let ttidCommand: RUMTimeToInitialDisplayCommand = .mockAny()
        let ttfdCommand: RUMTimeToFullDisplayCommand = .mockWith(
            time: mockContext.launchInfo.processLaunchDate.addingTimeInterval(1)
        )

        // When
        manager.process(ttidCommand, context: mockContext, writer: mockWriter)
        manager.process(ttfdCommand, context: mockContext, writer: mockWriter)

        // Then
        let vitalEvents = mockWriter.events(ofType: RUMVitalAppLaunchEvent.self)
        XCTAssertEqual(vitalEvents.count, 0)
    }
}
