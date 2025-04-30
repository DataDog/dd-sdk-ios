/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Defines types that are sent by RUM on the message-bus.
public enum RUMPayloadMessages {
    /// Message to send when RUM view is reset.
    public static let viewReset = "rum-view-reset"
}

/// Lightweight representation of current RUM session state, used to compute `RUMOffViewEventsHandlingRule`.
/// It gets serialized into fatal error context for computing the rule upon app process restart.
public struct RUMSessionState: Equatable, Codable {
    /// The session ID. Can be `.nullUUID` if the session was rejected by sampler.
    public let sessionUUID: UUID
    /// If this is the very first session in the app process (`true`) or was re-created upon timeout (`false`).
    public let isInitialSession: Bool
    /// If this session has ever tracked any view (used to reason about "application launch" events).
    public let hasTrackedAnyView: Bool
    /// If there was a Session Replay recording pending at the moment of starting this session (`nil` if SR Feature was not configured).
    public let didStartWithReplay: Bool?

    /// Creates a RUM Session State
    /// - Parameters:
    ///   - sessionUUID: The session ID. Can be `.nullUUID` if the session was rejected by sampler.
    ///   - isInitialSession: If this is the very first session in the app process (`true`) or was re-created upon timeout (`false`).
    ///   - hasTrackedAnyView: If this session has ever tracked any view (used to reason about "application launch" events).
    ///   - didStartWithReplay: If there was a Session Replay recording pending at the moment of starting this session (`nil` if SR Feature was not configured).
    public init(
        sessionUUID: UUID,
        isInitialSession: Bool,
        hasTrackedAnyView: Bool,
        didStartWithReplay: Bool?
    ) {
        self.sessionUUID = sessionUUID
        self.isInitialSession = isInitialSession
        self.hasTrackedAnyView = hasTrackedAnyView
        self.didStartWithReplay = didStartWithReplay
    }
}
