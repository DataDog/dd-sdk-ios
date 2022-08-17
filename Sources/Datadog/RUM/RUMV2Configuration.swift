/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Creates RUM Feature Configuration.
///
/// - Parameter intake: The RUM intake URL.
/// - Returns: The RUM feature configuration.
internal func createRUMConfiguration(intake: URL) -> DatadogFeatureConfiguration {
    return DatadogFeatureConfiguration(
        name: "rum",
        requestBuilder: RUMRequestBuilder(intake: intake),
        messageReceiver: RUMMessageReceiver()
    )
}

/// The RUM URL Request Builder for formatting and configuring the `URLRequest`
/// to upload RUM data.
internal struct RUMRequestBuilder: FeatureRequestBuilder {
    /// The RUM intake.
    let intake: URL

    /// The RUM request body format.
    let format = DataFormat(prefix: "", suffix: "", separator: "\n")

    func request(for events: [Data], with context: DatadogContext) -> URLRequest {
        let builder = URLRequestBuilder(
            url: intake,
            queryItems: [
                .ddsource(source: context.source),
                .ddtags(
                    tags: [
                        "service:\(context.service)",
                        "version:\(context.version)",
                        "sdk_version:\(context.sdkVersion)",
                        "env:\(context.env)"
                    ]
                )
            ],
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

        let data = format.format(events)
        return builder.uploadRequest(with: data)
    }
}

internal struct RUMMessageReceiver: FeatureMessageReceiver {
    /// Process messages receives from the bus.
    ///
    /// - Parameters:
    ///   - message: The Feature message
    ///   - core: The core from which the message is transmitted.
    func receive(message: FeatureMessage, from core: DatadogCoreProtocol) -> Bool {
        switch message {
        case .error(let message, let attributes):
            return addError(message: message, attributes: attributes)
        default:
            return false
        }
    }

    /// Adds RUM Error with given message and stack to current RUM View.
    private func addError(message: String, attributes: FeatureMessageAttributes) -> Bool {
        guard
            let monitor = Global.rum as? RUMMonitor,
            let source = attributes["source", type: RUMInternalErrorSource.self]
        else {
            return false
        }

        monitor.addError(
            message: message,
            type: attributes["type"],
            stack: attributes["stack"],
            source: source,
            attributes: attributes["attributes"] ?? [:]
        )

        return true
    }
}
