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
public struct RUMSessionState: Codable, Equatable {
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

/// Error message consumed by RUM on the message-bus.
public struct RUMErrorMessage {
    /// The time of the error
    public let time: Date
    /// The RUM error message
    public let message: String
    /// The RUM error source
    public let source: String
    /// The RUM error type
    public let type: String?
    /// The RUM error stack
    public let stack: String?
    /// The RUM attributes
    public let attributes: [String: Encodable]
    /// Binary images if need to decode the stack trace
    public let binaryImages: [BinaryImage]?

    /// Create a Log error message to be sent on the message-bus.
    /// 
    /// - Parameters:
    ///   - time: The time of the error
    ///   - message: The RUM error message
    ///   - source: The RUM error source
    ///   - type: The RUM error type
    ///   - stack: The RUM error stack
    ///   - attributes: The RUM attributes
    ///   - binaryImages: Binary images if need to decode the stack trace
    public init(
        time: Date,
        message: String,
        source: String,
        type: String?,
        stack: String?,
        attributes: [String: Encodable],
        binaryImages: [BinaryImage]?
    ) {
        self.time = time
        self.message = message
        self.source = source
        self.type = type
        self.stack = stack
        self.attributes = attributes
        self.binaryImages = binaryImages
    }
}

/// Flag evaluation message consumed by RUM on the message-bus.
public struct RUMFlagEvaluationMessage {
    /// The flag key
    public let flagKey: String
    /// The evaluated value
    public let value: any Encodable

    /// Create a flag evaluation message to be sent on the message-bus.
    ///
    /// - Parameters:
    ///   - flagKey: The flag key
    ///   - value: The evaluated value
    public init(flagKey: String, value: any Encodable) {
        self.flagKey = flagKey
        self.value = value
    }
}
