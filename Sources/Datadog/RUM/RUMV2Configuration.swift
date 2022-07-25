/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Creates V2 Storage configuration for V1 RUM.
internal func createV2RUMStorageConfiguration() -> FeatureStorageConfiguration {
    return FeatureStorageConfiguration(
        directories: .init(
            authorized: "rum/v2", // relative to `CoreDirectory.coreDirectory`
            unauthorized: "rum/intermediate-v2", // relative to `CoreDirectory.coreDirectory`
            deprecated: [
                "com.datadoghq.rum", // relative to `CoreDirectory.osDirectory`
            ]
        ),
        featureName: "RUM"
    )
}

/// Creates V2 Upload configuration for V1 RUM.
internal func createV2RUMUploadConfiguration(v1Configuration: FeaturesConfiguration.RUM) -> FeatureV1UploadConfiguration {
    return FeatureV1UploadConfiguration(
        featureName: "RUM",
        requestBuilder: RUMRequestBuilder(intake: v1Configuration.uploadURL)
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
