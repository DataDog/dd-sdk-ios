/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogInternal
import TestUtilities

/// A [Test Harness](https://en.wikipedia.org/wiki/Test_harness) that simulates the iOS app environment and manages SDK lifecycle.
/// Used for testing how the SDK responds to different app states and events.
internal class AppRunner {
    /// Describes how the app process was launched.
    struct ProcessLaunchType {
        /// The current process’s task policy role (`task_role_t`), indicating how the process was launched (e.g., by user or system prewarming).
        /// See `__dd_private_AppLaunchHandler.taskPolicyRole` for context and resolution logic.
        let taskPolicyRole: Int
        let processInfoEnvironment: [String: String]
        let processLaunchDate: Date
        let runtimeLoadDate: Date
        let initialAppState: AppState
        let description: String

        /// Represents a user-initiated launch (cold start) in a `UISceneDelegate`-based app.
        /// In this setup, `application(_:didFinishLaunchingWithOptions:)` is called while the app is in the `BACKGROUND` state,
        /// unlike app-delegate-only apps which start in `INACTIVE`.
        ///
        /// Sets `TASK_FOREGROUND_APPLICATION` as the task policy role — confirmed through local testing.
        ///
        /// On watchOS, there is no UIScene support, so the app starts in `INACTIVE` (like app-delegate-based apps).
        /// The task policy role is also unavailable on watchOS.
        static func userLaunchInSceneDelegateBasedApp(processLaunchDate: Date) -> ProcessLaunchType {
            #if os(iOS) || os(visionOS)
            let taskPolicyRole = Int(TASK_FOREGROUND_APPLICATION.rawValue)
            let initialAppState = AppState.background
            #elseif os(watchOS)
            let taskPolicyRole = __dd_private_TASK_POLICY_UNAVAILABLE
            // watchOS has no UIScene-based lifecycle; the app starts in INACTIVE state.
            let initialAppState = AppState.inactive
            #else
            let taskPolicyRole = __dd_private_TASK_POLICY_UNAVAILABLE
            let initialAppState = AppState.background
            #endif

            return .init(
                taskPolicyRole: taskPolicyRole,
                processInfoEnvironment: [:],
                processLaunchDate: processLaunchDate,
                runtimeLoadDate: processLaunchDate,
                initialAppState: initialAppState,
                description: "user launch (with scene-delegate)"
            )
        }

        /// Represents a user-initiated launch (cold start) in an `UIApplicationDelegate`-only app (with no `UISceneDelegate`).
        /// In this setup, `application(_:didFinishLaunchingWithOptions:)` is called in the `INACTIVE` state.
        ///
        /// Sets `TASK_FOREGROUND_APPLICATION` as the task policy role — confirmed through local testing.
        static func userLaunchInAppDelegateBasedApp(processLaunchDate: Date) -> ProcessLaunchType {
            #if os(iOS) || os(visionOS)
            let taskPolicyRole = Int(TASK_FOREGROUND_APPLICATION.rawValue)
            #else
            let taskPolicyRole = __dd_private_TASK_POLICY_UNAVAILABLE
            #endif

            return .init(
                taskPolicyRole: taskPolicyRole,
                processInfoEnvironment: [:],
                processLaunchDate: processLaunchDate,
                runtimeLoadDate: processLaunchDate,
                initialAppState: .inactive,
                description: "user launch (with app-delegate)"
            )
        }

        /// Represents a prewarmed app process launched by the OS.
        ///
        /// Sets `TASK_DARWINBG_APPLICATION` as the task policy role, though this has not been confirmed
        /// in prewarming scenarios. This uncertainty is acceptable, as the `"ActivePrewarm"` flag in
        /// `ProcessInfo.environment` takes precedence when classifying prewarming.
        @available(tvOS, unavailable)
        static func osPrewarm(processLaunchDate: Date, runtimeLoadDate: Date) -> ProcessLaunchType {
            return .init(
                taskPolicyRole: Int(TASK_DARWINBG_APPLICATION.rawValue),
                processInfoEnvironment: ["ActivePrewarm": "1"],
                processLaunchDate: processLaunchDate,
                runtimeLoadDate: runtimeLoadDate,
                initialAppState: .background,
                description: "os prewarm"
            )
        }

        /// Represents a background launch (e.g., due to a silent push or background fetch).
        ///
        /// Sets `TASK_NONUI_APPLICATION` as the task policy role, though this has not been
        /// confirmed for background launch scenarios. This is acceptable, as the SDK determines
        /// background launch based on a heuristic: "not user launch AND not prewarming" — which is reliably detectable.
        static func backgroundLaunch(processLaunchDate: Date) -> ProcessLaunchType {
            #if os(iOS) || os(visionOS)
            let taskPolicyRole = Int(TASK_NONUI_APPLICATION.rawValue)
            #else
            let taskPolicyRole = __dd_private_TASK_POLICY_UNAVAILABLE
            #endif

            return .init(
                taskPolicyRole: taskPolicyRole,
                processInfoEnvironment: [:],
                processLaunchDate: processLaunchDate,
                runtimeLoadDate: processLaunchDate,
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

        appDirectoryURL = nil
        processInfo = nil
        notificationCenter = nil
        dateProvider = nil
        appStateProvider = nil
        appLaunchHandler = nil
        state.removeAll()
    }

    // swiftlint:disable implicitly_unwrapped_optional
    var appDirectoryURL: URL!
    var processInfo: ProcessInfoMock!
    var notificationCenter: NotificationCenter!
    var dateProvider: DateProviderMock!
    var appStateProvider: AppStateProviderMock!
    var appLaunchHandler: AppLaunchHandlerMock!
    #if !os(watchOS)
    var frameInfoProvider: FrameInfoProviderMock!
    #endif
    // swiftlint:enable implicitly_unwrapped_optional
    private var appStateObservers: [NSObjectProtocol] = []
    /// Per-feature anonymous storage. Each `AppRunner+<Feature>` extension reads/writes
    /// its own slot via a computed property (e.g., `core`, `loggers`), keeping the main
    /// class SDK-agnostic.
    var state: [String: Any] = [:]
    #if !os(watchOS)
    var lastAppearedViewController: UIViewController?
    #endif

    // MARK: - App Lifecycle

    /// Simulates app launch with the given process launch type.
    func launch(_ launchType: ProcessLaunchType) {
        appDirectoryURL = temporaryDirectory
        processInfo = ProcessInfoMock(environment: launchType.processInfoEnvironment)
        notificationCenter = NotificationCenter()
        dateProvider = DateProviderMock(now: launchType.processLaunchDate)
        appStateProvider = AppStateProviderMock(state: launchType.initialAppState)
        appLaunchHandler = AppLaunchHandlerMock(
            taskPolicyRole: launchType.taskPolicyRole,
            processLaunchDate: launchType.processLaunchDate,
            runtimeLoadDate: launchType.runtimeLoadDate,
            didBecomeActiveDate: nil // will wait for SimulationStep.changeAppState(_:)
        )

        appStateObservers = [
            notificationCenter.addObserver(forName: ApplicationNotifications.didBecomeActive, object: nil, queue: nil) { [weak self] _ in
                guard let self else {
                    return
                }

                appStateProvider.current = .active

                // Simulate the application becoming active in `appLaunchHandler`:
                appLaunchHandler.simulateDidBecomeActive(date: dateProvider.now)
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
}
