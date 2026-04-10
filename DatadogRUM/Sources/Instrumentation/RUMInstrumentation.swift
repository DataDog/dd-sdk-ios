/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Bundles RUM instrumentation components.
internal final class RUMInstrumentation: RUMCommandPublisher {
    fileprivate enum Constants {
        /// Minimum allowed value for long task threshold configuration.
        static let minLongTaskThreshold: TimeInterval = 0
        /// Minimum allowed value for app hang threshold configuration.
        static let minAppHangThreshold: TimeInterval = 0.1
    }

    /// Receives interceptions of both automatic and manual instrumentations.
    /// It is non-optional as we can't know if SwiftUI manual instrumentation will be used or not.
    let viewsHandler: RUMViewsHandler

    /// Receives interceptions of both automatic and manual instrumentations.
    /// It is non-optional as we can't know if SwiftUI manual instrumentation will be used or not.
    let actionsHandler: RUMActionsHandling

    #if !os(watchOS)
    /// Swizzles `UIViewController` for intercepting its lifecycle callbacks.
    /// It is `nil` (no swizzling) if RUM View automatic instrumentation is not enabled.
    let viewControllerSwizzler: UIViewControllerSwizzler?

    /// Swizzles `UIApplication` for intercepting `UIEvents` passed to the app.
    /// It is `nil` (no swizzling) if RUM Action automatic instrumentation is not enabled.
    let uiApplicationSwizzler: UIApplicationSwizzler?

    #if !os(tvOS)
    /// Swizzles `UIScrollView.delegate` setter for intercepting scroll gestures.
    /// It is `nil` (no swizzling) if RUM Action automatic instrumentation is not enabled.
    let scrollViewSwizzler: UIScrollViewSwizzler?
    /// Receives scroll lifecycle events and generates RUM commands.
    let scrollHandler: RUMScrollHandler?
    #endif
    #endif

    /// Instruments RUM Long Tasks. It is `nil` if long tasks tracking is not enabled.
    let longTasks: LongTaskObserver?

    /// Instruments App Hangs. It is `nil` if hangs monitoring is not enabled or when running in an iOS widget.
    let appHangs: AppHangsMonitor?

    /// Instruments Watchdog Terminations. It is `nil` when running in an iOS widget.
    let watchdogTermination: WatchdogTerminationMonitor?

    let memoryWarningMonitor: MemoryWarningMonitor?

    // MARK: - Initialization

