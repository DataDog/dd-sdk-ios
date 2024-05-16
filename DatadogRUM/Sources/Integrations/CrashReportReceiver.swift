/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Receiver to consume crash reports as RUM events.
internal struct CrashReportReceiver: FeatureMessageReceiver {
    /// Defines keys referencing Crash message on the bus.
    enum MessageKeys {
        /// The key references a crash message.
        static let crash = "crash"
    }

    struct Crash: Decodable {
        /// The crash report.
        let report: DDCrashReport
        /// The crash context
        let context: CrashContext
    }

    struct CrashContext: Decodable {
        /// The Application launch date
        let appLaunchDate: Date?
        /// Interval between device and server time.
        let serverTimeOffset: TimeInterval
        /// The name of the service that data is generated from.
        let service: String
        /// Current device information.
        let device: DeviceInfo
        /// The version of the application that data is generated from.
        let version: String
        /// The build Id of the applicaiton that data is generated from
        let buildId: String?
        /// The build number of the application that data is generated from.
        let buildNumber: String
        /// Denotes the mobile application's platform, such as `"ios"` or `"flutter"` that data is generated from.
        let source: String
        /// The last RUM view in crashed app process.
        var lastRUMViewEvent: RUMViewEvent?
        /// State of the last RUM session in crashed app process.
        var lastRUMSessionState: RUMSessionState?
        /// The last global RUM attributes in crashed app process.
        var lastRUMAttributes: GlobalRUMAttributes?
        /// The last _"Is app in foreground?"_ information from crashed app process.
        let lastIsAppInForeground: Bool
        /// Network information.
        ///
        /// Represents the current state of the device network connectivity and interface.
        /// The value can be `unknown` if the network interface is not available or if it has not
        /// yet been evaluated.
        let networkConnectionInfo: NetworkConnectionInfo?
        /// Carrier information.
        ///
        /// Represents the current telephony service info of the device.
        /// This value can be `nil` of no service is currently registered, or if the device does
        /// not support telephony services.
        let carrierInfo: CarrierInfo?
        /// Current user information.
        let userInfo: UserInfo?
    }

    private struct AdjustedCrashTimings {
        /// Crash date read from `CrashReport`. It uses device time.
        let crashDate: Date
        /// Crash date adjusted with current time correction. It uses NTP time.
        let realCrashDate: Date
        /// Current time, adjusted with NTP correction.
        let realDateNow: Date
        /// Time between crash and application launch
        let timeSinceAppStart: TimeInterval?
    }

    /// RUM feature scope.
    let featureScope: FeatureScope
    let applicationID: String
    let dateProvider: DateProvider
    let sessionSampler: Sampler
    let trackBackgroundEvents: Bool
    let uuidGenerator: RUMUUIDGenerator
    /// Integration with CIApp tests. It contains the CIApp test context when active.
    let ciTest: RUMCITest?
    /// Integration with Synthetics tests. It contains the Synthetics test context when active.
    let syntheticsTest: RUMSyntheticsTest?
    let eventsMapper: RUMEventsMapper

    // MARK: - Initialization

    init(
        featureScope: FeatureScope,
        applicationID: String,
        dateProvider: DateProvider,
        sessionSampler: Sampler,
        trackBackgroundEvents: Bool,
        uuidGenerator: RUMUUIDGenerator,
        ciTest: RUMCITest?,
        syntheticsTest: RUMSyntheticsTest?,
        eventsMapper: RUMEventsMapper
    ) {
        self.featureScope = featureScope
        self.applicationID = applicationID
        self.dateProvider = dateProvider
        self.sessionSampler = sessionSampler
        self.trackBackgroundEvents = trackBackgroundEvents
        self.uuidGenerator = uuidGenerator
        self.ciTest = ciTest
        self.syntheticsTest = syntheticsTest
        self.eventsMapper = eventsMapper
    }

    func receive(message: FeatureMessage, from core: DatadogCoreProtocol) -> Bool {
        do {
            guard let crash: Crash = try message.baggage(forKey: MessageKeys.crash) else {
                return false
            }

            return send(report: crash.report, with: crash.context)
        } catch {
            featureScope.telemetry
                .error("Fails to decode crash from RUM", error: error)
        }

        return false
    }

