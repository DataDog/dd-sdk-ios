/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

internal class CrashReporter {
    /// Queue for synchronizing internal operations.
    private let queue: DispatchQueue

    /// An interface for accessing the `DDCrashReportingPlugin` from `DatadogCrashReporting`.
    let plugin: DDCrashReportingPluginType
    /// Integration enabling sending crash reports as Logs or RUM Errors.
    let loggingOrRUMIntegration: CrashReportingIntegration

    let crashContextProvider: CrashContextProviderType

    // MARK: - Initialization

    convenience init?(crashReportingFeature: CrashReportingFeature) {
        let loggingOrRUMIntegration: CrashReportingIntegration?

        // If RUM rum is enabled prefer it for sending crash reports, otherwise use Logging feature.
        if let rumFeature = RUMFeature.instance {
            loggingOrRUMIntegration = CrashReportingWithRUMIntegration(rumFeature: rumFeature)
        } else if let loggingFeature = LoggingFeature.instance {
            loggingOrRUMIntegration = CrashReportingWithLoggingIntegration(loggingFeature: loggingFeature)
        } else {
            loggingOrRUMIntegration = nil
        }

        guard let availableLoggingOrRUMIntegration = loggingOrRUMIntegration else {
            // This case is not reachable in higher abstraction but we add sanity warning.
            userLogger.error(
                """
                In order to use Crash Reporting, RUM or Logging feature must be enabled.
                Make sure `.enableRUM(true)` or `.enableLogging(true)` are configured
                when initializing Datadog SDK.
                """
            )
            return nil
        }

        self.init(
            crashReportingPlugin: crashReportingFeature.configuration.crashReportingPlugin,
            crashContextProvider: CrashContextProvider(
                consentProvider: crashReportingFeature.consentProvider
            ),
            loggingOrRUMIntegration: availableLoggingOrRUMIntegration
        )
    }

    init(
        crashReportingPlugin: DDCrashReportingPluginType,
        crashContextProvider: CrashContextProviderType,
        loggingOrRUMIntegration: CrashReportingIntegration
    ) {
        self.queue = DispatchQueue(
            label: "com.datadoghq.crash-reporter",
            target: .global(qos: .utility)
        )
        self.plugin = crashReportingPlugin
        self.loggingOrRUMIntegration = loggingOrRUMIntegration
        self.crashContextProvider = crashContextProvider

        // Inject current `CrashContext`
        self.inject(currentCrashContext: crashContextProvider.currentCrashContext)

        // Register for future `CrashContext` changes
        self.crashContextProvider.onCrashContextChange = { [unowned self] newCrashContext in
            self.inject(currentCrashContext: newCrashContext)
        }
    }

    // MARK: - Interaction with `DatadogCrashReporting` plugin

    func sendCrashReportIfFound() {
        queue.async {
            self.plugin.readPendingCrashReport { [unowned self] crashReport in
                guard let availableCrashReport = crashReport else {
                    return false
                }

                let crashContext = crashReport?.context.flatMap { self.decode(crashContextData: $0) }
                self.loggingOrRUMIntegration.send(crashReport: availableCrashReport, with: crashContext)
                return true
            }
        }
    }

    private func inject(currentCrashContext: CrashContext) {
        queue.async {
            if let crashContextData = self.encode(crashContext: currentCrashContext) {
                self.plugin.inject(context: crashContextData)
            }
        }
    }

    // MARK: - CrashContext Encoding and Decoding

    private let crashContextEncoder = JSONEncoder()
    private let crashContextDecoder = JSONDecoder()

    private func encode(crashContext: CrashContext) -> Data? {
        do {
            return try crashContextEncoder.encode(crashContext)
        } catch {
            userLogger.warn(
                """
                Failed to encode crash report context. The app state information associated with eventual crash
                report may be not in sync with the current state of the application.

                Error details: \(error)
                """
            )
            return nil
        }
    }

    private func decode(crashContextData: Data) -> CrashContext? {
        do {
            return try crashContextDecoder.decode(CrashContext.self, from: crashContextData)
        } catch {
            userLogger.error(
                """
                Failed to decode crash report context. The app state information associated with the crash
                report won't be in sync with the state of the application when it crashed.

                Error details: \(error)
                """
            )
            return nil
        }
    }
}
