/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal enum SessionEndedMetricError: Error, CustomStringConvertible {
    /// Indicates an attempt of tracking view event in session that shouldn't belong to.
    case trackingViewInForeignSession(viewURL: String, sessionID: RUMUUID)

    var description: String {
        switch self {
        case .trackingViewInForeignSession(let viewURL, let sessionID):
            let isAppLaunchView = viewURL == RUMOffViewEventsHandlingRule.Constants.applicationLaunchViewURL
            let isBackgroundView = viewURL == RUMOffViewEventsHandlingRule.Constants.backgroundViewURL
            let viewKind = isAppLaunchView ? "AppLaunch" : (isBackgroundView ? "Background" : "Custom")
            return "Attempted to track \(viewKind) view in session with different UUID \(sessionID)"
        }
    }
}

/// Tracks the state of RUM session and exports attributes for "RUM Session Ended" telemetry.
///
/// It is modeled as a reference type and contains mutable state. The thread safety for its mutations is
/// achieved by design: only `SessionEndedMetricController` interacts with this class and does
/// it through critical section each time.
internal class SessionEndedMetric {
    /// Definition of fields in "RUM Session Ended" telemetry, following the "RUM Session Ended" telemetry spec.
    internal enum Constants {
        /// The name of this metric, included in telemetry log.
        /// Note: the "[Mobile Metric]" prefix is added when sending this telemetry in RUM.
        static let name = "RUM Session Ended"
        /// Metric type value.
        static let typeValue = "rum session ended"
        /// Namespace for bundling metric attributes ("rse" = "RUM Session Ended").
        static let rseKey = "rse"
    }

   /// An ID of the session being tracked through this metric object.
    let sessionID: RUMUUID

    /// The type of OS component where the session was tracked.
    private let bundleType: BundleType

    /// The session precondition that led to the creation of this session.
    private let precondition: RUMSessionPrecondition?

    /// Tracks view information for certain `view.id`.
    private class TrackedViewInfo {
        /// The view URL as reported in RUM data.
        let viewURL: String
        /// The type of instrumentation that started this view.
        /// It can be `nil` if view was started implicitly by RUM, which is the case for "ApplicationLaunch" and "Background" views.
        let instrumentationType: InstrumentationType?
        /// The start of the view in milliseconds from from epoch.
        let startMs: Int64
        /// The duration of the view in nanoseconds.
        var durationNs: Int64
        /// If any of view updates to this `view.id` had `session.has_replay == true`.
        var hasReplay: Bool

        init(
            viewURL: String,
            instrumentationType: InstrumentationType?,
            startMs: Int64,
            durationNs: Int64,
            hasReplay: Bool
        ) {
            self.viewURL = viewURL
            self.instrumentationType = instrumentationType
            self.startMs = startMs
            self.durationNs = durationNs
            self.hasReplay = hasReplay
        }
    }

    /// Stores information about tracked views, referencing them by their `view.id`.
    private var trackedViews: [String: TrackedViewInfo] = [:]

    /// Info about the first tracked view.
    private var firstTrackedView: TrackedViewInfo?

    /// Info about the last tracked view.
    private var lastTrackedView: TrackedViewInfo?

    /// Stores information about tracked actions, referencing them by their instrumentation type.
    private var trackedActions: [String: Int] = [:]

    /// Tracks the number of SDK errors by their kind.
    private var trackedSDKErrors: [String: Int] = [:]

    /// Indicates if the session was stopped through `stopSession()` API.
    private var wasStopped = false

    /// Information about the upload quality during the session.
    private var uploadQuality: [String: Attributes.UploadQuality] = [:]

    /// If `RUM.Configuration.trackBackgroundEvents` was enabled for this session.
    private let tracksBackgroundEvents: Bool

    /// The current value of NTP offset at session start.
    private let ntpOffsetAtStart: TimeInterval

    /// Represents types of event that can be missed due to absence of an active RUM view.
    enum MissedEventType: String {
        case action
        case resource
        case error
        case longTask
        case viewLoadingTime
    }

    /// Tracks the number of RUM events missed due to absence of an active RUM view.
    private var missedEvents: [MissedEventType: Int] = [:]

    // MARK: - Tracking Metric State

