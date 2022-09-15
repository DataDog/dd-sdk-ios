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
internal func createV2RUMUploadConfiguration(v1Configuration: FeaturesConfiguration.RUM) -> FeatureUploadConfiguration {
    return FeatureUploadConfiguration(
        featureName: "RUM",
        createRequestBuilder: { v1Context in
            var tags = [
                "service:\(v1Context.service)",
                "version:\(v1Context.version)",
                "sdk_version:\(v1Context.sdkVersion)",
                "env:\(v1Context.env)",
            ]
            if let variant = v1Context.variant {
                tags.append("variant:\(variant)")
            }

            return RequestBuilder(
                url: v1Configuration.uploadURL,
                queryItems: [
                    .ddsource(source: v1Context.source),
                    .ddtags(
                        tags: tags
                    )
                ],
                headers: [
                    .contentTypeHeader(contentType: .textPlainUTF8),
                    .userAgentHeader(
                        appName: v1Context.applicationName,
                        appVersion: v1Context.version,
                        device: v1Context.device
                    ),
                    .ddAPIKeyHeader(clientToken: v1Context.clientToken),
                    .ddEVPOriginHeader(source: v1Context.ciAppOrigin ?? v1Context.source),
                    .ddEVPOriginVersionHeader(sdkVersion: v1Context.sdkVersion),
                    .ddRequestIDHeader(),
                ]
            )
        },
        payloadFormat: DataFormat(prefix: "", suffix: "", separator: "\n")
    )
}
