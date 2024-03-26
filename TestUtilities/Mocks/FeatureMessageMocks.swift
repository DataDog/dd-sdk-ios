/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

public extension Array where Element == FeatureMessage {
    /// Unpacks the first "baggage message" with given key in this array.
    func firstBaggage(withKey key: String) -> FeatureBaggage? {
        return compactMap({ $0.asBaggage }).filter({ $0.key == key }).first?.baggage
    }

    /// Unpacks the last "baggage message" with given key in this array.
    func lastBaggage(withKey key: String) -> FeatureBaggage? {
        return compactMap({ $0.asBaggage }).filter({ $0.key == key }).last?.baggage
    }

    /// Unpacks the first "baggage message" with given key in this array.
    var firstWebViewMessage: WebViewMessage? {
        return lazy.compactMap { $0.asWebViewMessage }.first
    }

    /// Unpacks the first "context message" in this array.
    func firstContext() -> DatadogContext? {
        return compactMap({ $0.asContext }).first
    }

    /// Unpacks the first "telemetry message" in this array.
    func firstContext() -> TelemetryMessage? {
        return compactMap({ $0.asTelemetry }).first
    }
}

public extension FeatureMessage {
    /// Extracts baggage attributes from feature message.
    var asBaggage: (key: String, baggage: FeatureBaggage)? {
        guard case let .baggage(key, baggage) = self else {
            return nil
        }
        return (key: key, baggage: baggage)
    }

    /// Extracts baggage attributes from feature message.
    var asWebViewMessage: WebViewMessage? {
        guard case let .webview(message) = self else {
            return nil
        }
        return message
    }

    /// Extracts context from feature message.
    var asContext: DatadogContext? {
        guard case let .context(context) = self else {
            return nil
        }
        return context
    }

    /// Extracts telemetry from feature message.
    var asTelemetry: TelemetryMessage? {
        guard case let .telemetry(telemetry) = self else {
            return nil
        }
        return telemetry
    }
}
