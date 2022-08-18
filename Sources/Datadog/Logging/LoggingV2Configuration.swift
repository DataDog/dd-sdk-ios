/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Creates Logging Feature Configuration.
///
/// - Parameter intake: The Logging intake URL.
/// - Returns: The Logging feature configuration.
internal func createLoggingConfiguration(intake: URL) -> DatadogFeatureConfiguration {
    return DatadogFeatureConfiguration(
        name: "logging",
        requestBuilder: LoggingRequestBuilder(intake: intake),
        messageReceiver: NOPFeatureMessageReceiver()
    )
}

/// The Logging URL Request Builder for formatting and configuring the `URLRequest`
/// to upload logs data.
internal struct LoggingRequestBuilder: FeatureRequestBuilder {
    /// The logs intake.
    let intake: URL

    /// The logs request body format.
    let format = DataFormat(prefix: "[", suffix: "]", separator: ",")

    func request(for events: [Data], with context: DatadogContext) -> URLRequest {
        let builder = URLRequestBuilder(
            url: intake,
            queryItems: [
                .ddsource(source: context.source)
            ],
            headers: [
                .contentTypeHeader(contentType: .applicationJSON),
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
