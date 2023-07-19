/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Creates Tracing Feature Configuration.
///
/// - Parameter intake: The Tracing intake URL.
/// - Returns: The Tracing feature configuration.
internal func createTracingConfiguration(intake: URL) -> DatadogFeatureConfiguration {
    return DatadogFeatureConfiguration(
        name: "tracing",
        requestBuilder: TracingRequestBuilder(intake: intake),
        messageReceiver: TracingMessageReceiver()
    )
}

internal func mapInternalTags(_ originalTag: String) -> String {
    switch originalTag {
    case "application.id":
        return "_dd.application.id"
    case "session.id":
        return "_dd.session.id"
    case "view.id":
        return "_dd.view.id"
    case "user_action.id":
        return "_dd.action.id"
    default:
        return originalTag
    }
}

/// The Tracing URL Request Builder for formatting and configuring the `URLRequest`
/// to upload traces data.
internal struct TracingRequestBuilder: FeatureRequestBuilder {
    /// The tracing intake.
    let intake: URL

    /// The tracing request body format.
    let format = DataFormat(prefix: "", suffix: "", separator: "\n")

    func request(for events: [Event], with context: DatadogContext) -> URLRequest {
        let builder = URLRequestBuilder(
            url: intake,
            queryItems: [],
            headers: [
                .contentTypeHeader(contentType: .textPlainUTF8),
                .userAgentHeader(
                    appName: context.applicationName,
                    appVersion: context.version,
                    device: context.device
                ),
                .ddAPIKeyHeader(clientToken: context.clientToken),
                .ddEVPOriginHeader(source: context.ciAppOrigin ?? context.source),
                .ddEVPOriginVersionHeader(sdkVersion: context.sdkVersion),
                .ddRequestIDHeader(),
            ]
        )

        let data = format.format(events.map { $0.data })
        return builder.uploadRequest(with: data)
    }
}

internal struct TracingMessageReceiver: FeatureMessageReceiver {
    /// Tracks RUM context to be associated with spans.
    let rum = TracingWithRUMIntegration()

    /// Process messages receives from the bus.
    ///
    /// - Parameters:
    ///   - message: The Feature message
    ///   - core: The core from which the message is transmitted.
    func receive(message: FeatureMessage, from core: DatadogCoreProtocol) -> Bool {
        switch message {
        case .context(let context):
            return update(context: context)
        default:
            return false
        }
    }

    /// Updates RUM attributes of the `Global.sharedTracer` if available.
    ///
    /// - Parameter context: The updated core context.
    private func update(context: DatadogContext) -> Bool {
        if let attributes: [String: String?] = context.featuresAttributes["rum"]?.ids {
            let attributes = attributes.compactMapValues { $0 }
            let mappedAttribues = Dictionary(uniqueKeysWithValues: attributes.map { key, value in (mapInternalTags(key), value) })

            rum.attributes = mappedAttribues
            return true
        }
        return false
    }
}
