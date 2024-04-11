/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Builder for constructing fatal errors (such as Crashes or Fatal App Hangs) that can be sent to the last RUM session in previous process.
internal struct FatalErrorBuilder {
    struct Constants {
        /// Maximum time since the occurrence of fatal error enabling us to send the RUM view event to associate it with the interrupted RUM session:
        /// * if the app is restarted earlier than the date of fatal error + this interval, then we send both the `RUMErrorEvent` and `RUMViewEvent`,
        /// * if the app is restarted later than the date of fatal error + this interval, then we only send `RUMErrorEvent`.
        ///
        /// This condition originates from RUM backend constraints on processing `RUMViewEvents` in stale sessions. If the session does not
        /// receive any updates for a long time, then sending some significantly later may lead to inconsistency.
        static let viewEventAvailabilityThreshold: TimeInterval = 14_400 // 4 hours
    }

    enum FatalError {
        /// A crash with given metadata information.
        case crash
        /// A fatal App Hang.
        case hang
    }

    /// Current SDK context.
    let context: DatadogContext

    let error: FatalError

    let errorDate: Date
    let errorType: String
    let errorMessage: String
    let errorStack: String

    let errorThreads: [RUMErrorEvent.Error.Threads]?
    let errorBinaryImages: [RUMErrorEvent.Error.BinaryImages]?
    let errorWasTruncated: Bool?
    let errorMeta: RUMErrorEvent.Error.Meta?

    /// Creates RUM error linked to given view.
    func createRUMError(with lastRUMView: RUMViewEvent) -> RUMErrorEvent {
        let event = RUMErrorEvent(
            dd: .init(
                browserSdkVersion: nil,
                configuration: lastRUMView.dd.configuration.map {
                    .init(
                        sessionReplaySampleRate: $0.sessionReplaySampleRate,
                        sessionSampleRate: $0.sessionSampleRate
                    )
                },
                session: .init(
                    plan: .plan1,
                    sessionPrecondition: lastRUMView.dd.session?.sessionPrecondition
                )
            ),
            action: nil,
            application: .init(id: lastRUMView.application.id),
            buildId: lastRUMView.buildId,
            buildVersion: lastRUMView.buildVersion,
            ciTest: lastRUMView.ciTest,
            connectivity: lastRUMView.connectivity,
            container: nil,
            context: lastRUMView.context,
            date: errorDate.timeIntervalSince1970.toInt64Milliseconds,
            device: lastRUMView.device,
            display: nil,
            error: .init(
                binaryImages: errorBinaryImages,
                category: {
                    switch error {
                    case .crash: return .exception
                    case .hang: return .appHang
                    }
                }(),
                handling: nil,
                handlingStack: nil,
                id: nil,
                isCrash: {
                    switch error {
                    case .crash: return true
                    case .hang: return true // fatal hangs are considered `@error.is_crash: true`
                    }
                }(),
                message: errorMessage,
                meta: errorMeta,
                resource: nil,
                source: .source,
                sourceType: context.nativeSourceOverride.map { RUMErrorSourceType(rawValue: $0) } ?? .ios,
                stack: errorStack,
                threads: errorThreads,
                type: errorType,
                wasTruncated: errorWasTruncated
            ),
            freeze: nil, // `@error.freeze.duration` is not yet supported for fatal App Hangs
            os: lastRUMView.os,
            service: lastRUMView.service,
            session: .init(
                hasReplay: lastRUMView.session.hasReplay,
                id: lastRUMView.session.id,
                type: lastRUMView.session.type
            ),
            source: lastRUMView.source?.toErrorEventSource ?? .ios,
            synthetics: lastRUMView.synthetics,
            usr: lastRUMView.usr,
            version: lastRUMView.version,
            view: .init(
                id: lastRUMView.view.id,
                inForeground: nil,
                name: lastRUMView.view.name,
                referrer: lastRUMView.view.referrer,
                url: lastRUMView.view.url
            )
        )

        return event
    }

    /// Updates given RUM view with fatal error information.
    func updateRUMViewWithError(_ original: RUMViewEvent) -> RUMViewEvent {
        return RUMViewEvent(
            dd: .init(
                browserSdkVersion: original.dd.browserSdkVersion,
                configuration: original.dd.configuration,
                documentVersion: original.dd.documentVersion + 1,
                pageStates: original.dd.pageStates,
                replayStats: original.dd.replayStats,
                session: original.dd.session
            ),
            application: original.application,
            buildId: original.buildId,
            buildVersion: original.buildVersion,
            ciTest: original.ciTest,
            connectivity: original.connectivity,
            container: original.container,
            context: original.context,
            date: errorDate.timeIntervalSince1970.toInt64Milliseconds - 1, // -1ms to put the fatal error after view in RUM session
            device: original.device,
            display: original.display,
            os: original.os,
            privacy: original.privacy,
            service: original.service,
            session: original.session,
            source: original.source ?? .ios,
            synthetics: original.synthetics,
            usr: original.usr,
            version: original.version,
            view: .init(
                action: original.view.action,
                cpuTicksCount: original.view.cpuTicksCount,
                cpuTicksPerSecond: original.view.cpuTicksPerSecond,
                crash: .init(
                    count: {
                        switch error {
                        case .crash: return 1
                        case .hang: return 1 // fatal hangs are considered in `@view.crash.count`
                        }
                    }()
                ),
                cumulativeLayoutShift: original.view.cumulativeLayoutShift,
                cumulativeLayoutShiftTargetSelector: original.view.cumulativeLayoutShiftTargetSelector,
                customTimings: original.view.customTimings,
                domComplete: original.view.domComplete,
                domContentLoaded: original.view.domContentLoaded,
                domInteractive: original.view.domInteractive,
                error: .init(
                    count: original.view.error.count + 1 // count the new error
                ),
                firstByte: original.view.firstByte,
                firstContentfulPaint: original.view.firstContentfulPaint,
                firstInputDelay: original.view.firstInputDelay,
                firstInputTargetSelector: original.view.firstInputTargetSelector,
                firstInputTime: original.view.firstInputTime,
                flutterBuildTime: original.view.flutterBuildTime,
                flutterRasterTime: original.view.flutterRasterTime,
                frozenFrame: original.view.frozenFrame,
                frustration: original.view.frustration,
                id: original.view.id,
                inForegroundPeriods: original.view.inForegroundPeriods,
                interactionToNextPaint: original.view.interactionToNextPaint,
                interactionToNextPaintTargetSelector: original.view.interactionToNextPaintTargetSelector,
                isActive: false, // after fatal error, this is no longer active view
                isSlowRendered: original.view.isSlowRendered,
                jsRefreshRate: original.view.jsRefreshRate,
                largestContentfulPaint: original.view.largestContentfulPaint,
                largestContentfulPaintTargetSelector: original.view.largestContentfulPaintTargetSelector,
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
}
