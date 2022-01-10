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

    private struct AdjustedCrashTimings {
        /// Crash date read from `CrashReport`. It uses device time.
        let crashDate: Date
        /// Crash date adjusted with current time correction. It uses NTP time.
        let realCrashDate: Date
        /// Current time, adjusted with NTP correction.
        let realDateNow: Date
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

        let crashDate = crashReport.date ?? dateProvider.currentDate()
        let adjustedCrashTimings = AdjustedCrashTimings(
            crashDate: crashDate,
            realCrashDate: currentTimeCorrection.applying(to: crashDate),
            realDateNow: currentTimeCorrection.applying(to: dateProvider.currentDate())
        )

        if let lastRUMViewEvent = crashContext.lastRUMViewEvent {
            sendCrashReportLinkedToLastViewInPreviousSession(crashReport, lastRUMViewEventInPreviousSession: lastRUMViewEvent, using: adjustedCrashTimings)
        } else if let lastRUMSessionState = crashContext.lastRUMSessionState {
            sendCrashReportToPreviousSession(crashReport, crashContext: crashContext, lastRUMSessionStateInPreviousSession: lastRUMSessionState, using: adjustedCrashTimings)
        } else if rumConfiguration.sessionSampler.sample() { // before producing a new RUM session, we must consider sampling
            sendCrashReportToNewSession(crashReport, crashContext: crashContext, using: adjustedCrashTimings)
        } else {
            userLogger.info("There was a crash in previous session, but it is ignored due to sampling.")
        }
    }

    /// If the crash occured in an existing RUM session and we know its `lastRUMViewEvent` we send the error using that session UUID and link
    /// the crash to that view. The error event can be preceded with a view update based on `Constants.viewEventAvailabilityThreshold` condition.
    private func sendCrashReportLinkedToLastViewInPreviousSession(
        _ crashReport: DDCrashReport,
        lastRUMViewEventInPreviousSession lastRUMViewEvent: RUMEvent<RUMViewEvent>,
        using crashTimings: AdjustedCrashTimings
    ) {
        if crashTimings.realDateNow.timeIntervalSince(crashTimings.realCrashDate) < Constants.viewEventAvailabilityThreshold {
            send(crashReport: crashReport, to: lastRUMViewEvent, using: crashTimings.realCrashDate)
        } else {
            // We know it is too late for sending RUM view to previous RUM session as it is now stale on backend.
            // To avoid inconsistency, we only send the RUM error.
            userLogger.debug("Sending crash as RUM error.")
            let rumError = createRUMError(from: crashReport, and: lastRUMViewEvent, crashDate: crashTimings.realCrashDate)
            rumEventOutput.write(rumEvent: rumError)
        }
    }

    /// If the crash occured in an existing RUM session and we know its `lastRUMSessionState` but there was no `lastRUMViewEvent` we can
    /// still send the error using that session UUID. Lack of `lastRUMViewEvent` means that there was no **active** view, but the presence of
    /// `lastRUMSessionState` indicates that some views were tracked before.
    private func sendCrashReportToPreviousSession(
        _ crashReport: DDCrashReport,
        crashContext: CrashContext,
        lastRUMSessionStateInPreviousSession lastRUMSessionState: RUMSessionState,
        using crashTimings: AdjustedCrashTimings
    ) {
        let handlingRule = RUMOffViewEventsHandlingRule(
            sessionState: lastRUMSessionState,
            isAppInForeground: crashContext.lastIsAppInForeground,
            isBETEnabled: rumConfiguration.backgroundEventTrackingEnabled
        )

        let newRUMView: RUMEvent<RUMViewEvent>?

        switch handlingRule {
        case .handleInApplicationLaunchView:
            // This indicates an edge case, where RUM session was created (we know the `lastRUMSessionState`), but no RUM view event
            // was yet passed to `CrashContext` (othwesiwe we would be calling `sendCrashReportLinkedToLastViewInPreviousSession()`).
            // It can happen if crash occurs shortly after starting first RUM session, but before we complete serializing first RUM view event in `CrashContext`.
            newRUMView = createNewRUMViewEvent(
                named: RUMOffViewEventsHandlingRule.Constants.applicationLaunchViewName,
                url: RUMOffViewEventsHandlingRule.Constants.applicationLaunchViewURL,
                startDate: crashTimings.realCrashDate,
                sessionUUID: RUMUUID(rawValue: lastRUMSessionState.sessionUUID), // link it to previous RUM Session
                crashContext: crashContext
            )
        case .handleInBackgroundView:
            // It means that the crash occured as the very first event after sending app to background in previous session.
            // This is why we don't have the `lastRUMViewEvent` (no view was active), but we know the `lastRUMSessionState`.
            newRUMView = createNewRUMViewEvent(
                named: RUMOffViewEventsHandlingRule.Constants.backgroundViewName,
                url: RUMOffViewEventsHandlingRule.Constants.backgroundViewURL,
                startDate: crashTimings.realCrashDate,
                sessionUUID: RUMUUID(rawValue: lastRUMSessionState.sessionUUID), // link it to previous RUM Session
                crashContext: crashContext
            )
        case .doNotHandle:
            userLogger.debug("There was a crash in background, but it is ignored due to Background Event Tracking disabled or sampling.")
            newRUMView = nil
        }

        if let newRUMView = newRUMView {
            send(crashReport: crashReport, to: newRUMView, using: crashTimings.realCrashDate)
        }
    }

    /// If the crash occurred before starting RUM session (after initializing SDK, but before starting the first view) we don't have any session UUID to associate the error with.
    /// In that case, we consider sending this crash within a new, single-view session: either "ApplicationLaunch" view or "Background" view.
    private func sendCrashReportToNewSession(
        _ crashReport: DDCrashReport,
        crashContext: CrashContext,
        using crashTimings: AdjustedCrashTimings
    ) {
        // We can ignore `sessionState` for building the rule as we can assume there was no session sent - otherwise,
        // the `lastRUMSessionState` would have been set in `CrashContext` and we could be sending the crash to previous session
        // through `sendCrashReportToPreviousSession()`.
        let handlingRule = RUMOffViewEventsHandlingRule(
            sessionState: nil,
            isAppInForeground: crashContext.lastIsAppInForeground,
            isBETEnabled: rumConfiguration.backgroundEventTrackingEnabled
        )

        let newRUMView: RUMEvent<RUMViewEvent>?

        switch handlingRule {
        case .handleInApplicationLaunchView:
            newRUMView = createNewRUMViewEvent(
                named: RUMOffViewEventsHandlingRule.Constants.applicationLaunchViewName,
                url: RUMOffViewEventsHandlingRule.Constants.applicationLaunchViewURL,
                startDate: crashTimings.realCrashDate,
                sessionUUID: rumConfiguration.uuidGenerator.generateUnique(), // create new RUM session
                crashContext: crashContext
            )
        case .handleInBackgroundView:
            newRUMView = createNewRUMViewEvent(
                named: RUMOffViewEventsHandlingRule.Constants.backgroundViewName,
                url: RUMOffViewEventsHandlingRule.Constants.backgroundViewURL,
                startDate: crashTimings.realCrashDate,
                sessionUUID: rumConfiguration.uuidGenerator.generateUnique(), // create new RUM session
                crashContext: crashContext
            )
        case .doNotHandle:
            userLogger.debug("There was a crash in background, but it is ignored due to Background Event Tracking disabled.")
            newRUMView = nil
        }

        if let newRUMView = newRUMView {
            send(crashReport: crashReport, to: newRUMView, using: crashTimings.realCrashDate)
        }
    }

    /// Sends given `CrashReport` by linking it to given `rumView` and updating view counts accordingly.
    private func send(crashReport: DDCrashReport, to rumView: RUMEvent<RUMViewEvent>, using realCrashDate: Date) {
        userLogger.debug("Updating RUM view with crash report.")
        let updatedRUMView = updateRUMViewWithNewError(rumView, crashDate: realCrashDate)
        let rumError = createRUMError(from: crashReport, and: updatedRUMView, crashDate: realCrashDate)
        rumEventOutput.write(rumEvent: rumError)
        rumEventOutput.write(rumEvent: updatedRUMView)
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
            date: crashDate.timeIntervalSince1970.toInt64Milliseconds - 1, // -1ms to put the crash after view in RUM session
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
    private func createNewRUMViewEvent(
        named viewName: String,
        url viewURL: String,
        startDate: Date,
        sessionUUID: RUMUUID,
        crashContext: CrashContext
    ) -> RUMEvent<RUMViewEvent> {
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
                id: sessionUUID.toRUMDataFormat,
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
