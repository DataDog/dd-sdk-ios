/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Creates V2 Storage configuration for V1 Logging.
internal func createV2LoggingStorageConfiguration() -> FeatureStorageConfiguration {
    return FeatureStorageConfiguration(
        directories: .init(
            authorized: "logging/v2", // relative to `CoreDirectory.coreDirectory`
            unauthorized: "logging/intermediate-v2", // relative to `CoreDirectory.coreDirectory`
            deprecated: [
                "com.datadoghq.logs", // relative to `CoreDirectory.osDirectory`
            ]
        ),
        featureName: "logging"
    )
}

/// Creates V2 Upload configuration for V1 Logging.
internal func createV2LoggingUploadConfiguration(v1Configuration: FeaturesConfiguration.Logging) -> FeatureV1UploadConfiguration {
    return FeatureV1UploadConfiguration(
        featureName: "logging",
        requestBuilder: LoggingRequestBuilder(intake: v1Configuration.uploadURL)
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
