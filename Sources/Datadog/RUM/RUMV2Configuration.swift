/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Creates RUM Feature Configuration.
///
/// - Parameter intake: The RUM intake URL.
/// - Returns: The RUM feature configuration.
internal func createRUMConfiguration(configuration: FeaturesConfiguration.RUM) -> DatadogFeatureConfiguration {
    return DatadogFeatureConfiguration(
        name: "rum",
        requestBuilder: RUMRequestBuilder(intake: configuration.uploadURL),
        messageReceiver: CombinedFeatureMessageReceiver(
            ErrorMessageReceiver(),
            WebViewEventReceiver(
                dateProvider: configuration.dateProvider
            ),
            CrashReportReceiver(
                applicationID: configuration.applicationID,
                dateProvider: configuration.dateProvider,
                sessionSampler: configuration.sessionSampler,
                backgroundEventTrackingEnabled: configuration.backgroundEventTrackingEnabled,
                uuidGenerator: configuration.uuidGenerator
            )
        )
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
        var tags = [
            "service:\(context.service)",
            "version:\(context.version)",
            "sdk_version:\(context.sdkVersion)",
            "env:\(context.env)",
        ]

        if let variant = context.variant {
            tags.append("variant:\(variant)")
        }

        let builder = URLRequestBuilder(
            url: intake,
            queryItems: [
                .ddsource(source: context.source),
                .ddtags(tags: tags)
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

/// Defines keys referencing RUM baggage in `DatadogContext.featuresAttributes`.
internal enum RUMBaggageKeys {
    /// The key references RUM view event.
    /// The view event associated with the key conforms to `Codable`.
    static let viewEvent = "view-event"

    /// The key references a `true` value if the RUM view is reset.
    static let viewReset = "view-reset"

    /// The key references RUM session state.
    /// The state associated with the key conforms to `Codable`.
    static let sessionState = "session-state"
}

internal struct ErrorMessageReceiver: FeatureMessageReceiver {
    /// Adds RUM Error with given message and stack to current RUM View.
    func receive(message: FeatureMessage, from core: DatadogCoreProtocol) -> Bool {
        guard
            case let .error(message, attributes) = message,
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
