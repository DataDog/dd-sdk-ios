/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Creates V2 Storage configuration for V1 Tracing.
internal func createV2TracingStorageConfiguration() -> FeatureStorageConfiguration {
    return FeatureStorageConfiguration(
        directories: .init(
            authorized: "tracing/v2", // relative to `CoreDirectory.coreDirectory`
            unauthorized: "tracing/intermediate-v2", // relative to `CoreDirectory.coreDirectory`
            deprecated: [
                "com.datadoghq.traces", // relative to `CoreDirectory.osDirectory`
            ]
        ),
        featureName: "tracing"
    )
}

/// Creates V2 Upload configuration for V1 Tracing.
internal func createV2TracingUploadConfiguration(v1Configuration: FeaturesConfiguration.Tracing) -> FeatureV1UploadConfiguration {
    return FeatureV1UploadConfiguration(
        featureName: "tracing",
        requestBuilder: TracingRequestBuilder(intake: v1Configuration.uploadURL)
    )
}

/// The Tracing URL Request Builder for formatting and configuring the `URLRequest`
/// to upload traces data.
internal struct TracingRequestBuilder: FeatureRequestBuilder {
    /// The tracing intake.
    let intake: URL

    /// The tracing request body format.
    let format = DataFormat(prefix: "", suffix: "", separator: "\n")

    func request(for events: [Data], with context: DatadogContext) -> URLRequest {
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

        let data = format.format(events)
        return builder.uploadRequest(with: data)
    }
}
