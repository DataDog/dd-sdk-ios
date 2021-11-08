/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// An integration sending crash reports as logs.
internal struct CrashReportingWithLoggingIntegration: CrashReportingIntegration {
    struct Constants {
        /// The logger name that will appear in `Log` sent to Datadog.
        static let loggerName = "crash-reporter"
    }

    /// The output for writing logs. It uses the authorized data folder and is synchronized with the eventual
    /// authorized output working simultaneously in the Logging feature.
    private let logOutput: LogOutput
    private let dateProvider: DateProvider
    private let dateCorrector: DateCorrectorType

    /// Global configuration set for the SDK (service name, environment, application version, ...)
    private let configuration: FeaturesConfiguration.Common

    init(loggingFeature: LoggingFeature) {
        self.init(
            logOutput: LogFileOutput(
                fileWriter: loggingFeature.storage.arbitraryAuthorizedWriter,
                // The RUM Errors integration is not set for this instance of the `LogFileOutput` we don't want to
                // issue additional RUM Errors for crash reports. Those are send through `CrashReportingWithRUMIntegration`.
                rumErrorsIntegration: nil
            ),
            dateProvider: loggingFeature.dateProvider,
            dateCorrector: loggingFeature.dateCorrector,
            configuration: loggingFeature.configuration.common
        )
    }

    init(
        logOutput: LogOutput,
        dateProvider: DateProvider,
        dateCorrector: DateCorrectorType,
        configuration: FeaturesConfiguration.Common
    ) {
        self.logOutput = logOutput
        self.dateProvider = dateProvider
        self.dateCorrector = dateCorrector
        self.configuration = configuration
    }

    func send(crashReport: DDCrashReport, with crashContext: CrashContext) {
        guard crashContext.lastTrackingConsent == .granted else {
            return // Only authorized crash reports can be send
        }

        // The `crashReport.crashDate` uses system `Date` collected at the moment of crash, so we need to adjust it
        // to the server time before processing. Following use of the current correction is not ideal, but this is the best
        // approximation we can get.
        let currentTimeCorrection = dateCorrector.currentCorrection

        let crashDate = crashReport.date ?? dateProvider.currentDate()
        let realCrashDate = currentTimeCorrection.applying(to: crashDate)

        let log = createLog(from: crashReport, crashContext: crashContext, crashDate: realCrashDate)
        logOutput.write(log: log)
    }

    // MARK: - Building Log

    private func createLog(from crashReport: DDCrashReport, crashContext: CrashContext, crashDate: Date) -> LogEvent {
        var errorAttributes: [AttributeKey: AttributeValue] = [:]
        errorAttributes[DDError.threads] = crashReport.threads
        errorAttributes[DDError.binaryImages] = crashReport.binaryImages
        errorAttributes[DDError.meta] = crashReport.meta
        errorAttributes[DDError.wasTruncated] = crashReport.wasTruncated

        let user = crashContext.lastUserInfo

        return LogEvent(
            date: crashDate,
            status: .emergency,
            message: crashReport.message,
            error: .init(
                kind: crashReport.type,
                message: crashReport.message,
                stack: crashReport.stack
            ),
            serviceName: configuration.serviceName,
            environment: configuration.environment,
            loggerName: Constants.loggerName,
            loggerVersion: sdkVersion,
            threadName: nil,
            applicationVersion: configuration.applicationVersion,
            userInfo: .init(
                id: user?.id,
                name: user?.name,
                email: user?.email,
                extraInfo: user?.extraInfo ?? [:]
            ),
            networkConnectionInfo: crashContext.lastNetworkConnectionInfo,
            mobileCarrierInfo: crashContext.lastCarrierInfo,
            attributes: .init(userAttributes: [:], internalAttributes: errorAttributes),
            tags: nil
        )
    }
}
