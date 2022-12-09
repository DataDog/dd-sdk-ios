/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
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
    private let core: DatadogCoreProtocol

    /// Time provider.
    private let dateProvider: DateProvider

    init(
        core: DatadogCoreProtocol,
        dateProvider: DateProvider
    ) {
        self.core = core
        self.dateProvider = dateProvider
    }

    func send(report: DDCrashReport, with context: CrashContext) {
        guard context.trackingConsent == .granted else {
            return // Only authorized crash reports can be send
        }

        // The `report.crashDate` uses system `Date` collected at the moment of crash, so we need to adjust it
        // to the server time before processing. Following use of the current correction is not ideal, but this is the best
        // approximation we can get.
        let currentTimeCorrection = context.serverTimeOffset

        let crashDate = report.date ?? dateProvider.now
        let realCrashDate = crashDate.addingTimeInterval(currentTimeCorrection)

        let log = createLog(from: report, context: context, date: realCrashDate)

        core.send(
            message: .custom(
                key: "crash",
                baggage: ["log": log]
            )
        )
    }

    // MARK: - Building Log

    private func createLog(from report: DDCrashReport, context: CrashContext, date: Date) -> LogEvent {
        var errorAttributes: [AttributeKey: AttributeValue] = [:]
        errorAttributes[DDError.threads] = report.threads
        errorAttributes[DDError.binaryImages] = report.binaryImages
        errorAttributes[DDError.meta] = report.meta
        errorAttributes[DDError.wasTruncated] = report.wasTruncated

        let user = context.userInfo
        let deviceInfo = context.device

        return LogEvent(
            date: date,
            status: .emergency,
            message: report.message,
            error: .init(
                kind: report.type,
                message: report.message,
                stack: report.stack
            ),
            serviceName: context.service,
            environment: context.env,
            loggerName: Constants.loggerName,
            loggerVersion: context.sdkVersion,
            threadName: nil,
            applicationVersion: context.version,
            dd: .init(
                device: .init(architecture: deviceInfo.architecture)
            ),
            userInfo: .init(
                id: user?.id,
                name: user?.name,
                email: user?.email,
                extraInfo: user?.extraInfo ?? [:]
            ),
            networkConnectionInfo: context.networkConnectionInfo,
            mobileCarrierInfo: context.carrierInfo,
            attributes: .init(userAttributes: [:], internalAttributes: errorAttributes),
            tags: nil
        )
    }
}
