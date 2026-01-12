/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
@testable import DatadogCore
@testable import DatadogRUM

extension AppRunStep {
    // MARK: - App Lifecycle

    static func appLaunch(type: AppRunner.ProcessLaunchType) -> AppRunStep {
        return AppRunStep({ app in
            app.launch(type)
        })
    }

    static func advanceTime(by duration: TimeInterval) -> AppRunStep {
        return AppRunStep({ app in
            app.advanceTime(by: duration)
        })
    }

    static func appBecomesActive(after dt: TimeInterval) -> AppRunStep {
        return AppRunStep({ app in
            app.advanceTime(by: dt)
            app.transitionToActive()
        })
    }

    static func appEntersBackground(after dt: TimeInterval) -> AppRunStep {
        return AppRunStep({ app in
            app.advanceTime(by: dt)
            app.transitionToBackground()
        })
    }

    static func appDisplaysFirstFrame(after dt: TimeInterval = 0) -> AppRunStep {
        return AppRunStep({ app in
            app.advanceTime(by: dt)
            app.displayFirstFrame(after: dt)
        })
    }

    // MARK: - RUM Use Cases

    static func enableRUM(
        after dt: TimeInterval,
        sdkSetup: AppRunner.SDKSetup? = nil,
        rumSetup: AppRunner.RUMSetup? = nil
    ) -> AppRunStep {
        return AppRunStep({ app in
            app.advanceTime(by: dt)
            app.initializeSDK(sdkSetup ?? { _ in })
            app.enableRUM { rumConfig in
                rumSetup?(&rumConfig)
                rumConfig.sessionEndedSampleRate = 0 // TODO: RUM-9335 Enable "Session Ended" telemetry after fixing `application.id` value for session stop
                rumConfig.telemetrySampleRate = 0
            }
        })
    }

    static func stopSession(after dt: TimeInterval) -> AppRunStep {
        return AppRunStep({ app in
            app.advanceTime(by: dt)
            app.rum.stopSession()
        })
    }

    static func timeoutSession() -> AppRunStep {
        return AppRunStep({ app in
            app.advanceTime(by: RUMSessionScope.Constants.sessionTimeoutDuration)
        })
    }

    static func startManualView(after dt: TimeInterval, viewName: String, viewKey: String = "view") -> AppRunStep {
        return AppRunStep({ app in
            app.advanceTime(by: dt)
            app.rum.startView(key: viewKey, name: viewName)
        })
    }

    static func stopManualView(after dt: TimeInterval, viewKey: String = "view") -> AppRunStep {
        return AppRunStep({ app in
            app.advanceTime(by: dt)
            app.rum.stopView(key: viewKey)
        })
    }

    static func startAutomaticView(after dt: TimeInterval, viewController: UIViewController) -> AppRunStep {
        return AppRunStep({ app in
            app.advanceTime(by: dt)
            app.viewDidAppear(vc: viewController)
        })
    }

    static func stopAutomaticView(after dt: TimeInterval, viewController: UIViewController) -> AppRunStep {
        return AppRunStep({ app in
            app.advanceTime(by: dt)
            app.viewDidDisappear(vc: viewController)
        })
    }

    static func trackTwoActions(after1 dt1: TimeInterval, after2 dt2: TimeInterval) -> AppRunStep {
        return AppRunStep({ app in
            app.advanceTime(by: dt1)
            app.rum.addAction(type: .custom, name: "CustomAction1")
            app.advanceTime(by: dt2)
            app.rum.addAction(type: .custom, name: "CustomAction2")
        })
    }

    static func trackResource(after dt: TimeInterval, duration: TimeInterval) -> AppRunStep {
        return AppRunStep({ app in
            app.advanceTime(by: dt)
            app.rum.startResource(resourceKey: "resource", url: URL(string: "https://resource.url")!)
            app.advanceTime(by: duration)
            app.rum.stopResource(resourceKey: "resource", response: .mockAny())
        })
    }

    static func trackTwoLongTasks(after1 dt1: TimeInterval, after2 dt2: TimeInterval, duration1: TimeInterval = 0.1, duration2: TimeInterval = 0.1) -> AppRunStep {
        return AppRunStep({ app in
            app.advanceTime(by: dt1)
            app.rum._internal?.addLongTask(at: app.currentTime, duration: duration1)
            app.advanceTime(by: dt2)
            app.rum._internal?.addLongTask(at: app.currentTime, duration: duration2)
        })
    }

    static func startResource(after dt: TimeInterval, key: String, url: URL) -> AppRunStep {
        return AppRunStep({ app in
            app.advanceTime(by: dt)
            app.rum.startResource(resourceKey: key, url: url)
        })
    }

    static func stopResource(after dt: TimeInterval, key: String) -> AppRunStep {
        return AppRunStep({ app in
            app.advanceTime(by: dt)
            app.rum.stopResource(resourceKey: key, response: .mockAny())
        })
    }
}

// MARK: - Test Utils

extension AppRunStep {
    static func flushDatadogContext() -> AppRunStep {
        AppRunStep { app in
            DatadogContextProvider.defaultQueue.sync {}
        }
    }
}
