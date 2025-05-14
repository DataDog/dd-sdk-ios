/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogRUM
import DatadogInternal
import TestUtilities

/// Test case covering scenarios of starting RUM session.
class StartingRUMSessionTests: XCTestCase {
    private var core: DatadogCoreProxy! // swiftlint:disable:this implicitly_unwrapped_optional
    private var rumConfig: RUM.Configuration! // swiftlint:disable:this implicitly_unwrapped_optional

    /// The date of app process start.
    private let processStartTime = Date()
    /// The time it took for app process to start.
    private let processStartDuration: TimeInterval = 2.5
    /// The date of SDK init.
    private lazy var sdkInitTime = processStartTime.addingTimeInterval(processStartDuration)
    /// The date of first activity in RUM.
    private lazy var firstRUMTime = sdkInitTime.addingTimeInterval(3)

    override func setUp() {
        super.setUp()
        core = DatadogCoreProxy()
        rumConfig = RUM.Configuration(applicationID: .mockAny())
    }

        override func tearDownWithError() throws {
        try core.flushAndTearDown()
        core = nil
        rumConfig = nil
        super.tearDown()
    }

    func testGivenAppLaunchInForegroundAndNoPrewarming_whenRUMisEnabled_itStartsAppLaunchViewAndSendsAppStartAction() throws {
        // Given
        core.context = .mockWith(
            sdkInitDate: sdkInitTime,
            launchTime: .mockWith(
                launchTime: processStartDuration,
                launchDate: processStartTime,
                isActivePrewarm: false
            ),
            applicationStateHistory: .mockAppInForeground(
                since: processStartTime
            )
        )
        let rumTime = DateProviderMock()
        rumConfig.dateProvider = rumTime
        rumConfig.trackBackgroundEvents = .mockRandom() // no matter BET state

        // When
        rumTime.now = sdkInitTime
        RUM.enable(with: rumConfig, in: core)

        // Then
        let session = try RUMSessionMatcher
            .groupMatchersBySessions(try core.waitAndReturnRUMEventMatchers())
            .takeSingle()

        XCTAssertEqual(session.views.count, 1)
        XCTAssertTrue(try session.has(sessionPrecondition: .userAppLaunch), "Session must be marked as 'user app launch'")

        let initView = try XCTUnwrap(session.views.first)
        XCTAssertTrue(initView.isApplicationLaunchView(), "Session should begin with 'app launch' view")

        let initViewEvent = try XCTUnwrap(initView.viewEvents.last)
        XCTAssertEqual(initViewEvent.date, processStartTime.timeIntervalSince1970.toInt64Milliseconds, "The 'app launch' view should start at process launch")
        XCTAssertEqual(initViewEvent.view.timeSpent, (sdkInitTime.timeIntervalSince(processStartTime)).toInt64Nanoseconds, "The 'app launch' view should span from app launch to 'sdk init'")

        let actionEvent = try XCTUnwrap(initView.actionEvents.first)
        XCTAssertEqual(actionEvent.action.type, .applicationStart, "The 'app launch' view should send 'app start' action")
        XCTAssertEqual(actionEvent.date, initViewEvent.date, "The 'app start' action must occur at the beginning of 'app launch' view")
        XCTAssertEqual(actionEvent.action.loadingTime, processStartDuration.toInt64Nanoseconds, "The duration of 'app start' action must equal to the duration of process launch")
    }

    func testGivenAppLaunchInForegroundAndNoPrewarming_whenRUMisEnabledAndViewIsTracked_itStartsWithAppLaunchViewAndSendsAppStartAction() throws {
        // Given
        core.context = .mockWith(
            sdkInitDate: sdkInitTime,
            launchTime: .mockWith(
                launchTime: processStartDuration,
                launchDate: processStartTime,
                isActivePrewarm: false
            ),
            applicationStateHistory: .mockAppInForeground(
                since: processStartTime
            )
        )
        let rumTime = DateProviderMock()
        rumConfig.dateProvider = rumTime
        rumConfig.trackBackgroundEvents = .mockRandom() // no matter BET state

        // When
        rumTime.now = sdkInitTime
        RUM.enable(with: rumConfig, in: core)

        rumTime.now = firstRUMTime
        RUMMonitor.shared(in: core).startView(key: "key", name: "FirstView")

        // Then
        let session = try RUMSessionMatcher
            .groupMatchersBySessions(try core.waitAndReturnRUMEventMatchers())
            .takeSingle()

        XCTAssertEqual(session.views.count, 2)
        XCTAssertTrue(try session.has(sessionPrecondition: .userAppLaunch), "Session must be marked as 'user app launch'")

        let initView = try XCTUnwrap(session.views.first)
        XCTAssertTrue(initView.isApplicationLaunchView(), "Session should begin with 'app launch' view")

        let initViewEvent = try XCTUnwrap(initView.viewEvents.last)
        XCTAssertEqual(initViewEvent.date, processStartTime.timeIntervalSince1970.toInt64Milliseconds, "The 'app launch' view should start at process launch")
        XCTAssertEqual(initViewEvent.view.timeSpent, (firstRUMTime.timeIntervalSince(processStartTime)).toInt64Nanoseconds, "The 'app launch' view should span from app launch to first view")

        let actionEvent = try XCTUnwrap(initView.actionEvents.first)
        XCTAssertEqual(actionEvent.action.type, .applicationStart, "The 'app launch' view should send 'app start' action")
        XCTAssertEqual(actionEvent.date, initViewEvent.date, "The 'app start' action must occur at the beginning of 'app launch' view")
        XCTAssertEqual(actionEvent.action.loadingTime, processStartDuration.toInt64Nanoseconds, "The duration of 'app start' action must equal to the duration of process launch")

        let firstView = try XCTUnwrap(session.views.last)
        XCTAssertEqual(firstView.name, "FirstView")
        XCTAssertEqual(firstView.viewEvents.last?.date, firstRUMTime.timeIntervalSince1970.toInt64Milliseconds)
    }

