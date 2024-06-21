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
    /// RUM feature scope.
    private let featureScope: FeatureScope

    init(featureScope: FeatureScope) {
        self.featureScope = featureScope
    }

    /// Sends the Watchdog Termination event to Datadog.
    func send(date: Date?, state: WatchdogTerminationAppState, viewEvent: RUMViewEvent) {
        guard state.trackingConsent == .granted else { // consider the user consent from previous session
            DD.logger.debug("Skipped sending Watchdog Termination as it was recorded with \(state.trackingConsent) consent")
            return
        }

        let errorDate = date ?? Date(timeIntervalSinceReferenceDate: TimeInterval(viewEvent.date))

        DD.logger.debug("Sending Watchdog Termination event")
        featureScope.eventWriteContext(bypassConsent: true) { context, writer in
            let builder = FatalErrorBuilder(
                context: context,
                error: .watchdogTermination,
                errorDate: errorDate,
                errorType: "WatchdogTermination",
                errorMessage: "The operating system watchdog terminated the application.",
                errorStack: nil,
                errorThreads: nil,
                errorBinaryImages: nil,
                errorWasTruncated: nil,
                errorMeta: nil
            )
            let error = builder.createRUMError(with: viewEvent)
            let view = builder.updateRUMViewWithError(viewEvent)
            writer.write(value: error)
            writer.write(value: view)
        }
    }
}
