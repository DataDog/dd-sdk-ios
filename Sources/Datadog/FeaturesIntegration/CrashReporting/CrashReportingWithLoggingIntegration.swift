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

    private let context: DatadogV1Context

    init(loggingFeature: LoggingFeature, context: DatadogV1Context) {
        self.init(
            logOutput: LogFileOutput(
                fileWriter: loggingFeature.storage.arbitraryAuthorizedWriter
            ),
            context: context
        )
    }

    init(
        logOutput: LogOutput,
        context: DatadogV1Context
    ) {
        self.logOutput = logOutput
        self.context = context
    }

    func send(crashReport: DDCrashReport, with crashContext: CrashContext) {
        guard crashContext.lastTrackingConsent == .granted else {
            return // Only authorized crash reports can be send
        }

        // The `crashReport.crashDate` uses system `Date` collected at the moment of crash, so we need to adjust it
        // to the server time before processing. Following use of the current correction is not ideal, but this is the best
        // approximation we can get.
        let currentTimeCorrection = context.dateCorrector.offset

        let crashDate = crashReport.date ?? context.dateProvider.now
        let realCrashDate = crashDate.addingTimeInterval(currentTimeCorrection)

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
            serviceName: context.service,
            environment: context.env,
            loggerName: Constants.loggerName,
            loggerVersion: context.sdkVersion,
            threadName: nil,
            applicationVersion: context.version,
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