    func testGivenAppLaunchInBackgroundAndNoPrewarming_whenRUMisEnabledAndViewIsTracked_itStartsWithTrackedView() throws {
        // Given
        core.context = .mockWith(
            sdkInitDate: sdkInitTime,
            launchTime: .mockWith(
                launchTime: processStartDuration,
                launchDate: processStartTime,
                isActivePrewarm: false
            ),
            applicationStateHistory: .mockAppInBackground(
                since: processStartTime
            )
        )
        let rumTime = DateProviderMock()
        rumConfig.dateProvider = rumTime
        rumConfig.trackBackgroundEvents = .mockRandom() // no matter BET state

        // When
        rumTime.now = sdkInitTime
        RUM.enable(with: rumConfig, in: core)

        rumTime.now = firstRUMTime
        RUMMonitor.shared(in: core).startView(key: "key", name: "FirstView")

        // Then
        let session = try RUMSessionMatcher
            .groupMatchersBySessions(try core.waitAndReturnRUMEventMatchers())
            .takeSingle()

        XCTAssertEqual(session.views.count, 1)
        XCTAssertTrue(try session.has(sessionPrecondition: .backgroundLaunch), "Session must be marked as 'background launch'")

        let firstView = try XCTUnwrap(session.views.first)
        XCTAssertFalse(firstView.isApplicationLaunchView(), "Session should not begin with 'app launch' view")
        XCTAssertEqual(firstView.name, "FirstView")
        XCTAssertEqual(firstView.viewEvents.last?.date, firstRUMTime.timeIntervalSince1970.toInt64Milliseconds)
        XCTAssertTrue(firstView.actionEvents.isEmpty, "The 'app start' action should not be sent")
    }

    func testGivenAppLaunchWithPrewarming_whenRUMisEnabledAndViewIsTrackedInBackground_itStartsWithTrackedView() throws {
        // Given
        core.context = .mockWith(
            sdkInitDate: sdkInitTime,
            launchTime: .mockWith(
                launchTime: processStartDuration,
                launchDate: processStartTime,
                isActivePrewarm: true
            ),
            applicationStateHistory: .mockAppInBackground( // active prewarm implies background
                since: processStartTime
            )
        )
        let rumTime = DateProviderMock()
        rumConfig.dateProvider = rumTime
        rumConfig.trackBackgroundEvents = .mockRandom() // no matter BET state

        // When
        rumTime.now = sdkInitTime
        RUM.enable(with: rumConfig, in: core)

        rumTime.now = firstRUMTime
        RUMMonitor.shared(in: core).startView(key: "key", name: "FirstView")

        // Then
        let session = try RUMSessionMatcher
            .groupMatchersBySessions(try core.waitAndReturnRUMEventMatchers())
            .takeSingle()

        XCTAssertEqual(session.views.count, 1)
        XCTAssertTrue(try session.has(sessionPrecondition: .prewarm), "Session must be marked as 'prewarm'")

        let firstView = try XCTUnwrap(session.views.first)
        XCTAssertFalse(firstView.isApplicationLaunchView(), "Session should not begin with 'app launch' view")
        XCTAssertEqual(firstView.name, "FirstView")
        XCTAssertEqual(firstView.viewEvents.last?.date, firstRUMTime.timeIntervalSince1970.toInt64Milliseconds)
        XCTAssertTrue(firstView.actionEvents.isEmpty, "The 'app start' action should not be sent")
    }

