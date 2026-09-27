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
    #if DD_RUM_LIFECYCLE_DIAGNOSTICS
    private let diagnosticsEnabled = true
    #else
    private let diagnosticsEnabled = false
    #endif
    private let diagnosticID = UUID().uuidString
    private let diagnosticLock = NSLock()
    private var diagnosticSequence = 0

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
        recordDiagnostic("teardown")
        appStateObservers.forEach { notificationCenter.removeObserver($0) }
        appStateObservers = []

        DeleteTemporaryDirectory()

        appDirectory = nil
        processInfo = nil
        notificationCenter = nil
        dateProvider = nil
        appStateProvider = nil
        appLaunchHandler = nil
        core = nil
    }

    // swiftlint:disable implicitly_unwrapped_optional
    private var appDirectory: (() -> Directory)!
    private var processInfo: ProcessInfoMock!
    private var notificationCenter: NotificationCenter!
    private var dateProvider: DateProviderMock!
    private var appStateProvider: AppStateProviderMock!
    private var appLaunchHandler: AppLaunchHandlerMock!
    #if !os(watchOS)
    private var frameInfoProvider: FrameInfoProviderMock!
    #endif
    private var core: DatadogCoreProxy!
    // swiftlint:enable implicitly_unwrapped_optional
    private var appStateObservers: [NSObjectProtocol] = []

    // MARK: - App Lifecycle

    /// Simulates app launch with the given process launch type.
    func launch(_ launchType: ProcessLaunchType) {
        appDirectory = { Directory(url: temporaryDirectory) }
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
        recordDiagnostic("launch", values: ["launchType": launchType.description])
    }

    /// Simulates transition to the active state.
    func transitionToActive() {
        precondition(currentState != .active, "The app is already ACTIVE")
        recordDiagnostic("beforeActive")
        if currentState != .inactive { // apps do not send "will enter foreground" when in INACTIVE
            notificationCenter.post(name: ApplicationNotifications.willEnterForeground, object: nil)
            recordDiagnostic("afterWillEnterForeground")
        }
        notificationCenter.post(name: ApplicationNotifications.didBecomeActive, object: nil)
        recordDiagnostic("afterDidBecomeActive")
    }

    /// Simulates transition to the background state.
    func transitionToBackground() {
        precondition(currentState != .background, "The app is already in BACKGROUND")
        recordDiagnostic("beforeBackground")
        if currentState != .inactive { // apps do not send "will resign active" when in INACTIVE
            notificationCenter.post(name: ApplicationNotifications.willResignActive, object: nil)
            recordDiagnostic("afterWillResignActive")
        }
        notificationCenter.post(name: ApplicationNotifications.didEnterBackground, object: nil)
        recordDiagnostic("afterDidEnterBackground")
    }

    /// Returns the current simulated app state.
    var currentState: AppState { appStateProvider.current }

    /// Advances the current test time by the specified interval.
    func advanceTime(by interval: TimeInterval) {
        dateProvider.now.addTimeInterval(interval)
    }

    /// Returns the current simulated time.
    var currentTime: Date { dateProvider.now }

    /// Simulates the first frame of an app launch.
    func displayFirstFrame(after interval: TimeInterval) {
        #if !os(watchOS)
        recordDiagnostic("beforeFirstFrame", values: ["providerPresent": frameInfoProvider != nil])
        self.frameInfoProvider.triggerCallback(interval: interval)
        recordDiagnostic("afterFirstFrame")
        #endif
    }

    #if !os(watchOS)
    private var lastAppearedViewController: UIViewController?

    /// Simulates `viewDidAppear()` for a given view controller.
    /// If another view controller had previously appeared, it will automatically simulate `viewDidDisappear()` for it.
    func viewDidAppear(vc: UIViewController) {
        if let lastAppearedViewController {
            viewDidDisappear(vc: lastAppearedViewController)
        }
        recordViewDiagnostic("beforeViewDidAppear", viewController: vc)
        vc.viewDidAppear(true)
        lastAppearedViewController = vc
        recordViewDiagnostic("afterViewDidAppear", viewController: vc)
    }

    /// Simulates `viewDidDisappear()` for a given view controller.
    func viewDidDisappear(vc: UIViewController) {
        recordViewDiagnostic("beforeViewDidDisappear", viewController: vc)
        vc.viewDidDisappear(true)
        if lastAppearedViewController === vc {
            lastAppearedViewController = nil
        }
        recordViewDiagnostic("afterViewDidDisappear", viewController: vc)
    }
    #endif

    // MARK: - SDK Setup

    /// Typealias for SDK configuration closure.
    typealias SDKSetup = (inout Datadog.Configuration) -> Void

    /// Initializes the SDK using an optional setup block.
    func initializeSDK(_ sdkSetup: SDKSetup = { _ in }) {
        var config = Datadog.Configuration(clientToken: "mock-client-token", env: "env")
        config.systemDirectory = appDirectory
        config.processInfo = processInfo
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
        config.mediaTimeProvider = MediaTimeProviderMock(current: 0)
        config.notificationCenter = notificationCenter
        #if !os(watchOS)
        config.frameInfoProviderFactory = { [weak self] in
            let frameInfoProvider = FrameInfoProviderMock(target: $0, selector: $1)
            self?.frameInfoProvider = frameInfoProvider
            return frameInfoProvider
        }
        #endif
        rumSetup(&config)
        RUM.enable(with: config, in: core)
        #if !os(watchOS)
        recordDiagnostic("rumEnabled", values: ["automaticViews": config.uiKitViewsPredicate != nil])
        #else
        recordDiagnostic("rumEnabled")
        #endif
    }

    /// Provides convenient access to the current `RUMMonitor`.
    var rum: RUMMonitorProtocol { RUMMonitor.shared(in: core) }

    // MARK: - Data Retrieval

    /// Flushes all pending SDK operations synchronously.
    func flush() {
        core.flush()
    }

    /// Returns grouped RUM sessions recorded during the test.
    /// - Returns: An array of `RUMSessionMatcher` grouped by `session.id`.
    func recordedRUMSessions() throws -> [RUMSessionMatcher] {
        let sessions = try RUMSessionMatcher.groupMatchersBySessions(try core.waitAndReturnRUMEventMatchers())
        if diagnosticsEnabled {
            let values = sessions.map { session -> [String: Any] in
                return [
                    "id": session.sessionID,
                    "hasTTID": session.ttidEvent != nil,
                    "views": session.views.map { view in
                        var values: [String: Any] = ["id": view.viewID, "name": view.name]
                        if let duration = view.duration {
                            values["duration"] = duration
                        }
                        return values
                    }
                ]
            }
            recordDiagnostic("result", values: ["sessions": values])
        }
        return sessions
    }

    // These opt-in test records observe the fixture without posting notifications,
    // draining SDK queues or replacing the command subscriber.
    private func recordDiagnostic(_ phase: String, values: [String: Any] = [:]) {
        guard diagnosticsEnabled else {
            return
        }
        var record = values
        record["phase"] = phase
        record["run"] = diagnosticID
        record["mainThread"] = Thread.isMainThread
        if let time = dateProvider?.now.timeIntervalSince1970 {
            record["time"] = time
        }
        if let state = appStateProvider?.current {
            record["state"] = String(describing: state)
        }
        #if !os(watchOS)
        if Thread.isMainThread, let viewController = lastAppearedViewController {
            record["lastView"] = viewDiagnostic(viewController)
        }
        #endif
        diagnosticLock.lock()
        defer { diagnosticLock.unlock() }
        diagnosticSequence += 1
        record["sequence"] = diagnosticSequence
        do {
            let data = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
            print("RUM_INTEGRATION_LIFECYCLE " + String(decoding: data, as: UTF8.self))
        } catch {
            XCTFail("Could not encode lifecycle diagnostic")
        }
    }

    #if !os(watchOS)
    private func recordViewDiagnostic(_ phase: String, viewController: UIViewController) {
        guard diagnosticsEnabled else {
            return
        }
        recordDiagnostic(phase, values: Thread.isMainThread ? ["view": viewDiagnostic(viewController)] : [:])
    }

    private func viewDiagnostic(_ viewController: UIViewController) -> [String: Any] {
        let window = viewController.viewIfLoaded?.window
        return [
            "controller": String(describing: ObjectIdentifier(viewController)),
            "window": window.map { String(describing: ObjectIdentifier($0)) } ?? "none",
            "scene": window?.windowScene?.session.persistentIdentifier ?? "none"
        ]
    }
    #endif
}
