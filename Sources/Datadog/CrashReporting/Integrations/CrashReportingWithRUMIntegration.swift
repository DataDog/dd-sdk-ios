/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
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

    private let applicationID: String
    private let dateProvider: DateProvider
    private let sessionSampler: Sampler
    private let backgroundEventTrackingEnabled: Bool
    private let uuidGenerator: RUMUUIDGenerator

    private let core: DatadogCoreProtocol

    // MARK: - Initialization

    init(
        core: DatadogCoreProtocol,
        applicationID: String,
        dateProvider: DateProvider,
        sessionSampler: Sampler,
        backgroundEventTrackingEnabled: Bool,
        uuidGenerator: RUMUUIDGenerator
    ) {
        self.core = core
        self.applicationID = applicationID
        self.dateProvider = dateProvider
        self.sessionSampler = sessionSampler
        self.backgroundEventTrackingEnabled = backgroundEventTrackingEnabled
        self.uuidGenerator = uuidGenerator
    }

    // MARK: - CrashReportingIntegration

    func send(report: DDCrashReport, with context: CrashContext) {
        guard context.trackingConsent == .granted else {
            return // Only authorized crash reports can be send
        }

        // The `crashReport.crashDate` uses system `Date` collected at the moment of crash, so we need to adjust it
        // to the server time before processing. Following use of the current correction is not ideal (it's not the correction
        // from the moment of crash), but this is the best approximation we can get.
        let currentTimeCorrection = context.serverTimeOffset

        let crashDate = report.date ?? dateProvider.now
        let adjustedCrashTimings = AdjustedCrashTimings(
            crashDate: crashDate,
            realCrashDate: crashDate.addingTimeInterval(currentTimeCorrection),
            realDateNow: dateProvider.now.addingTimeInterval(currentTimeCorrection)
        )

        if let lastRUMViewEvent = context.lastRUMViewEvent {
            sendCrashReportLinkedToLastViewInPreviousSession(report, lastRUMViewEventInPreviousSession: lastRUMViewEvent, using: adjustedCrashTimings)
        } else if let lastRUMSessionState = context.lastRUMSessionState {
            sendCrashReportToPreviousSession(report, crashContext: context, lastRUMSessionStateInPreviousSession: lastRUMSessionState, using: adjustedCrashTimings)
        } else if sessionSampler.sample() { // before producing a new RUM session, we must consider sampling
            sendCrashReportToNewSession(report, crashContext: context, using: adjustedCrashTimings)
        } else {
            DD.logger.debug("There was a crash in previous session, but it is ignored due to sampling.")
        }
    }

    /// If the crash occured in an existing RUM session and we know its `lastRUMViewEvent` we send the error using that session UUID and link
    /// the crash to that view. The error event can be preceded with a view update based on `Constants.viewEventAvailabilityThreshold` condition.
    private func sendCrashReportLinkedToLastViewInPreviousSession(
        _ crashReport: DDCrashReport,
        lastRUMViewEventInPreviousSession lastRUMViewEvent: RUMViewEvent,
        using crashTimings: AdjustedCrashTimings
    ) {
        if crashTimings.realDateNow.timeIntervalSince(crashTimings.realCrashDate) < Constants.viewEventAvailabilityThreshold {
            send(crashReport: crashReport, to: lastRUMViewEvent, using: crashTimings.realCrashDate)
        } else {
            // We know it is too late for sending RUM view to previous RUM session as it is now stale on backend.
            // To avoid inconsistency, we only send the RUM error.
            DD.logger.debug("Sending crash as RUM error.")
            let rumError = createRUMError(from: crashReport, and: lastRUMViewEvent, crashDate: crashTimings.realCrashDate)
            core.send(
                message: .custom(
                    key: "crash",
                    baggage: ["rum-error": rumError]
                )
            )
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
            isBETEnabled: backgroundEventTrackingEnabled
        )

        let newRUMView: RUMViewEvent?

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
                context: crashContext,
                hasReplay: lastRUMSessionState.didStartWithReplay
            )
        case .handleInBackgroundView:
            // It means that the crash occured as the very first event after sending app to background in previous session.
            // This is why we don't have the `lastRUMViewEvent` (no view was active), but we know the `lastRUMSessionState`.
            newRUMView = createNewRUMViewEvent(
                named: RUMOffViewEventsHandlingRule.Constants.backgroundViewName,
                url: RUMOffViewEventsHandlingRule.Constants.backgroundViewURL,
                startDate: crashTimings.realCrashDate,
                sessionUUID: RUMUUID(rawValue: lastRUMSessionState.sessionUUID), // link it to previous RUM Session
                context: crashContext,
                hasReplay: lastRUMSessionState.didStartWithReplay
            )
        case .doNotHandle:
            DD.logger.debug("There was a crash in background, but it is ignored due to Background Event Tracking disabled or sampling.")
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
            isBETEnabled: backgroundEventTrackingEnabled
        )

        let newRUMView: RUMViewEvent?

        switch handlingRule {
        case .handleInApplicationLaunchView:
            newRUMView = createNewRUMViewEvent(
                named: RUMOffViewEventsHandlingRule.Constants.applicationLaunchViewName,
                url: RUMOffViewEventsHandlingRule.Constants.applicationLaunchViewURL,
                startDate: crashTimings.realCrashDate,
                sessionUUID: uuidGenerator.generateUnique(), // create new RUM session
                context: crashContext,
                // As the crash occured after initializing SDK but before starting the first view,
                // we can't know if Session Replay was configured. However, lack of view implies
                // that there must be no replay collected:
                hasReplay: false
            )
        case .handleInBackgroundView:
            newRUMView = createNewRUMViewEvent(
                named: RUMOffViewEventsHandlingRule.Constants.backgroundViewName,
                url: RUMOffViewEventsHandlingRule.Constants.backgroundViewURL,
                startDate: crashTimings.realCrashDate,
                sessionUUID: uuidGenerator.generateUnique(), // create new RUM session
                context: crashContext,
                // As the crash occured after initializing SDK but before starting the first view,
                // we can't know if Session Replay was configured. However, lack of view implies
                // that there must be no replay collected:
                hasReplay: false
            )
        case .doNotHandle:
            DD.logger.debug("There was a crash in background, but it is ignored due to Background Event Tracking disabled.")
            newRUMView = nil
        }

        if let newRUMView = newRUMView {
            send(crashReport: crashReport, to: newRUMView, using: crashTimings.realCrashDate)
        }
    }

    /// Sends given `CrashReport` by linking it to given `rumView` and updating view counts accordingly.
    private func send(crashReport: DDCrashReport, to rumView: RUMViewEvent, using realCrashDate: Date) {
        DD.logger.debug("Updating RUM view with crash report.")
        let updatedRUMView = updateRUMViewWithNewError(rumView, crashDate: realCrashDate)
        let rumError = createRUMError(from: crashReport, and: updatedRUMView, crashDate: realCrashDate)

        core.send(
            message: .custom(
                key: "crash",
                baggage: [
                    "rum-error": rumError,
                    "rum-view": updatedRUMView
                ]
            )
        )
    }

    // MARK: - Building RUM events

    /// Creates RUM error based on the session information from `lastRUMViewEvent` and `DDCrashReport` details.
    private func createRUMError(from crashReport: DDCrashReport, and lastRUMView: RUMViewEvent, crashDate: Date) -> RUMCrashEvent {
        let errorType = crashReport.type
        let errorMessage = crashReport.message
        let errorStackTrace = crashReport.stack

        var errorAttributes: [String: Encodable] = [:]
        errorAttributes[DDError.threads] = crashReport.threads
        errorAttributes[DDError.binaryImages] = crashReport.binaryImages
        errorAttributes[DDError.meta] = crashReport.meta
        errorAttributes[DDError.wasTruncated] = crashReport.wasTruncated

        let event = RUMErrorEvent(
            dd: .init(
                browserSdkVersion: nil,
                session: .init(plan: .plan1)
            ),
            action: nil,
            application: .init(id: lastRUMView.application.id),
            ciTest: lastRUMView.ciTest,
            connectivity: lastRUMView.connectivity,
            context: nil,
            date: crashDate.timeIntervalSince1970.toInt64Milliseconds,
            device: lastRUMView.device,
            display: nil,
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
            os: lastRUMView.os,
            service: lastRUMView.service,
            session: .init(
                hasReplay: lastRUMView.session.hasReplay,
                id: lastRUMView.session.id,
                type: lastRUMView.ciTest != nil ? .ciTest : .user
            ),
            source: lastRUMView.source?.toErrorEventSource ?? .ios,
            synthetics: nil,
            usr: lastRUMView.usr,
            version: lastRUMView.version,
            view: .init(
                id: lastRUMView.view.id,
                inForeground: nil,
                referrer: lastRUMView.view.referrer,
                url: lastRUMView.view.url
            )
        )

        return RUMCrashEvent(
            error: event,
            additionalAttributes: errorAttributes
        )
    }

    /// Updates given RUM view event with crash information.
    private func updateRUMViewWithNewError(_ original: RUMViewEvent, crashDate: Date) -> RUMViewEvent {
        return RUMViewEvent(
            dd: .init(
                browserSdkVersion: nil,
                documentVersion: original.dd.documentVersion + 1,
                session: .init(plan: .plan1)
            ),
            application: original.application,
            ciTest: original.ciTest,
            connectivity: original.connectivity,
            context: original.context,
            date: crashDate.timeIntervalSince1970.toInt64Milliseconds - 1, // -1ms to put the crash after view in RUM session
            device: original.device,
            display: nil,
            os: original.os,
            service: original.service,
            session: original.session,
            source: original.source ?? .ios,
            synthetics: nil,
            usr: original.usr,
            version: original.version,
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
                firstByte: nil,
                firstContentfulPaint: original.view.firstContentfulPaint,
                firstInputDelay: original.view.firstInputDelay,
                firstInputTime: original.view.firstInputTime,
                flutterBuildTime: nil,
                flutterRasterTime: nil,
                frozenFrame: .init(count: 0),
                frustration: .init(count: 0),
                id: original.view.id,
                inForegroundPeriods: original.view.inForegroundPeriods,
                isActive: false,
                isSlowRendered: false,
                jsRefreshRate: nil,
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
    }

    /// Creates new RUM view event.
    private func createNewRUMViewEvent(
        named viewName: String,
        url viewURL: String,
        startDate: Date,
        sessionUUID: RUMUUID,
        context: CrashContext,
        hasReplay: Bool?
    ) -> RUMViewEvent {
        let viewUUID = uuidGenerator.generateUnique()

        return RUMViewEvent(
            dd: .init(
                browserSdkVersion: nil,
                documentVersion: 1,
                session: .init(plan: .plan1)
            ),
            application: .init(
                id: applicationID
            ),
            ciTest: CITestIntegration.active?.rumCITest,
            connectivity: RUMConnectivity(
                networkInfo: context.networkConnectionInfo,
                carrierInfo: context.carrierInfo
            ),
            context: nil,
            date: startDate.timeIntervalSince1970.toInt64Milliseconds,
            device: .init(device: context.device),
            display: nil,
            // RUMM-2197: In very rare cases, the OS info computed below might not be exactly the one
            // that the app crashed on. This would correspond to a scenario when the device OS was upgraded
            // before restarting the app after crash. To solve this, the OS information would have to be
            // persisted in `crashContext` the same way as we do for other dynamic information.
            os: .init(device: context.device),
            service: context.service,
            session: .init(
                hasReplay: hasReplay,
                id: sessionUUID.toRUMDataFormat,
                type: CITestIntegration.active != nil ? .ciTest : .user
            ),
            source: .init(rawValue: context.source) ?? .ios,
            synthetics: nil,
            usr: context.userInfo.map { RUMUser(userInfo: $0) },
            version: context.version,
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
                firstByte: nil,
                firstContentfulPaint: nil,
                firstInputDelay: nil,
                firstInputTime: nil,
                flutterBuildTime: nil,
                flutterRasterTime: nil,
                frozenFrame: .init(count: 0),
                frustration: .init(count: 0),
                id: viewUUID.toRUMDataFormat,
                inForegroundPeriods: nil,
                isActive: false, // we know it won't receive updates
                isSlowRendered: false,
                jsRefreshRate: nil,
                largestContentfulPaint: nil,
                loadEvent: nil,
                loadingTime: nil,
                loadingType: nil,
                longTask: .init(count: 0),
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
    }
}

/// `Encodable` representation of RUM Error event for crash.
/// Mutable properties are subject of sanitization or data scrubbing.
/// TODO: RUMM-1949 - Remove `RUMCrashEvent` with generated model.
internal struct RUMCrashEvent: RUMDataModel {
    /// The actual RUM event model created by `RUMMonitor`
    var model: RUMErrorEvent

    /// Error attributes. Only set when `DM == RUMErrorEvent` and error describes a crash.
    /// Can be entirely removed when RUMM-1463 is resolved and error values are part of the `RUMErrorEvent`.
    let additionalAttributes: [String: Encodable]?

    /// Creates a RUM Event object object based on the given sanitizable model.
    ///
    /// The error attributes keys must be prefixed by `error.*`.
    ///
    /// - Parameters:
    ///   - model: The sanitizable event model.
    ///   - errorAttributes: The optional error attributes.
    init(error: RUMErrorEvent, additionalAttributes: [String: Encodable]? = nil) {
        self.model = error
        self.additionalAttributes = additionalAttributes
    }

    func encode(to encoder: Encoder) throws {
        // Encode attributes
        var container = encoder.container(keyedBy: DynamicCodingKey.self)

        // TODO: RUMM-1463 Remove this `errorAttributes` property once new error format is managed through `RUMDataModels`
        try additionalAttributes?.forEach { attribute in
            try container.encode(AnyEncodable(attribute.value), forKey: DynamicCodingKey(attribute.key))
        }

        // Encode the sanitized `RUMErrorEvent`.
        try model.encode(to: encoder)
    }

    init(from decoder: Decoder) throws {
        self.model = try RUMErrorEvent(from: decoder)

        // Decode other properties into additionalAttributes
        let dynamicContainer = try decoder.container(keyedBy: DynamicCodingKey.self)
        let dynamicKeys = dynamicContainer.allKeys.filter { RUMErrorEvent.CodingKeys(rawValue: $0.stringValue) == nil }
        var dictionary: [String: Codable] = [:]

        try dynamicKeys.forEach { codingKey in
            dictionary[codingKey.stringValue] = try dynamicContainer.decode(AnyCodable.self, forKey: codingKey)
        }

        self.additionalAttributes = dictionary
    }
}

extension RUMCrashEvent: RUMSanitizableEvent {
    var usr: RUMUser? {
        get { model.usr }
        set { model.usr = newValue }
    }

    var context: RUMEventAttributes? {
        get { model.context }
        set { model.context = newValue }
    }
}
