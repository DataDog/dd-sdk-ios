/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogInternal
import TestUtilities
@testable import DatadogCore
@testable import DatadogRUM

/// A [Test Harness](https://en.wikipedia.org/wiki/Test_harness) that simulates the iOS app environment and manages SDK lifecycle.
/// Used for testing how the SDK responds to different app states and events.
internal class AppRunner {
    /// Describes how the app process was launched.
    struct ProcessLaunchType {
        let processLaunchDate: Date
        let activePrewarm: Bool
        let initialAppState: AppState
        let description: String

        /// Represents a user-initiated launch (cold start).
        static func userLaunch(processLaunchDate: Date) -> ProcessLaunchType {
            return .init(
                processLaunchDate: processLaunchDate,
                activePrewarm: false,
                initialAppState: .inactive,
                description: "user launch"
            )
        }

        /// Represents a prewarmed process launch by the OS.
        static func osPrewarm(processLaunchDate: Date) -> ProcessLaunchType {
            return .init(
                processLaunchDate: processLaunchDate,
                activePrewarm: true,
                initialAppState: .background,
                description: "os prewarm"
            )
        }

        /// Represents a launch in the background (e.g. silent push or background fetch).
        static func backgroundLaunch(processLaunchDate: Date) -> ProcessLaunchType {
            return .init(
                processLaunchDate: processLaunchDate,
                activePrewarm: false,
                initialAppState: .background,
                description: "background launch"
            )
        }
    }

    /// Prepares the app environment for testing.
    func setUp() {
        CreateTemporaryDirectory()
    }

    /// Cleans up and resets the test environment.
    func tearDown() {
        appStateObservers.forEach { notificationCenter.removeObserver($0) }
        appStateObservers = []

        DeleteTemporaryDirectory()

        appDirectory = nil
        notificationCenter = nil
        dateProvider = nil
        appStateProvider = nil
        appLaunchHandler = nil
        core = nil
    }

    // swiftlint:disable implicitly_unwrapped_optional
    private var appDirectory: (() -> Directory)!
    private var notificationCenter: NotificationCenter!
    private var dateProvider: DateProviderMock!
    private var appStateProvider: AppStateProviderMock!
    private var appLaunchHandler: AppLaunchHandlerMock!
    private var core: DatadogCoreProxy!
    // swiftlint:enable implicitly_unwrapped_optional
    private var appStateObservers: [NSObjectProtocol] = []

    // MARK: - App Lifecycle

    /// Simulates app launch with the given process launch type.
    func launch(_ launchType: ProcessLaunchType) {
        appDirectory = { Directory(url: temporaryDirectory) }
        notificationCenter = NotificationCenter()
        dateProvider = DateProviderMock(now: launchType.processLaunchDate)
        appStateProvider = AppStateProviderMock(state: launchType.initialAppState)
        appLaunchHandler = AppLaunchHandlerMock(
            launchDate: launchType.processLaunchDate,
            timeToDidBecomeActive: nil, // will wait for SimulationStep.changeAppState(_:)
            isActivePrewarm: launchType.activePrewarm
        )

        appStateObservers = [
            notificationCenter.addObserver(forName: ApplicationNotifications.didBecomeActive, object: nil, queue: nil) { [weak self] _ in
                guard let self else {
                    return
                }

                appStateProvider.current = .active

                // Simulate the application becoming active in `appLaunchHandler`:
                let launchTime = dateProvider.now.timeIntervalSince(appLaunchHandler.launchDate)
                appLaunchHandler.simulateDidBecomeActive(timeInterval: launchTime)
            },
            notificationCenter.addObserver(forName: ApplicationNotifications.willResignActive, object: nil, queue: nil) { [weak self] _ in
                self?.appStateProvider.current = .inactive
            },
            notificationCenter.addObserver(forName: ApplicationNotifications.didEnterBackground, object: nil, queue: nil) { [weak self] _ in
                self?.appStateProvider.current = .background
            },
            notificationCenter.addObserver(forName: ApplicationNotifications.willEnterForeground, object: nil, queue: nil) { [weak self] _ in
                self?.appStateProvider.current = .inactive
            }
        ]
    }