    /// Initializer.
    /// - Parameters:
    ///   - sessionID: An ID of the session that is being tracked with this metric.
    ///   - precondition: The precondition that led to starting this session.
    ///   - context: The SDK context at the moment of starting this session.
    ///   - tracksBackgroundEvents: If background events tracking is enabled for this session.
    init(
        sessionID: RUMUUID,
        precondition: RUMSessionPrecondition?,
        context: DatadogContext,
        tracksBackgroundEvents: Bool
    ) {
        self.sessionID = sessionID
        self.bundleType = context.applicationBundleType
        self.precondition = precondition
        self.tracksBackgroundEvents = tracksBackgroundEvents
        self.ntpOffsetAtStart = context.serverTimeOffset
    }

    /// Tracks the view event that occurred during the session.
    /// - Parameters:
    ///   - view: the view event to track
    ///   - instrumentationType: the type of instrumentation used to start this view (only the first value for each `view.id` is tracked; succeeding values
    ///   will be ignored so it is okay to pass value on first call and then follow with `nil` for next updates of given `view.id`)
    func track(view: RUMViewEvent, instrumentationType: InstrumentationType?) throws {
        guard view.session.id == sessionID.toRUMDataFormat else {
            throw SessionEndedMetricError.trackingViewInForeignSession(viewURL: view.view.url, sessionID: sessionID)
        }

        let info: TrackedViewInfo

        if let existingInfo = trackedViews[view.view.id] {
            info = existingInfo
            info.durationNs = view.view.timeSpent
            info.hasReplay = info.hasReplay || (view.session.hasReplay ?? false)
        } else {
            info = TrackedViewInfo(
                viewURL: view.view.url,
                instrumentationType: instrumentationType,
                startMs: view.date,
                durationNs: view.view.timeSpent,
                hasReplay: view.session.hasReplay ?? false
            )
            trackedViews[view.view.id] = info
        }

        if firstTrackedView == nil {
            firstTrackedView = info
        }
        lastTrackedView = info
    }

    /// Tracks information about an action that occurred during the session.
    /// - Parameters:
    ///   - action: the action event to track
    ///   - instrumentationType: the type of instrumentation used to start this action
    func track(action: RUMActionEvent, instrumentationType: InstrumentationType?) {
        guard action.session.id == sessionID.toRUMDataFormat else {
            return
        }

        if let instrumentationType = instrumentationType {
            trackedActions[instrumentationType.metricKey] = (trackedActions[instrumentationType.metricKey] ?? 0) + 1
        }
    }

    /// Tracks the kind of SDK error that occurred during the session.
    /// - Parameter sdkErrorKind: the kind of SDK error
    func track(sdkErrorKind: String) {
        if let count = trackedSDKErrors[sdkErrorKind] {
            trackedSDKErrors[sdkErrorKind] = count + 1
        } else {
            trackedSDKErrors[sdkErrorKind] = 1
        }
    }

    /// Tracks an event missed due to absence of an active view.
    /// - Parameter missedEventType: the type of an event that was missed
    func track(missedEventType: MissedEventType) {
        if let count = missedEvents[missedEventType] {
            missedEvents[missedEventType] = count + 1
        } else {
            missedEvents[missedEventType] = 1
        }
    }

    /// Signals that the session was stopped with `stopSession()` API.
    func trackWasStopped() {
        wasStopped = true
    }

    /// Tracks the upload quality metric for aggregation.
    ///
    /// - Parameters:
    ///   - attributes: The upload quality attributes
    func track(uploadQuality attributes: [String: Encodable]) {
        guard let track = attributes[UploadQualityMetric.track] as? String else {
            return
        }

        let uploadQuality = self.uploadQuality[track] ?? Attributes.UploadQuality(
            cycleCount: 0,
            failureCount: [:],
            blockerCount: [:]
        )

        var failureCount = uploadQuality.failureCount
        var blockerCount = uploadQuality.blockerCount

        if let failure = attributes[UploadQualityMetric.failure] as? String {
            // Merge by incrementing values
            failureCount.merge([failure: 1], uniquingKeysWith: +)
        }

        if let blockers = attributes[UploadQualityMetric.blockers] as? [String] {
            // Merge by incrementing values
            blockerCount = blockers.reduce(into: blockerCount) { count, blocker in
                count[blocker, default: 0] += 1
            }
        }

        self.uploadQuality[track] = Attributes.UploadQuality(
            cycleCount: uploadQuality.cycleCount + 1,
            failureCount: failureCount,
            blockerCount: blockerCount
        )
    }

    // MARK: - Exporting Attributes

