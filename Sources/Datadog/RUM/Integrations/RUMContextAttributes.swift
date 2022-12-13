/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// RUM Attributes shared with other Feature registered in core.
internal enum RUMContextAttributes {
    /// The ID of RUM application (`String`).
    internal static let applicationID = "application_id"

    /// The ID of current RUM session (standard UUID `String`, lowercased).
    /// In case the session is rejected (not sampled), RUM context is set to empty (`[:]`) in core.
    internal static let sessionID = "session_id"

    /// The ID of current RUM view (standard UUID `String`, lowercased).
    internal static let viewID = "view.id"

    /// The ID of current RUM action (standard UUID `String`, lowercased).
    internal static let userActionID = "user_action.id"
}