    #if !os(watchOS)
    init(
        featureScope: FeatureScope,
        uiKitRUMViewsPredicate: UIKitRUMViewsPredicate?,
        uiKitRUMActionsPredicate: UIKitRUMActionsPredicate?,
        swiftUIRUMViewsPredicate: SwiftUIRUMViewsPredicate?,
        swiftUIRUMActionsPredicate: SwiftUIRUMActionsPredicate?,
        longTaskThreshold: TimeInterval?,
        appHangThreshold: TimeInterval?,
        mainQueue: DispatchQueue,
        dateProvider: DateProvider,
        backtraceReporter: BacktraceReporting,
        fatalErrorContext: FatalErrorContextNotifying,
        processID: UUID,
        notificationCenter: NotificationCenter,
        bundleType: BundleType,
        watchdogTermination: WatchdogTerminationMonitor?,
        memoryWarningMonitor: MemoryWarningMonitor?,
        uuidGenerator: RUMUUIDGenerator
    ) {
        // Always create views handler (we can't know if it will be used by SwiftUI manual instrumentation)
        // and only activate `UIViewControllerSwizzler` if automatic instrumentation for UIKit or SwiftUI is configured:
        let viewsHandler = RUMViewsHandler(
            dateProvider: dateProvider,
            uiKitPredicate: uiKitRUMViewsPredicate,
            swiftUIPredicate: swiftUIRUMViewsPredicate,
            swiftUIViewNameExtractor: SwiftUIReflectionBasedViewNameExtractor(),
            notificationCenter: notificationCenter
        )
        let viewControllerSwizzler: UIViewControllerSwizzler? = {
            do {
                // Enable event interception if either UIKit or SwiftUI automatic view tracking is enabled
                if uiKitRUMViewsPredicate != nil || swiftUIRUMViewsPredicate != nil {
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

        // Always create the actions handler (we can't know if it will be used by SwiftUI manual instrumentation)
        // and only activate `UIApplicationSwizzler` if automatic instrumentation for UIKit or SwiftUI is configured
        let actionsHandler: RUMActionsHandling = {
            #if os(tvOS)
            return RUMActionsHandler(
                dateProvider: dateProvider,
                uiKitPredicate: uiKitRUMActionsPredicate
            )
            #else
            return RUMActionsHandler(
                dateProvider: dateProvider,
                uiKitPredicate: uiKitRUMActionsPredicate,
                swiftUIPredicate: swiftUIRUMActionsPredicate,
                swiftUIDetector: SwiftUIComponentFactory.createDetector()
            )
            #endif
        }()

        let uiApplicationSwizzler: UIApplicationSwizzler? = {
            do {
                // Enable event interception if either UIKit or SwiftUI automatic action tracking is enabled
                if uiKitRUMActionsPredicate != nil || swiftUIRUMActionsPredicate != nil {
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

        #if !os(tvOS)
        // Create scroll handler and swizzler if UIKit action tracking is enabled:
        let scrollHandler: RUMScrollHandler?
        let scrollViewSwizzler: UIScrollViewSwizzler?
        if let uiKitRUMActionsPredicate = uiKitRUMActionsPredicate {
            let handler = RUMScrollHandler(
                dateProvider: dateProvider,
                predicate: uiKitRUMActionsPredicate
            )
            scrollHandler = handler
            scrollViewSwizzler = {
                do {
                    return try UIScrollViewSwizzler(handler: handler)
                } catch {
                    consolePrint(
                        "🔥 Datadog SDK error: RUM scroll tracking can't be enabled due to error: \(error)",
                        .error
                    )
                    return nil
                }
            }()
        } else {
            scrollHandler = nil
            scrollViewSwizzler = nil
        }
        #endif

        self.viewsHandler = viewsHandler
        self.actionsHandler = actionsHandler
        self.viewControllerSwizzler = viewControllerSwizzler
        self.uiApplicationSwizzler = uiApplicationSwizzler
        #if !os(tvOS)
        self.scrollHandler = scrollHandler
        self.scrollViewSwizzler = scrollViewSwizzler
        #endif
        self.longTasks = LongTaskObserver(threshold: longTaskThreshold, dateProvider: dateProvider)
        self.appHangs = AppHangsMonitor(
            featureScope: featureScope,
            appHangThreshold: appHangThreshold,
            bundleType: bundleType,
            mainQueue: mainQueue,
            dateProvider: dateProvider,
            backtraceReporter: backtraceReporter,
            fatalErrorContext: fatalErrorContext,
            processID: processID,
            uuidGenerator: uuidGenerator
        )
        self.watchdogTermination = watchdogTermination
        self.memoryWarningMonitor = memoryWarningMonitor

        // Enable configured instrumentations:
        self.viewControllerSwizzler?.swizzle()
        self.uiApplicationSwizzler?.swizzle()
        #if !os(tvOS)
        self.scrollViewSwizzler?.swizzle()
        #endif
        self.longTasks?.start()
        self.appHangs?.start()
        self.memoryWarningMonitor?.start()
    }

    #else

    init(
        featureScope: FeatureScope,
        longTaskThreshold: TimeInterval?,
        appHangThreshold: TimeInterval?,
        mainQueue: DispatchQueue,
        dateProvider: DateProvider,
        backtraceReporter: BacktraceReporting,
        fatalErrorContext: FatalErrorContextNotifying,
        processID: UUID,
        notificationCenter: NotificationCenter,
        bundleType: BundleType,
        watchdogTermination: WatchdogTerminationMonitor?,
        memoryWarningMonitor: MemoryWarningMonitor?,
        uuidGenerator: RUMUUIDGenerator
    ) {
        // Always create views handler (we can't know if it will be used by manual instrumentation)
        self.viewsHandler = RUMViewsHandler(dateProvider: dateProvider, notificationCenter: notificationCenter)
        // Always create the actions handler (we can't know if it will be used by SwiftUI manual instrumentation)
        self.actionsHandler = RUMActionsHandler(dateProvider: dateProvider)
        self.longTasks = LongTaskObserver(threshold: longTaskThreshold, dateProvider: dateProvider)
        self.appHangs = AppHangsMonitor(
            featureScope: featureScope,
            appHangThreshold: appHangThreshold,
            bundleType: bundleType,
            mainQueue: mainQueue,
            dateProvider: dateProvider,
            backtraceReporter: backtraceReporter,
            fatalErrorContext: fatalErrorContext,
            processID: processID,
            uuidGenerator: uuidGenerator
        )
        self.watchdogTermination = watchdogTermination
        self.memoryWarningMonitor = memoryWarningMonitor

        // Enable configured instrumentations:
        self.longTasks?.start()
        self.appHangs?.start()
        self.memoryWarningMonitor?.start()
    }

    #endif

    deinit {
        // Disable configured instrumentations:
        #if !os(watchOS)
        viewControllerSwizzler?.unswizzle()
        uiApplicationSwizzler?.unswizzle()
        #if !os(tvOS)
        scrollViewSwizzler?.unswizzle()
        #endif
        #endif
        longTasks?.stop()
        appHangs?.stop()
        watchdogTermination?.stop()
        memoryWarningMonitor?.stop()
    }

    func publish(to subscriber: RUMCommandSubscriber) {
        viewsHandler.publish(to: subscriber)
        actionsHandler.publish(to: subscriber)
        #if !os(watchOS) && !os(tvOS)
        scrollHandler?.publish(to: subscriber)
        #endif
        longTasks?.publish(to: subscriber)
        appHangs?.nonFatalHangsHandler.publish(to: subscriber)
        memoryWarningMonitor?.reporter.publish(to: subscriber)
    }
}

private extension LongTaskObserver {
    /// Creates a `LongTaskObserver` if `threshold` is non-nil and above the minimum, otherwise returns `nil`.
    convenience init?(threshold: TimeInterval?, dateProvider: DateProvider) {
        guard let threshold = threshold else {
            return nil
        }

        guard threshold > RUMInstrumentation.Constants.minLongTaskThreshold else {
            DD.logger.error("`RUM.Configuration.longTaskThreshold` cannot be less than 0s. Long Tasks monitoring will be disabled.")
            return nil
        }

        self.init(threshold: threshold, dateProvider: dateProvider)
    }
}

private extension AppHangsMonitor {
    /// Creates an `AppHangsMonitor` if `appHangThreshold` is non-nil and `bundleType` is `.iOSApp`, otherwise returns `nil`.
    convenience init?(
        featureScope: FeatureScope,
        appHangThreshold: TimeInterval?,
        bundleType: BundleType,
        mainQueue: DispatchQueue,
        dateProvider: DateProvider,
        backtraceReporter: BacktraceReporting,
        fatalErrorContext: FatalErrorContextNotifying,
        processID: UUID,
        uuidGenerator: RUMUUIDGenerator
    ) {
        guard bundleType == .iOSApp, var appHangThreshold = appHangThreshold else {
            return nil
        }

        if appHangThreshold < RUMInstrumentation.Constants.minAppHangThreshold {
            appHangThreshold = RUMInstrumentation.Constants.minAppHangThreshold
            DD.logger.warn("`RUM.Configuration.appHangThreshold` cannot be less than \(RUMInstrumentation.Constants.minAppHangThreshold)s. A value of \(RUMInstrumentation.Constants.minAppHangThreshold)s will be used.")
        }

        self.init(
            featureScope: featureScope,
            appHangThreshold: appHangThreshold,
            observedQueue: mainQueue,
            backtraceReporter: backtraceReporter,
            fatalErrorContext: fatalErrorContext,
            dateProvider: dateProvider,
            uuidGenerator: uuidGenerator,
            processID: processID
        )
    }
}