    /// Set of quality and diagnostic attributes for the Session Ended metric.
    internal struct Attributes: Encodable {
        /// The type of OS component where the session was tracked.
        let processType: String
        /// The precondition that led to the creation of this session.
        ///
        /// Note: We don't expect it to ever become `nil`, but optionality is enforced in upstream code.
        let precondition: String?
        /// The session's duration (in nanoseconds), calculated from view events.
        ///
        /// This calculation only includes view events that are written to disk, with no consideration if the I/O operation
        /// has succeeded or not. Views dropped through the mapper API are not included in this duration.
        ///
        /// Note: It becomes `nil` if no views were tracked in this session.
        let duration: Int64?
        /// Indicates if the session was stopped through `stopSession()` API.
        let wasStopped: Bool
        /// If background events tracking is enabled for this session.
        let hasBackgroundEventsTrackingEnabled: Bool

        struct ViewsCount: Encodable {
            /// The number of distinct views (view UUIDs) sent during this session.
            let total: Int
            /// The number of standard "Background" views tracked during this session.
            let background: Int
            /// The number of standard "ApplicationLaunch" views tracked during this session (sanity check: we expect `0` or `1`).
            let applicationLaunch: Int
            /// The map of view instrumentation types to the number of views tracked with each instrumentation.
            let byInstrumentation: [String: Int]
            /// The number of distinct views that had `has_replay == true` in any of their view events.
            let withHasReplay: Int

            enum CodingKeys: String, CodingKey {
                case total
                case background
                case applicationLaunch = "app_launch"
                case byInstrumentation = "by_instrumentation"
                case withHasReplay = "with_has_replay"
            }
        }

        let viewsCount: ViewsCount

        struct ActionsCount: Encodable {
            /// The number of distinct actions sent during this session.
            let total: Int
            /// The map of action instrumentation types to the number of actions tracked with each instrumentation.
            let byInstrumentation: [String: Int]

            enum CodingKeys: String, CodingKey {
                case total
                case byInstrumentation = "by_instrumentation"
            }
        }

        let actionsCount: ActionsCount

        struct SDKErrorsCount: Encodable {
            /// The total number of SDK errors that occurred during the session, excluding any effects from telemetry limits
            /// such as duplicate filtering or maximum caps.
            let total: Int
            /// The map of TOP 5 SDK error kinds to the number of their occurrences during the session.
            /// Error kinds may include characters illegal for being a JSON key, so they are escaped.
            let byKind: [String: Int]

            enum CodingKeys: String, CodingKey {
                case total
                case byKind = "by_kind"
            }
        }

        let sdkErrorsCount: SDKErrorsCount

        struct NTPOffset: Encodable {
            /// The NTP offset at session start, in milliseconds.
            let atStart: Int64
            /// The NTP offset at session end, in milliseconds.
            let atEnd: Int64

            enum CodingKeys: String, CodingKey {
                case atStart = "at_start"
                case atEnd = "at_end"
            }
        }

        /// NTP offset information tracked for this session.
        let ntpOffset: NTPOffset

        struct NoViewEventsCount: Encodable {
            /// Number of action events missed due to absence of an active view.
            let actions: Int
            /// Number of resource events missed due to absence of an active view.
            let resources: Int
            /// Number of error events missed due to absence of an active view.
            let errors: Int
            /// Number of long task events missed due to absence of an active view.
            let longTasks: Int

            enum CodingKeys: String, CodingKey {
                case actions
                case resources
                case errors
                case longTasks = "long_tasks"
            }
        }

        /// Information on number of events missed due to absence of an active view.
        let noViewEventsCount: NoViewEventsCount

        struct UploadQuality: Encodable {
            let cycleCount: Int
            let failureCount: [String: Int]
            let blockerCount: [String: Int]

            enum CodingKeys: String, CodingKey {
                case cycleCount = "cycle_count"
                case failureCount = "failure_count"
                case blockerCount = "blocker_count"
            }
        }

        /// Information about the upload quality during the session.
        /// The upload quality is splitting between upload track name.
        /// Tracks upload quality during the session, aggregating them by track name.
        /// Each track reports its own upload quality metrics.
        let uploadQuality: [String: UploadQuality]

        enum CodingKeys: String, CodingKey {
            case processType = "process_type"
            case precondition
            case duration
            case wasStopped = "was_stopped"
            case hasBackgroundEventsTrackingEnabled = "has_background_events_tracking_enabled"
            case viewsCount = "views_count"
            case actionsCount = "actions_count"
            case sdkErrorsCount = "sdk_errors_count"
            case ntpOffset = "ntp_offset"
            case noViewEventsCount = "no_view_events_count"
            case uploadQuality = "upload_quality"
        }
    }

