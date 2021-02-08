/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Describes current Datadog SDK context, so the app state information can be attached to
/// the crash report and retrieved back when the application is started again.
///
/// Note: as it gets saved along with the crash report during process interruption, it's good
/// to keep this data well-packed and as small as possible.
internal struct CrashContext: Codable {
    /// Codable representation of the public `TrackingConsent`.
    /// Uses `Int8` for optimized packing.
    enum TrackingConsent: Int8, Codable {
        case granted
        case notGranted
        case pending
    }

    /// Last value of `TrackingConsent`.
    var lastTrackingConsent: TrackingConsent
    /// Last RUM View event.
    var lastRUMViewEvent: RUMViewEvent?

    // TODO: RUMM-1049 Add Codable version of `UserInfo?`, `NetworkInfo?` and `CarrierInfo?`

    enum CodingKeys: String, CodingKey {
        case lastTrackingConsent = "ltc"
        case lastRUMViewEvent = "lre"
    }
}

// MARK: - Helpers

extension CrashContext.TrackingConsent {
    /// Maps `public TrackingConsent` to `CrashContext.TrackingConsent`.
    init(trackingConsent: TrackingConsent) {
        switch trackingConsent {
        case .granted: self = .granted
        case .notGranted: self = .notGranted
        case .pending: self = .pending
        }
    }
}
