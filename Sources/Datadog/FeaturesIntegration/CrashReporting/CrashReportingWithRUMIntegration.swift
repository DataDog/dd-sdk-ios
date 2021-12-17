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
    private let rumConfiguration: FeaturesConfiguration.RUM

    // MARK: - Initialization

    init(rumFeature: RUMFeature) {
        self.init(
            rumEventOutput: RUMEventFileOutput(
                fileWriter: rumFeature.storage.arbitraryAuthorizedWriter
            ),
            dateProvider: rumFeature.dateProvider,
            dateCorrector: rumFeature.dateCorrector,
            rumConfiguration: rumFeature.configuration
        )
    }

    init(
        rumEventOutput: RUMEventOutput,
        dateProvider: DateProvider,
        dateCorrector: DateCorrectorType,
        rumConfiguration: FeaturesConfiguration.RUM
    ) {
        self.rumEventOutput = rumEventOutput
        self.dateProvider = dateProvider
        self.dateCorrector = dateCorrector
        self.rumConfiguration = rumConfiguration
    }

    // MARK: - CrashReportingIntegration

    func send(crashReport: DDCrashReport, with crashContext: CrashContext) {
        guard crashContext.lastTrackingConsent == .granted else {
            return // Only authorized crash reports can be send
        }

        // The `crashReport.crashDate` uses system `Date` collected at the moment of crash, so we need to adjust it
        // to the server time before processing. Following use of the current correction is not ideal (it's not the correction
        // from the moment of crash), but this is the best approximation we can get.
        let currentTimeCorrection = dateCorrector.currentCorrection

        if let lastRUMViewEvent = crashContext.lastRUMViewEvent {
            sendCrashReportToPreviousSession(crashReport, rumViewEventFromPreviousSession: lastRUMViewEvent, using: currentTimeCorrection)
        } else if rumConfiguration.sessionSampler.sample() { // before producing a new RUM session, we must consider sampling
            sendCrashReportToNewSession(crashReport, crashContext: crashContext, using: currentTimeCorrection)
        } else {
            userLogger.info("There was a crash in previous session, but it is ignored due to sampling.")
        }
    }

    /// If the crash occured in an existing RUM session and we know its `lastRUMViewEvent` we send the error using that session UUID.
    /// The error event can be preceded with a view update based on `Constants.viewEventAvailabilityThreshold` condition.
    private func sendCrashReportToPreviousSession(
        _ crashReport: DDCrashReport,
        rumViewEventFromPreviousSession lastRUMViewEvent: RUMEvent<RUMViewEvent>,
        using currentTimeCorrection: DateCorrection
    ) {
        let crashDate = crashReport.date ?? dateProvider.currentDate()
        let realCrashDate = currentTimeCorrection.applying(to: crashDate)
        let realDateNow = currentTimeCorrection.applying(to: dateProvider.currentDate())

        if realDateNow.timeIntervalSince(realCrashDate) < Constants.viewEventAvailabilityThreshold {
            let rumError = createRUMError(from: crashReport, and: lastRUMViewEvent, crashDate: realCrashDate)
            let rumView = updateRUMViewWithNewError(lastRUMViewEvent, crashDate: realCrashDate)
            rumEventOutput.write(rumEvent: rumError)
            rumEventOutput.write(rumEvent: rumView)
        } else {
            // We know it is too late for sending RUM view to previous RUM session as it is now stale on backend.
            // To avoid inconsistency, we only send the RUM error.
            let rumError = createRUMError(from: crashReport, and: lastRUMViewEvent, crashDate: realCrashDate)
            rumEventOutput.write(rumEvent: rumError)
        }
    }

    /// If the crash occurred before starting RUM session (after initializing SDK, but before starting the first view) we don't have any session UUID to associate the error with.
    /// In that case, we consider sending this crash within a new, single-view session: either "ApplicationLaunch" view or "Background" view.
    private func sendCrashReportToNewSession(
        _ crashReport: DDCrashReport,
        crashContext: CrashContext,
        using currentTimeCorrection: DateCorrection
    ) {
        // We can ignore `sessionState` for building the rule as we can assume there was no session sent - otherwise,
        // the `lastRUMViewEvent` would have been set in `CrashContext` and we could be sending the crash to previous session
        // through `sendCrashReportToPreviousSession()`.
        let handlingRule = RUMOffViewEventsHandlingRule(
            sessionState: nil,
            isAppInForeground: crashContext.lastIsAppInForeground,
            isBETEnabled: rumConfiguration.backgroundEventTrackingEnabled
        )

        let crashDate = crashReport.date ?? dateProvider.currentDate()
        let realCrashDate = currentTimeCorrection.applying(to: crashDate)
        let newRUMView: RUMEvent<RUMViewEvent>?

        switch handlingRule {
        case .handleInApplicationLaunchView:
            newRUMView = createNewRUMViewEvent(
                named: RUMOffViewEventsHandlingRule.Constants.applicationLaunchViewName,
                url: RUMOffViewEventsHandlingRule.Constants.applicationLaunchViewURL,
                startDate: realCrashDate,
                crashContext: crashContext
            )
        case .handleInBackgroundView:
            newRUMView = createNewRUMViewEvent(
                named: RUMOffViewEventsHandlingRule.Constants.backgroundViewName,
                url: RUMOffViewEventsHandlingRule.Constants.backgroundViewURL,
                startDate: realCrashDate,
                crashContext: crashContext
            )
        case .doNotHandle:
            newRUMView = nil // could mean that the crash happened in background with and BET is disabled
        }

        if var newRUMView = newRUMView {
            newRUMView = updateRUMViewWithNewError(newRUMView, crashDate: realCrashDate)
            let rumError = createRUMError(from: crashReport, and: newRUMView, crashDate: realCrashDate)
            rumEventOutput.write(rumEvent: rumError)
            rumEventOutput.write(rumEvent: newRUMView)
        }
    }

    // MARK: - Building RUM events

    /// Creates RUM error based on the session information from `lastRUMViewEvent` and `DDCrashReport` details.
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
                sourceType: .ios,
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

    /// Updates given RUM view event with crash information.
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

    /// Creates new RUM view event.
    private func createNewRUMViewEvent(named viewName: String, url viewURL: String, startDate: Date, crashContext: CrashContext) -> RUMEvent<RUMViewEvent> {
        let newSessionUUID = rumConfiguration.uuidGenerator.generateUnique()
        let viewUUID = rumConfiguration.uuidGenerator.generateUnique()

        let rumView = RUMViewEvent(
            dd: .init(
                documentVersion: 1,
                session: .init(plan: .plan1)
            ),
            application: .init(
                id: rumConfiguration.applicationID
            ),
            connectivity: RUMConnectivity(
                networkInfo: crashContext.lastNetworkConnectionInfo,
                carrierInfo: crashContext.lastCarrierInfo
            ),
            context: nil,
            date: startDate.timeIntervalSince1970.toInt64Milliseconds,
            service: nil,
            session: .init(
                hasReplay: nil,
                id: newSessionUUID.toRUMDataFormat,
                type: .user
            ),
            synthetics: nil,
            usr: crashContext.lastUserInfo.flatMap { RUMUser(userInfo: $0) },
            view: .init(
                action: .init(count: 0),
                cpuTicksCount: nil,
                cpuTicksPerSecond: nil,
                crash: .init(count: 0),
                cumulativeLayoutShift: nil,
                customTimings: nil,
                domComplete: nil,
                domContentLoaded: nil,
                domInteractive: nil,
                error: .init(count: 0),
                firstContentfulPaint: nil,
                firstInputDelay: nil,
                firstInputTime: nil,
                frozenFrame: nil,
                id: viewUUID.toRUMDataFormat,
                inForegroundPeriods: nil,
                isActive: false, // we know it won't receive updates
                isSlowRendered: nil,
                largestContentfulPaint: nil,
                loadEvent: nil,
                loadingTime: nil,
                loadingType: nil,
                longTask: nil,
                memoryAverage: nil,
                memoryMax: nil,
                name: viewName,
                referrer: nil,
                refreshRateAverage: nil,
                refreshRateMin: nil,
                resource: .init(count: 0),
                timeSpent: 1, // arbitrary, 1ns duration
                url: viewURL
            )
        )

        return RUMEvent(model: rumView)
    }
}