    private func send(report: DDCrashReport, with context: CrashContext) -> Bool {
        // The `crashReport.crashDate` uses system `Date` collected at the moment of crash, so we need to adjust it
        // to the server time before processing. Following use of the current correction is not ideal (it's not the correction
        // from the moment of crash), but this is the best approximation we can get.
        let currentTimeCorrection = context.serverTimeOffset

        let crashDate = report.date ?? dateProvider.now
        var timeSinceAppStart: TimeInterval? = nil
        if let startDate = context.appLaunchDate {
            timeSinceAppStart = crashDate.timeIntervalSince(startDate)
        }

        let adjustedCrashTimings = AdjustedCrashTimings(
            crashDate: crashDate,
            realCrashDate: crashDate.addingTimeInterval(currentTimeCorrection),
            realDateNow: dateProvider.now.addingTimeInterval(currentTimeCorrection),
            timeSinceAppStart: timeSinceAppStart
        )

        // RUMM-2516 if a cross-platform crash was reported, do not send its native version
        if var lastRUMViewEvent = context.lastRUMViewEvent {
            if let lastRUMAttributes = context.lastRUMAttributes {
                // RUM-3588: If last RUM attributes are available, use them to replace view attributes as we know that
                // global RUM attributes can be updated more often than attributes in `lastRUMView`.
                // See https://github.com/DataDog/dd-sdk-ios/pull/1834 for more context.
                lastRUMViewEvent.context?.contextInfo = lastRUMAttributes.attributes
            }
            if lastRUMViewEvent.view.crash?.count ?? 0 < 1 {
                sendCrashReportLinkedToLastViewInPreviousSession(
                    report,
                    lastRUMViewEventInPreviousSession: lastRUMViewEvent,
                    using: adjustedCrashTimings
                )
            } else {
                DD.logger.debug("There was a crash in previous session, but it is ignored due to another crash already present in the last view.")
                return false
            }
        } else if let lastRUMSessionState = context.lastRUMSessionState {
            sendCrashReportToPreviousSession(report, crashContext: context, lastRUMSessionStateInPreviousSession: lastRUMSessionState, using: adjustedCrashTimings)
        } else if sessionSampler.sample() { // before producing a new RUM session, we must consider sampling
            sendCrashReportToNewSession(report, crashContext: context, using: adjustedCrashTimings)
        } else {
            DD.logger.debug("There was a crash in previous session, but it is ignored due to sampling.")
            return false
        }

        return true
    }

    /// If the crash occurred in an existing RUM session and we know its `lastRUMViewEvent` we send the error using that session UUID and link
    /// the crash to that view. The error event can be preceded with a view update based on `Constants.viewEventAvailabilityThreshold` condition.
    private func sendCrashReportLinkedToLastViewInPreviousSession(
        _ crashReport: DDCrashReport,
        lastRUMViewEventInPreviousSession lastRUMViewEvent: RUMViewEvent,
        using crashTimings: AdjustedCrashTimings
    ) {
        if crashTimings.realDateNow.timeIntervalSince(crashTimings.realCrashDate) < FatalErrorBuilder.Constants.viewEventAvailabilityThreshold {
            send(crashReport: crashReport, to: lastRUMViewEvent, using: crashTimings)
        } else {
            // We know it is too late for sending RUM view to previous RUM session as it is now stale on backend.
            // To avoid inconsistency, we only send the RUM error.
            DD.logger.debug("Sending crash as RUM error.")
            featureScope.eventWriteContext(bypassConsent: true) { context, writer in
                let builder = createFatalErrorBuilder(context: context, crash: crashReport, crashDate: crashTimings.realCrashDate, timeSinceAppStart: crashTimings.timeSinceAppStart)
                let rumError = builder.createRUMError(with: lastRUMViewEvent)

                if let mappedError = self.eventsMapper.map(event: rumError) {
                    writer.write(value: mappedError)
                } else {
                    DD.logger.warn("errorEventMapper returned 'nil' for a crash. Discarding crashes is not supported. The unmodified event will be sent.")
                    writer.write(value: rumError)
                }
            }
        }
    }

