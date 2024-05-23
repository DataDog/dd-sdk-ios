/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// An object tracking the state of RUM session and exporting attributes for "RUM Session Ended" telemetry.
internal final class SessionEndedMetric {
    /// Definition of fields in "RUM Session Ended" telemetry, following the "RUM Session Ended" telemetry spec.
    internal enum Constants {
        /// The name of this metric, included in telemetry log.
        /// Note: the "[Mobile Metric]" prefix is added when sending this telemetry in RUM.
        static let name = "RUM Session Ended"
        /// Metric type value.
        static let typeValue = "rum session ended"
        /// Namespace for bundling metric attributes ("rse" = "RUM Session Ended").
        static let rseKey = "rse"
        /// Key referencing the session ID (`String`) that the metric refers to.
        static let sessionIDKey = "sessionID"
    }

    /// An ID of the session being tracked through this metric object.
    private let sessionID: String

    /// The type of OS component where the session was tracked.
    private let bundleType: BundleType

    /// The session precondition that led to the creation of this session.
    private let precondition: RUMSessionPrecondition?

    private struct TrackedViewInfo {
        let viewURL: String
        let startMs: Int64
        var durationNs: Int64

        // TODO: RUM-4591 Track diagnostic attributes:
        // - `instrumentationType`: manual | uikit | swiftui
    }

    /// Stores information about tracked views, referencing them by their view ID.
    @ReadWriteLock
    private var trackedViews: [String: TrackedViewInfo] = [:]

    /// Info about the first tracked view.
    @ReadWriteLock
    private var firstTrackedView: TrackedViewInfo?

    /// Info about the last tracked view.
    @ReadWriteLock
    private var lastTrackedView: TrackedViewInfo?

    /// Tracks the number of SDK errors by their kind.
    @ReadWriteLock
    private var trackedSDKErrors: [String: Int] = [:]

    /// Indicates if the session was stopped through `stopSession()` API.
    @ReadWriteLock
    private var wasStopped: Bool = false

    // TODO: RUM-4591 Track diagnostic attributes:
    // - no_view_events_count
    // - has_background_events_tracking_enabled
    // - has_replay
    // - ntp_offset

    // MARK: - Tracking Metric State

    /// Initializer.
    /// - Parameters:
    ///   - sessionID: An ID of the session that is being tracked with this metric.
    ///   - precondition: The precondition that led to starting this session.
    ///   - context: The SDK context at the moment of starting this session.
    init(
        sessionID: String,
        precondition: RUMSessionPrecondition?,
        context: DatadogContext
    ) {
        self.sessionID = sessionID
        self.bundleType = context.applicationBundleType
        self.precondition = precondition
    }

    /// Tracks the view event that occurred during the session.
    func track(view: RUMViewEvent) {
        guard view.session.id == sessionID else {
            return // sanity check, unexpected
        }

        var info = trackedViews[view.view.id] ?? TrackedViewInfo(
            viewURL: view.view.url,
            startMs: view.date,
            durationNs: view.view.timeSpent
        )

        info.durationNs = view.view.timeSpent
        trackedViews[view.view.id] = info

        if firstTrackedView == nil {
            firstTrackedView = info
        }
        lastTrackedView = info
    }

    /// Tracks the kind of SDK error that occurred during the session.
    func track(sdkErrorKind: String) {
        if let count = trackedSDKErrors[sdkErrorKind] {
            trackedSDKErrors[sdkErrorKind] = count + 1
        } else {
            trackedSDKErrors[sdkErrorKind] = 1
        }
    }

    /// Signals that the session was stopped with `stopSession()` API.
    func trackWasStopped() {
        wasStopped = true
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
        /// The session's duration, calculated from view events.
        ///
        /// This calculation only includes view events that are written to disk, with no consideration if the I/O operation
        /// has succeeded or not. Views dropped through the mapper API are not included in this duration.
        ///
        /// Note: It becomes `nil` if no views were tracked in this session.
        let duration: Int64?
        /// Indicates if the session was stopped through `stopSession()` API.
        let wasStopped: Bool

        struct ViewsCount: Encodable {
            /// The number of distinct views (view UUIDs) sent during this session.
            let total: Int
            /// The number of standard "Background" views tracked during this session.
            let background: Int
            /// The number of standard "ApplicationLaunch" views tracked during this session (sanity check: we expect `0` or `1`).
            let applicationLaunch: Int

            enum CodingKeys: String, CodingKey {
                case total
                case background
                case applicationLaunch = "app_launch"
            }
        }

        let viewsCount: ViewsCount

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

        enum CodingKeys: String, CodingKey {
            case processType = "process_type"
            case precondition
            case duration
            case wasStopped = "was_stopped"
            case viewsCount = "views_count"
            case sdkErrorsCount = "sdk_errors_count"
        }
    }

    /// Exports metric attributes for `Telemetry.metric(name:attributes:)`.
    func asMetricAttributes() -> [String: Encodable] {
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

        // Compute SDK errors count
        let totalSDKErrors = trackedSDKErrors.count
        let top5SDKErrorsByKind = top5SDKErrorsByKind(from: trackedSDKErrors)

        return [
            SDKMetricFields.typeKey: Constants.typeValue,
            Constants.sessionIDKey: sessionID,
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
                viewsCount: .init(
                    total: totalViewsCount,
                    background: backgroundViewsCount,
                    applicationLaunch: appLaunchViewsCount
                ),
                sdkErrorsCount: .init(
                    total: totalSDKErrors,
                    byKind: top5SDKErrorsByKind
                )
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
