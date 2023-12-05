/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// RUM Attributes shared with other Feature registered in core.
internal enum RUMContextAttributes {
    internal enum IDs {
        /// The ID of RUM application (`String`).
        internal static let applicationID = "application.id"

        /// The ID of current RUM session (standard UUID `String`, lowercased).
        /// In case the session is rejected (not sampled), RUM context is set to empty (`[:]`) in core.
        internal static let sessionID = "session.id"

        /// The ID of current RUM view (standard UUID `String`, lowercased).
        internal static let viewID = "view.id"

        /// The ID of current RUM action (standard UUID `String`, lowercased).
        internal static let userActionID = "user_action.id"
    }

    /// Key that aggregates the dictionary of all the RUM context IDs.
    internal static let ids = "ids"

    /// Server time offset of current RUM view used for date correction.
    internal static let serverTimeOffset = "server_time_offset"
}

/// The RUM context received from `DatadogCore`.
internal struct RUMCoreContext: Codable {
    enum CodingKeys: String, CodingKey {
        case applicationID = "application.id"
        case sessionID = "session.id"
        case viewID = "view.id"
        case userActionID = "user_action.id"
        case viewServerTimeOffset = "server_time_offset"
    }

    /// Current RUM application ID - standard UUID string, lowecased.
    let applicationID: String
    /// Current RUM session ID - standard UUID string, lowecased.
    let sessionID: String
    /// Current RUM view ID - standard UUID string, lowecased. It can be empty when view is being loaded.
    let viewID: String?
    /// The ID of current RUM action (standard UUID `String`, lowercased).
    let userActionID: String?
    /// Current view related server time offset
    let viewServerTimeOffset: TimeInterval?
}
