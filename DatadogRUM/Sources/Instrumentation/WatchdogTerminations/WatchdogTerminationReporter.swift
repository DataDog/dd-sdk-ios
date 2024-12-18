/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Reports Watchdog Termination events to Datadog.
internal protocol WatchdogTerminationReporting {
    /// Sends the Watchdog Termination event to Datadog.
    func send(date: Date?, state: WatchdogTerminationAppState, viewEvent: RUMViewEvent)
}

/// Default implementation of `WatchdogTerminationReporting`.
internal final class WatchdogTerminationReporter: WatchdogTerminationReporting {
    enum Constants {
        /// The standardized `error.message` for RUM errors describing a Watchdog Termination.
        static let errorMessage = "The operating system watchdog terminated the application."
        /// The standardized `error.type` for RUM errors describing a Watchdog Termination.
        static let errorType = "WatchdogTermination"
        /// The standardized `error.stack` when stack trace is not available for Watchdog Termination.
        static let stackNotAvailableErrorMessage = "Stack trace is not available for Watchdog Termination."
    }

    /// RUM feature scope.
    private let featureScope: FeatureScope

    private let dateProvider: DateProvider

    init(
        featureScope: FeatureScope,
        dateProvider: DateProvider
    ) {
        self.featureScope = featureScope
        self.dateProvider = dateProvider
    }

    /// Sends the Watchdog Termination event to Datadog.
    func send(date: Date?, state: WatchdogTerminationAppState, viewEvent: RUMViewEvent) {
        guard state.trackingConsent == .granted else { // consider the user consent from previous session
            DD.logger.debug("Skipped sending Watchdog Termination as it was recorded with \(state.trackingConsent) consent")
            return
        }

        let errorDate = date ?? Date(timeIntervalSinceReferenceDate: TimeInterval(viewEvent.date))

        DD.logger.debug("Sending Watchdog Termination event")
        featureScope.eventWriteContext(bypassConsent: true) { [dateProvider] context, writer in
            let realDateNow = dateProvider.now.addingTimeInterval(context.serverTimeOffset)

            let builder = FatalErrorBuilder(
                context: context,
                error: .watchdogTermination,
                errorDate: errorDate,
                errorType: Constants.errorType,
                errorMessage: Constants.errorMessage,
                errorStack: Constants.stackNotAvailableErrorMessage,
                errorThreads: nil,
                errorBinaryImages: nil,
                errorWasTruncated: nil,
                errorMeta: nil,
                additionalAttributes: nil
            )
            let error = builder.createRUMError(with: viewEvent)
            let view = builder.updateRUMViewWithError(viewEvent)

            if realDateNow.timeIntervalSince(errorDate) < FatalErrorBuilder.Constants.viewEventAvailabilityThreshold {
                DD.logger.debug("Sending Watchdog Termination as RUM error with issuing RUM view update")
                // It is still OK to send RUM view to previous RUM session.
                writer.write(value: error)
                writer.write(value: view)
            } else {
                // We know it is too late for sending RUM view to previous RUM session as it is now stale on backend.
                // To avoid inconsistency, we only send the RUM error.
                DD.logger.debug("Sending Watchdog Termination as RUM error without updating RUM view")
                writer.write(value: error)
            }
        }
    }
}