    func testGivenAppLaunchWithPrewarming_whenRUMisEnabledAndViewIsTrackedInForeground_itStartsWithAppLaunchViewAndSendsAppStartAction() throws {
        // Given
        core.context = .mockWith(
            sdkInitDate: sdkInitTime,
            launchTime: .mockWith(
                launchTime: processStartDuration,
                launchDate: processStartTime,
                isActivePrewarm: true
            ),
            applicationStateHistory: .mockWith(
                initialState: .background, // active prewarm implies background
                date: processStartTime,
                transitions: [(state: .active, date: firstRUMTime.addingTimeInterval(-0.5))] // become active shortly before view is started
            )
        )
        let rumTime = DateProviderMock()
        rumConfig.dateProvider = rumTime
        rumConfig.trackBackgroundEvents = .mockRandom() // no matter BET state

        // When
        rumTime.now = sdkInitTime
        RUM.enable(with: rumConfig, in: core)

        rumTime.now = firstRUMTime
        RUMMonitor.shared(in: core).startView(key: "key", name: "FirstView")

        // Then
        let session = try RUMSessionMatcher
            .groupMatchersBySessions(try core.waitAndReturnRUMEventMatchers())
            .takeSingle()

        XCTAssertEqual(session.views.count, 2)
        XCTAssertTrue(try session.has(sessionPrecondition: .prewarm), "Session must be marked as 'prewarm'")

        let initView = try XCTUnwrap(session.views.first)
        XCTAssertTrue(initView.isApplicationLaunchView(), "Session should begin with 'app launch' view")

        let initViewEvent = try XCTUnwrap(initView.viewEvents.last)
        XCTAssertEqual(initViewEvent.date, sdkInitTime.timeIntervalSince1970.toInt64Milliseconds, "The 'app launch' view should start at sdk init")
        XCTAssertEqual(initViewEvent.view.timeSpent, (firstRUMTime.timeIntervalSince(sdkInitTime)).toInt64Nanoseconds, "The 'app launch' view should span from sdk init to first view")

        let actionEvent = try XCTUnwrap(initView.actionEvents.first)
        XCTAssertEqual(actionEvent.action.type, .applicationStart, "The 'app launch' view should send 'app start' action")
        XCTAssertEqual(actionEvent.date, initViewEvent.date, "The 'app start' action must occur at the beginning of 'app launch' view")
        XCTAssertNil(actionEvent.action.loadingTime, "The 'app start' action must have no 'loading time' set as we can't know it for prewarmed session")

        let firstView = try XCTUnwrap(session.views.last)
        XCTAssertEqual(firstView.name, "FirstView")
        XCTAssertEqual(firstView.viewEvents.last?.date, firstRUMTime.timeIntervalSince1970.toInt64Milliseconds)
    }

    // MARK: - Test Background Events Tracking

    func testGivenAppLaunchWithPrewarmingAndBETEnabled_whenRUMisEnabledAndInteractionEventIsTracked_itStartsWithBackgroundView() throws {
       // Given
        core.context = .mockWith(
            sdkInitDate: sdkInitTime,
            launchTime: .mockWith(
                launchTime: processStartDuration,
                launchDate: processStartTime,
                isActivePrewarm: true
            ),
            applicationStateHistory: .mockAppInBackground( // active prewarm implies background
                since: processStartTime
            )
        )
        let rumTime = DateProviderMock()
        rumConfig.dateProvider = rumTime
        rumConfig.trackBackgroundEvents = true

        // When
        rumTime.now = sdkInitTime
        RUM.enable(with: rumConfig, in: core)

        rumTime.now = firstRUMTime
        RUMMonitor.shared(in: core).addAction(type: .custom, name: "CustomAction")

        // Then
        let session = try RUMSessionMatcher
            .groupMatchersBySessions(try core.waitAndReturnRUMEventMatchers())
            .takeSingle()

        XCTAssertEqual(session.views.count, 1)
        XCTAssertTrue(try session.has(sessionPrecondition: .prewarm), "Session must be marked as 'prewarm'")

        let initView = try XCTUnwrap(session.views.first)
        XCTAssertTrue(initView.isBackgroundView(), "Session should begin with 'background' view")
        XCTAssertFalse(initView.actionEvents.contains(where: { $0.action.type == .applicationStart }), "The 'app start' action should not be sent")

        let actionEvent = try XCTUnwrap(initView.actionEvents.first)
        XCTAssertEqual(actionEvent.date, firstRUMTime.timeIntervalSince1970.toInt64Milliseconds)
        XCTAssertEqual(actionEvent.action.target?.name, "CustomAction")
    }

    func testGivenAppLaunchWithPrewarmingAndBETDisabled_whenRUMisEnabledAndInteractionEventIsTracked_itIgnoresTheEvent() throws {
       // Given
        core.context = .mockWith(
            sdkInitDate: sdkInitTime,
            launchTime: .mockWith(
                launchTime: processStartDuration,
                launchDate: processStartTime,
                isActivePrewarm: true
            ),
            applicationStateHistory: .mockAppInBackground( // active prewarm implies background
                since: processStartTime
            )
        )
        let rumTime = DateProviderMock()
        rumConfig.dateProvider = rumTime
        rumConfig.trackBackgroundEvents = false

        // When
        rumTime.now = sdkInitTime
        RUM.enable(with: rumConfig, in: core)

        rumTime.now = firstRUMTime
        RUMMonitor.shared(in: core).addAction(type: .custom, name: "CustomAction")

        // Then
        let events = core.waitAndReturnEventsData(ofFeature: RUMFeature.name, timeout: .now() + 1)
        XCTAssertTrue(events.isEmpty, "The session should not be started (no events must be sent)")
    }
}
