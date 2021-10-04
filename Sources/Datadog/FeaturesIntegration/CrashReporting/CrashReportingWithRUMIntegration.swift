/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// An integration sending crash reports as RUM Errors.
internal struct CrashReportingWithRUMIntegration: CrashReportingIntegration {
    struct Constants {
        /// Maximum time since the crash (in seconds) enabling us to send the RUM View event to associate it with the interrupted RUM Session:
        /// * if the app is restarted earlier than crash time + this interval, then we send both the `RUMErrorEvent` and `RUMViewEvent`,
        /// * if the app is restarted later than crash time + this interval, then we only send `RUMErrorEvent`.
        ///
        /// This condition originates from RUM backend constraints on processing `RUMViewEvents` in stale sessions. If the session does not
        /// receive any updates for a long time, then sending some significantly later may lead to inconsistency.
        static let viewEventAvailabilityThreshold: TimeInterval = 14_400 // 4 hours
    }

    /// The output for writing RUM events. It uses the authorized data folder and is synchronized with the eventual
    /// authorized output working simultaneously in the RUM feature.
    private let rumEventOutput: RUMEventOutput
    private let dateProvider: DateProvider
    private let dateCorrector: DateCorrectorType

    // MARK: - Initialization

    init(rumFeature: RUMFeature) {
        self.init(
            rumEventOutput: RUMEventFileOutput(
                fileWriter: rumFeature.storage.arbitraryAuthorizedWriter
            ),
            dateProvider: rumFeature.dateProvider,
            dateCorrector: rumFeature.dateCorrector
        )
    }

    init(
        rumEventOutput: RUMEventOutput,
        dateProvider: DateProvider,
        dateCorrector: DateCorrectorType
    ) {
        self.rumEventOutput = rumEventOutput
        self.dateProvider = dateProvider
        self.dateCorrector = dateCorrector
    }

    // MARK: - CrashReportingIntegration

    func send(crashReport: DDCrashReport, with crashContext: CrashContext) {
        guard crashContext.lastTrackingConsent == .granted else {
            return // Only authorized crash reports can be send
        }

        guard let lastRUMViewEvent = crashContext.lastRUMViewEvent else {
            InternalMonitoringFeature.instance?.monitor.sdkLogger.error("Attempt to send crash report through RUM integration, but last `RUMViewEvent` is missing")
            return // This integration requires crash report with associated `RUMViewEvent`
        }

        // The `crashReport.crashDate` uses system `Date` collected at the moment of crash, so we need to adjust it
        // to the server time before processing. Following use of the current correction is not ideal, but this is the best
        // approximation we can get.
        let currentTimeCorrection = dateCorrector.currentCorrection

        let crashDate = crashReport.date ?? dateProvider.currentDate()
        let realCrashDate = currentTimeCorrection.applying(to: crashDate)
        let realDateNow = currentTimeCorrection.applying(to: dateProvider.currentDate())

        if realDateNow.timeIntervalSince(realCrashDate) < Constants.viewEventAvailabilityThreshold {
            let rumError = createRUMError(from: crashReport, and: lastRUMViewEvent, crashDate: realCrashDate)
            let rumView = updateRUMViewWithNewError(lastRUMViewEvent, crashDate: realCrashDate)
            rumEventOutput.write(rumEvent: rumError)
            rumEventOutput.write(rumEvent: rumView)
        } else {
            let rumError = createRUMError(from: crashReport, and: lastRUMViewEvent, crashDate: realCrashDate)
            rumEventOutput.write(rumEvent: rumError)
        }
    }

    // MARK: - Building RUM events

    /// Creates the `RUMEvent<RUMErrorEvent>` based on the session information from `lastRUMViewEvent` and `DDCrashReport` details.
    private func createRUMError(from crashReport: DDCrashReport, and lastRUMViewEvent: RUMEvent<RUMViewEvent>, crashDate: Date) -> RUMEvent<RUMErrorEvent> {
        let lastRUMView = lastRUMViewEvent.model

        let errorType = crashReport.type
        let errorMessage = crashReport.message
        let errorStackTrace = crashReport.stack

        var errorAttributes = lastRUMViewEvent.errorAttributes ?? [:]
        errorAttributes[DDError.threads] = crashReport.threads
        errorAttributes[DDError.binaryImages] = crashReport.binaryImages
        errorAttributes[DDError.meta] = crashReport.meta
        errorAttributes[DDError.wasTruncated] = crashReport.wasTruncated

        let rumError = RUMErrorEvent(
            dd: .init(
                session: .init(plan: .plan1)
            ),
            action: nil,
            application: .init(id: lastRUMView.application.id),
            connectivity: lastRUMView.connectivity,
            context: nil,
            date: crashDate.timeIntervalSince1970.toInt64Milliseconds,
            error: .init(
                handling: nil,
                handlingStack: nil,
                id: nil,
                isCrash: true,
                message: errorMessage,
                resource: nil,
                source: .source,
                stack: errorStackTrace,
                type: errorType
            ),
            service: lastRUMView.service,
            session: .init(
                hasReplay: lastRUMView.session.hasReplay,
                id: lastRUMView.session.id,
                type: .user
            ),
            synthetics: nil,
            usr: lastRUMView.usr,
            view: .init(
                id: lastRUMView.view.id,
                inForeground: nil,
                referrer: lastRUMView.view.referrer,
                url: lastRUMView.view.url
            )
        )

        return RUMEvent(
            model: rumError,
            errorAttributes: errorAttributes
        )
    }

    /// Creates RUM View event which updates given `lastRUMViewEvent` with crash information.
    private func updateRUMViewWithNewError(_ rumViewEvent: RUMEvent<RUMViewEvent>, crashDate: Date) -> RUMEvent<RUMViewEvent> {
        let original = rumViewEvent.model
        let rumView = RUMViewEvent(
            dd: .init(
                documentVersion: original.dd.documentVersion + 1,
                session: .init(plan: .plan1)
            ),
            application: original.application,
            connectivity: original.connectivity,
            context: original.context,
            date: crashDate.timeIntervalSince1970.toInt64Milliseconds,
            service: original.service,
            session: original.session,
            synthetics: nil,
            usr: original.usr,
            view: .init(
                action: original.view.action,
                cpuTicksCount: original.view.cpuTicksCount,
                cpuTicksPerSecond: original.view.cpuTicksPerSecond,
                crash: .init(count: 1),
                cumulativeLayoutShift: original.view.cumulativeLayoutShift,
                customTimings: original.view.customTimings,
                domComplete: original.view.domComplete,
                domContentLoaded: original.view.domContentLoaded,
                domInteractive: original.view.domInteractive,
                error: original.view.error,
                firstContentfulPaint: original.view.firstContentfulPaint,
                firstInputDelay: original.view.firstInputDelay,
                firstInputTime: original.view.firstInputTime,
                frozenFrame: nil,
                id: original.view.id,
                inForegroundPeriods: original.view.inForegroundPeriods,
                isActive: false,
                isSlowRendered: nil,
                largestContentfulPaint: original.view.largestContentfulPaint,
                loadEvent: original.view.loadEvent,
                loadingTime: original.view.loadingTime,
                loadingType: original.view.loadingType,
                longTask: original.view.longTask,
                memoryAverage: original.view.memoryAverage,
                memoryMax: original.view.memoryMax,
                name: original.view.name,
                referrer: original.view.referrer,
                refreshRateAverage: original.view.refreshRateAverage,
                refreshRateMin: original.view.refreshRateMin,
                resource: original.view.resource,
                timeSpent: original.view.timeSpent,
                url: original.view.url
            )
        )

        return RUMEvent(model: rumView)
    }
}