    /// Exports metric attributes for `Telemetry.metric(name:attributes:)`. This method is expected to be called
    /// at session end with providing the SDK `context` valid at the moment of call.
    ///
    /// - Parameter context: the SDK context valid at the moment of this call
    /// - Returns: metric attributes
    func asMetricAttributes(with context: DatadogContext) -> [String: Encodable] {
        // Compute duration
        var durationNs: Int64?
        if let firstView = firstTrackedView, let lastView = lastTrackedView {
            let endOfLastViewNs = lastView.startMs.msToNs.addingReportingOverflow(lastView.durationNs).partialValue
            durationNs = endOfLastViewNs.subtractingReportingOverflow(firstView.startMs.msToNs).partialValue
        }

        // Compute views count
        let totalViewsCount = trackedViews.count
        let backgroundViewsCount = trackedViews.values.filter({ $0.viewURL == RUMOffViewEventsHandlingRule.Constants.backgroundViewURL }).count
        let appLaunchViewsCount = trackedViews.values.filter({ $0.viewURL == RUMOffViewEventsHandlingRule.Constants.applicationLaunchViewURL }).count
        var byInstrumentationViewsCount: [String: Int] = [:]
        trackedViews.values.forEach {
            if let instrumentationType = $0.instrumentationType {
                byInstrumentationViewsCount[instrumentationType.metricKey] = (byInstrumentationViewsCount[instrumentationType.metricKey] ?? 0) + 1
            }
        }
        let totalActionsCount = trackedActions.values.reduce(0, +)
        let withHasReplayCount = trackedViews.values.reduce(0, { acc, next in acc + (next.hasReplay ? 1 : 0) })

        // Compute SDK errors count
        let totalSDKErrors = trackedSDKErrors.values.reduce(0, +)
        let top5SDKErrorsByKind = top5SDKErrorsByKind(from: trackedSDKErrors)

        return [
            SDKMetricFields.typeKey: Constants.typeValue,
            SDKMetricFields.sessionIDOverrideKey: sessionID.toRUMDataFormat,
            Constants.rseKey: Attributes(
                processType: {
                    switch bundleType {
                    case .iOSApp: return "app"
                    case .iOSAppExtension: return "extension"
                    }
                }(),
                precondition: precondition?.rawValue,
                duration: durationNs,
                wasStopped: wasStopped,
                hasBackgroundEventsTrackingEnabled: tracksBackgroundEvents,
                viewsCount: .init(
                    total: totalViewsCount,
                    background: backgroundViewsCount,
                    applicationLaunch: appLaunchViewsCount,
                    byInstrumentation: byInstrumentationViewsCount,
                    withHasReplay: withHasReplayCount
                ),
                actionsCount: .init(
                    total: totalActionsCount,
                    byInstrumentation: trackedActions
                ),
                sdkErrorsCount: .init(
                    total: totalSDKErrors,
                    byKind: top5SDKErrorsByKind
                ),
                ntpOffset: .init(
                    atStart: ntpOffsetAtStart.toInt64Milliseconds,
                    atEnd: context.serverTimeOffset.toInt64Milliseconds
                ),
                noViewEventsCount: .init(
                    actions: missedEvents[.action] ?? 0,
                    resources: missedEvents[.resource] ?? 0,
                    errors: missedEvents[.error] ?? 0,
                    longTasks: missedEvents[.longTask] ?? 0
                ),
                uploadQuality: uploadQuality
            )
        ]
    }

    /// Returns the top 5 SDK errors with escaping their error kind.
    /// - Parameter sdkErrors: All SDK errors.
    /// - Returns: Top 5 errors with their count.
    private func top5SDKErrorsByKind(from sdkErrors: [String: Int]) -> [String: Int] {
        /// Replaces all non-alpanumeric characters with `_` (underscore).
        func escapeNonAlphanumericCharacters(_ string: String) -> String {
            let escaped = string.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : "_" }
            return String(escaped)
        }

        let sortedEntries = sdkErrors.sorted { $0.value > $1.value }
        let top5Entries = sortedEntries.prefix(5)
        var top5: [String: Int] = [:]
        for (key, value) in top5Entries {
            top5[escapeNonAlphanumericCharacters(key)] = value
        }
        return top5
    }
}

// MARK: - Helpers

private extension Int64 {
    /// Converts timestamp represented in milliseconds to nanoseconds with preventing Int64 overflow.
    var msToNs: Int64 { multipliedReportingOverflow(by: 1_000_000).partialValue }
}

extension InstrumentationType: Encodable {
    var metricKey: String {
        switch self {
        case .uikit: return "uikit"
        case .swiftuiAutomatic: return "swiftuiAutomatic"
        case .swiftui: return "swiftui"
        case .manual: return "manual"
        }
    }
}
