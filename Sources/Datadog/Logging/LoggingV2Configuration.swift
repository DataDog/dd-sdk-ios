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
            authorized: "com.datadoghq.logs/v2",
            unauthorized: "com.datadoghq.logs/intermediate-v2",
            deprecated: [
                "com.datadoghq.logs/v1",
                "com.datadoghq.logs/intermediate-v1",
            ]
        ),
        featureName: "logging"
    )
}

/// Creates V2 Upload configuration for V1 Logging.
internal func createV2LoggingUploadConfiguration(v1Configuration: FeaturesConfiguration.Logging) -> FeatureUploadConfiguration {
    return FeatureUploadConfiguration(
        featureName: "logging",
        createRequestBuilder: { v1Context, telemetry in
            return RequestBuilder(
                url: v1Configuration.uploadURL,
                queryItems: [
                    .ddsource(source: v1Context.source)
                ],
                headers: [
                    .contentTypeHeader(contentType: .applicationJSON),
                    .userAgentHeader(
                        appName: v1Context.applicationName,
                        appVersion: v1Context.version,
                        device: v1Context.mobileDevice
                    ),
                    .ddAPIKeyHeader(clientToken: v1Context.clientToken),
                    .ddEVPOriginHeader(source: v1Context.ciAppOrigin ?? v1Context.source),
                    .ddEVPOriginVersionHeader(sdkVersion: v1Context.sdkVersion),
                    .ddRequestIDHeader(),
                ],
                telemetry: telemetry
            )
        },
        payloadFormat: DataFormat(prefix: "[", suffix: "]", separator: ",")
    )
}