    /// Simulates transition to the active state.
    func transitionToActive() {
        precondition(currentState != .active, "The app is already ACTIVE")
        if currentState != .inactive { // apps do not send "will enter foreground" when in INACTIVE
            notificationCenter.post(name: ApplicationNotifications.willEnterForeground, object: nil)
        }
        notificationCenter.post(name: ApplicationNotifications.didBecomeActive, object: nil)
    }

    /// Simulates transition to the background state.
    func transitionToBackground() {
        precondition(currentState != .background, "The app is already in BACKGROUND")
        if currentState != .inactive { // apps do not send "will resign active" when in INACTIVE
            notificationCenter.post(name: ApplicationNotifications.willResignActive, object: nil)
        }
        notificationCenter.post(name: ApplicationNotifications.didEnterBackground, object: nil)
    }

    /// Returns the current simulated app state.
    var currentState: AppState { appStateProvider.current }

    /// Advances the current test time by the specified interval.
    func advanceTime(by interval: TimeInterval) {
        dateProvider.now.addTimeInterval(interval)
    }

    /// Returns the current simulated time.
    var currentTime: Date { dateProvider.now }

    private var lastAppearedViewController: UIViewController?

    /// Simulates `viewDidAppear()` for a given view controller.
    /// If another view controller had previously appeared, it will automatically simulate `viewDidDisappear()` for it.
    func viewDidAppear(vc: UIViewController) {
        if let lastAppearedViewController {
            viewDidDisappear(vc: lastAppearedViewController)
        }
        vc.viewDidAppear(true)
        lastAppearedViewController = vc
    }

    /// Simulates `viewDidDisappear()` for a given view controller.
    func viewDidDisappear(vc: UIViewController) {
        vc.viewDidDisappear(true)
        if lastAppearedViewController === vc {
            lastAppearedViewController = nil
        }
    }

    // MARK: - SDK Setup

    /// Typealias for SDK configuration closure.
    typealias SDKSetup = (inout Datadog.Configuration) -> Void

    /// Initializes the SDK using an optional setup block.
    func initializeSDK(_ sdkSetup: SDKSetup = { _ in }) {
        var config = Datadog.Configuration(clientToken: "mock-client-token", env: "env")
        config.systemDirectory = appDirectory
        config.dateProvider = dateProvider
        config.notificationCenter = notificationCenter
        config.appLaunchHandler = appLaunchHandler
        config.appStateProvider = appStateProvider
        config.serverDateProvider = ServerDateProviderMock()
        sdkSetup(&config)
        do {
            core = DatadogCoreProxy(
                core: try DatadogCore(configuration: config, trackingConsent: .granted, instanceName: .mockAny())
            )
        } catch {
            preconditionFailure("\(error)")
        }
    }

    // MARK: - RUM Setup

    /// Typealias for RUM configuration closure.
    typealias RUMSetup = (inout RUM.Configuration) -> Void

    /// Enables RUM with optional configuration.
    func enableRUM(_ rumSetup: RUMSetup = { _ in }) {
        var config = RUM.Configuration(applicationID: "mock-application-id")
        config.dateProvider = dateProvider
        config.notificationCenter = notificationCenter
        rumSetup(&config)
        RUM.enable(with: config, in: core)
    }

    /// Provides convenient access to the current `RUMMonitor`.
    var rum: RUMMonitorProtocol { RUMMonitor.shared(in: core) }

    // MARK: - Data Retrieval

    /// Returns grouped RUM sessions recorded during the test.
    /// - Returns: An array of `RUMSessionMatcher` grouped by `session.id`.
    func recordedRUMSessions() throws -> [RUMSessionMatcher] {
        return try RUMSessionMatcher.groupMatchersBySessions(try core.waitAndReturnRUMEventMatchers())
    }
}
