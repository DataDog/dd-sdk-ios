/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal
import UIKit

/// Bundles RUM instrumentation components.
internal final class RUMInstrumentation: RUMCommandPublisher {
    private enum Constants {
        /// Minimum allowed value for long task threshold configuration.
        static let minLongTaskThreshold: TimeInterval = 0
        /// Minimum allowed value for app hang threshold configuration.
        static let minAppHangThreshold: TimeInterval = 0.1
    }

    /// Swizzles `UIViewController` for intercepting its lifecycle callbacks.
    /// It is `nil` (no swizzling) if RUM View instrumentaiton is not enabled.
    let viewControllerSwizzler: UIViewControllerSwizzler?
    /// Receives interceptions from `UIViewControllerSwizzler` and from SwiftUI instrumentation.
    /// It is non-optional as we can't know if SwiftUI instrumentation will be used or not.
    let viewsHandler: RUMViewsHandler

    /// Swizzles `UIApplication` for intercepting `UIEvents` passed to the app.
    /// It is `nil` (no swizzling) if RUM Action instrumentaiton is not enabled.
    let uiApplicationSwizzler: UIApplicationSwizzler?
    /// Receives interceptions from `UIApplicationSwizzler` and from SwiftUI instrumentation.
    /// It is non-optional as we can't know if SwiftUI instrumentation will be used or not.
    let actionsHandler: RUMActionsHandling

    /// Instruments RUM Long Tasks. It is `nil` if long tasks tracking is not enabled.
    let longTasks: LongTaskObserver?

    /// Instruments App Hangs. It is `nil` if hangs monitoring is not enabled.
    let appHangs: AppHangsMonitor?

    /// Instruments Watchdog Terminations.
    let watchdogTermination: WatchdogTerminationMonitor?

    let memoryWarningMonitor: MemoryWarningMonitor?

    // MARK: - Initialization

    init(
        featureScope: FeatureScope,
        uiKitRUMViewsPredicate: UIKitRUMViewsPredicate?,
        uiKitRUMActionsPredicate: UIKitRUMActionsPredicate?,
        longTaskThreshold: TimeInterval?,
        appHangThreshold: TimeInterval?,
        mainQueue: DispatchQueue,
        dateProvider: DateProvider,
        backtraceReporter: BacktraceReporting,
        fatalErrorContext: FatalErrorContextNotifying,
        processID: UUID,
        watchdogTermination: WatchdogTerminationMonitor?,
        memoryWarningMonitor: MemoryWarningMonitor
    ) {
        // Always create views handler (we can't know if it will be used by SwiftUI instrumentation)
        // and only swizzle `UIViewController` if UIKit instrumentation is configured:
        let viewsHandler = RUMViewsHandler(dateProvider: dateProvider, predicate: uiKitRUMViewsPredicate)
        let viewControllerSwizzler: UIViewControllerSwizzler? = {
            do {
                if uiKitRUMViewsPredicate != nil {
                    return try UIViewControllerSwizzler(handler: viewsHandler)
                }
            } catch {
                consolePrint(
                    "🔥 Datadog SDK error: UIKit RUM Views tracking can't be enabled due to error: \(error)",
                    .error
                )
            }
            return nil
        }()

        // Always create actions handler (we can't know if it will be used by SwiftUI instrumentation)
        // and only swizzle `UIApplicationSwizzler` if UIKit instrumentation is configured:
        let actionsHandler = RUMActionsHandler(dateProvider: dateProvider, predicate: uiKitRUMActionsPredicate)
        let uiApplicationSwizzler: UIApplicationSwizzler? = {
            do {
                if uiKitRUMActionsPredicate != nil {
                    return try UIApplicationSwizzler(handler: actionsHandler)
                }
            } catch {
                consolePrint(
                    "🔥 Datadog SDK error: RUM Actions tracking can't be enabled due to error: \(error)",
                    .error
                )
            }
            return nil
        }()

        // Create long tasks and app hang observers only if configured:
        var longTasks: LongTaskObserver? = nil
        var appHangs: AppHangsMonitor? = nil

        if let longTaskThreshold = longTaskThreshold {
            if longTaskThreshold > Constants.minLongTaskThreshold {
                longTasks = LongTaskObserver(threshold: longTaskThreshold, dateProvider: dateProvider)
            } else {
                DD.logger.error("`RUM.Configuration.longTaskThreshold` cannot be less than 0s. Long Tasks monitoring will be disabled.")
            }
        }

        if var appHangThreshold = appHangThreshold {
            if appHangThreshold < Constants.minAppHangThreshold {
                appHangThreshold = Constants.minAppHangThreshold
                DD.logger.warn("`RUM.Configuration.appHangThreshold` cannot be less than \(Constants.minAppHangThreshold)s. A value of \(Constants.minAppHangThreshold)s will be used.")
            }

            appHangs = AppHangsMonitor(
                featureScope: featureScope,
                appHangThreshold: appHangThreshold,
                observedQueue: mainQueue,
                backtraceReporter: backtraceReporter,
                fatalErrorContext: fatalErrorContext,
                dateProvider: dateProvider,
                processID: processID
            )
        }

        self.viewsHandler = viewsHandler
        self.viewControllerSwizzler = viewControllerSwizzler
        self.actionsHandler = actionsHandler
        self.uiApplicationSwizzler = uiApplicationSwizzler
        self.longTasks = longTasks
        self.appHangs = appHangs
        self.watchdogTermination = watchdogTermination
        self.memoryWarningMonitor = memoryWarningMonitor

        // Enable configured instrumentations:
        self.viewControllerSwizzler?.swizzle()
        self.uiApplicationSwizzler?.swizzle()
        self.longTasks?.start()
        self.appHangs?.start()
        self.memoryWarningMonitor?.start()
    }

    deinit {
        // Disable configured instrumentations:
        viewControllerSwizzler?.unswizzle()
        uiApplicationSwizzler?.unswizzle()
        longTasks?.stop()
        appHangs?.stop()
        watchdogTermination?.stop()
        memoryWarningMonitor?.stop()
    }

    func publish(to subscriber: RUMCommandSubscriber) {
        viewsHandler.publish(to: subscriber)
        actionsHandler.publish(to: subscriber)
        longTasks?.publish(to: subscriber)
        appHangs?.nonFatalHangsHandler.publish(to: subscriber)
        memoryWarningMonitor?.reporter.publish(to: subscriber)
    }
}