    /// If the crash occurred in an existing RUM session and we know its `lastRUMSessionState` but there was no `lastRUMViewEvent` we can
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
            isBETEnabled: trackBackgroundEvents
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
            // It means that the crash occurred as the very first event after sending app to background in previous session.
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
            send(crashReport: crashReport, to: newRUMView, using: crashTimings)
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
            isBETEnabled: trackBackgroundEvents
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
                // As the crash occurred after initializing SDK but before starting the first view,
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
                // As the crash occurred after initializing SDK but before starting the first view,
                // we can't know if Session Replay was configured. However, lack of view implies
                // that there must be no replay collected:
                hasReplay: false
            )
        case .doNotHandle:
            DD.logger.debug("There was a crash in background, but it is ignored due to Background Event Tracking disabled.")
            newRUMView = nil
        }

        if let newRUMView = newRUMView {
            send(crashReport: crashReport, to: newRUMView, using: crashTimings)
        }
    }

    /// Sends given `CrashReport` by linking it to given `rumView` and updating view counts accordingly.
    private func send(crashReport: DDCrashReport, to rumView: RUMViewEvent, using crashTimings: AdjustedCrashTimings) {
        DD.logger.debug("Updating RUM view with crash report.")

        // crash reporting is considering the user consent from previous session, if an event reached
        // the message bus it means that consent was granted and we can safely bypass current consent.
        featureScope.eventWriteContext(bypassConsent: true) { context, writer in
            let builder = createFatalErrorBuilder(context: context, crash: crashReport, crashDate: crashTimings.realCrashDate, timeSinceAppStart: crashTimings.timeSinceAppStart)
            let updatedRUMView = builder.updateRUMViewWithError(rumView)
            let rumError = builder.createRUMError(with: updatedRUMView)

            if let mappedError = self.eventsMapper.map(event: rumError) {
                writer.write(value: mappedError)
            } else {
                DD.logger.warn("errorEventMapper returned 'nil' for a crash. Discarding crashes is not supported. The unmodified event will be sent.")
                writer.write(value: rumError)
            }
            if let mappedView = self.eventsMapper.map(event: updatedRUMView) {
                writer.write(value: self.eventsMapper.map(event: mappedView))
            }
        }
    }

    // MARK: - Building RUM events

    private func createFatalErrorBuilder(context: DatadogContext, crash: DDCrashReport, crashDate: Date, timeSinceAppStart: TimeInterval?) -> FatalErrorBuilder {
        return FatalErrorBuilder(
            context: context,
            error: .crash,
            errorDate: crashDate,
            errorType: crash.type,
            errorMessage: crash.message,
            errorStack: crash.stack,
            errorThreads: crash.threads.toRUMDataFormat,
            errorBinaryImages: crash.binaryImages.toRUMDataFormat,
            errorWasTruncated: crash.wasTruncated,
            errorMeta: crash.meta.toRUMDataFormat,
            timeSinceAppStart: timeSinceAppStart
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
                configuration: .init(
                    sessionReplaySampleRate: nil,
                    sessionSampleRate: Double(self.sessionSampler.samplingRate),
                    startSessionReplayRecordingManually: nil
                ),
                documentVersion: 1,
                pageStates: nil,
                replayStats: nil,
                session: .init(
                    plan: .plan1,
                    sessionPrecondition: nil
                )
            ),
            application: .init(
                id: applicationID
            ),
            buildId: context.buildId,
            buildVersion: context.buildNumber,
            ciTest: ciTest,
            connectivity: RUMConnectivity(
                networkInfo: context.networkConnectionInfo,
                carrierInfo: context.carrierInfo
            ),
            container: nil,
            // RUM-3588: We know that last RUM view is not available, so we're creating a new one. No matter that, try using last
            // RUM attributes if available. There is a chance of having them as global RUM attributes can be updated more often than RUM view.
            // See https://github.com/DataDog/dd-sdk-ios/pull/1834 for more context.
            context: context.lastRUMAttributes.map { .init(contextInfo: $0.attributes) },
            date: startDate.timeIntervalSince1970.toInt64Milliseconds,
            device: .init(device: context.device, telemetry: featureScope.telemetry),
            display: nil,
            // RUMM-2197: In very rare cases, the OS info computed below might not be exactly the one
            // that the app crashed on. This would correspond to a scenario when the device OS was upgraded
            // before restarting the app after crash. To solve this, the OS information would have to be
            // persisted in `crashContext` the same way as we do for other dynamic information.
            os: .init(device: context.device),
            privacy: nil,
            service: context.service,
            session: .init(
                hasReplay: hasReplay,
                id: sessionUUID.toRUMDataFormat,
                isActive: true,
                sampledForReplay: nil,
                type: ciTest != nil ? .ciTest : (syntheticsTest != nil ? .synthetics : .user)
            ),
            source: .init(rawValue: context.source) ?? .ios,
            synthetics: syntheticsTest,
            usr: context.userInfo.map { RUMUser(userInfo: $0) },
            version: context.version,
            view: .init(
                action: .init(count: 0),
                cpuTicksCount: nil,
                cpuTicksPerSecond: nil,
                crash: .init(count: 0),
                cumulativeLayoutShift: nil,
                cumulativeLayoutShiftTargetSelector: nil,
                customTimings: nil,
                domComplete: nil,
                domContentLoaded: nil,
                domInteractive: nil,
                error: .init(count: 0),
                firstByte: nil,
                firstContentfulPaint: nil,
                firstInputDelay: nil,
                firstInputTargetSelector: nil,
                firstInputTime: nil,
                flutterBuildTime: nil,
                flutterRasterTime: nil,
                frozenFrame: .init(count: 0),
                frustration: .init(count: 0),
                id: viewUUID.toRUMDataFormat,
                inForegroundPeriods: nil,
                interactionToNextPaint: nil,
                interactionToNextPaintTargetSelector: nil,
                isActive: false, // we know it won't receive updates
                isSlowRendered: false,
                jsRefreshRate: nil,
                largestContentfulPaint: nil,
                largestContentfulPaintTargetSelector: nil,
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
