/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// The RUM context received from `Core`.
public struct RUMCoreContext: AdditionalContext, Equatable {
    /// RUM key in core additional context.
    public static let key = "rum"
    /// Current RUM application ID - standard UUID string, lowercased.
    public let applicationID: String
    /// Current RUM session ID - standard UUID string, lowercased.
    public let sessionID: String
    /// Current RUM view ID - standard UUID string, lowercased. It can be empty when view is being loaded.
    public let viewID: String?
    /// The ID of current RUM action (standard UUID `String`, lowercased).
    public let userActionID: String?
    /// Current view related server time offset
    public let viewServerTimeOffset: TimeInterval?
    /// The deterministic sampler for the current RUM session, carrying the session seed and rate.
    /// Consumers use `sessionSampler.combined(with: childRate).sample()` to apply
    /// child-rate correction without UUID parsing.
    public let sessionSampler: DeterministicSampler

    /// Creates a RUM context.
    ///
    /// - Parameters:
    ///   - applicationID: Current RUM application ID - standard UUID string, lowercased.
    ///   - sessionID: Current RUM session ID - standard UUID string, lowercased.
    ///   - sessionSampler: The deterministic sampler used to sample the RUM session.
    ///   - viewID: Current RUM view ID - standard UUID string, lowercased. It can be empty when view is being loaded.
    ///   - userActionID: The ID of current RUM action (standard UUID `String`, lowercased).
    ///   - viewServerTimeOffset: Current view related server time offset
    public init(
        applicationID: String,
        sessionID: String,
        sessionSampler: DeterministicSampler,
        viewID: String? = nil,
        userActionID: String? = nil,
        viewServerTimeOffset: TimeInterval? = nil
    ) {
        self.applicationID = applicationID
        self.sessionID = sessionID
        self.sessionSampler = sessionSampler
        self.viewID = viewID
        self.userActionID = userActionID
        self.viewServerTimeOffset = viewServerTimeOffset
    }
}

extension RUMCoreContext {
    /// RUM attributes keys shared with other Features registered in core.
    public enum IDs {
        /// The ID of RUM application (`String`).
        public static let applicationID = "application.id"

        /// The ID of current RUM session (standard UUID `String`, lowercased).
        public static let sessionID = "session.id"

        /// The ID of current RUM view (standard UUID `String`, lowercased).
        public static let viewID = "view.id"

        /// The name of current RUM view.
        public static let viewName = "view.name"

        /// The ID of current RUM action (standard UUID `String`, lowercased).
        public static let userActionID = "user_action.id"

        /// The ID of current RUM vital (standard UUID `String`, lowercased).
        public static let vitalID = "vital.id"

        /// The name of current RUM vital.
        public static let vitalLabel = "vital.label"

        /// The ID of current RUM error (standard UUID `String`, lowercased).
        public static let errorID = "error.id"

        /// The ID of current RUM long task (standard UUID `String`, lowercased).
        public static let longTaskID = "long_task.id"
    }
}
