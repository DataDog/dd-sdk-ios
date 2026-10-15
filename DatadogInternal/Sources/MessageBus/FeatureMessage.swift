/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// The set of messages that can be transmitted on the Features message bus.
public enum FeatureMessage {
    /// A custom payload message.
    case payload(Any)

    /// A web-view message.
    ///
    /// Represent a Browser SDK event sent through the JS bridge.
    case webview(WebViewMessage)

    /// Session Replay records produced by an embedded renderer.
    case embeddedContent(EmbeddedContentMessage)

    /// A core context message.
    ///
    /// The core will send updated context through the bus. Do not send new context values
    /// from a Feature or Integration.
    case context(DatadogContext)

    /// A telemetry message.
    ///
    /// The core can send telemetry data coming from all Features.
    case telemetry(TelemetryMessage)
}

/// In-process ownership for a flag evaluation emitted inside a trusted RUM handoff.
/// The envelope is never serialized and owns no core, feature, scene or view.
@_spi(Internal)
public struct RUMFlagEvaluationContextMessage {
    public let evaluation: RUMFlagEvaluationMessage
    private let owner: RUMContextHandoff.Owner
    private let capturedContext: RUMContextHandoff.CurrentValue

    /// A missing handoff keeps the legacy message's representative fallback.
    public init?(evaluation: RUMFlagEvaluationMessage, in scope: Any) {
        guard let owner = RUMContextHandoff.owner(in: scope),
              let context = RUMContextHandoff.current(for: owner) else {
            return nil
        }
        self.evaluation = evaluation
        self.owner = owner
        self.capturedContext = context
    }

    /// Nil rejects a foreign or retired core generation; it is not new inference.
    public func context(for owner: RUMContextHandoff.Owner?) -> RUMContextHandoff.CurrentValue? {
        guard owner === self.owner, self.owner.isValid else {
            return nil
        }
        return capturedContext
    }
}
