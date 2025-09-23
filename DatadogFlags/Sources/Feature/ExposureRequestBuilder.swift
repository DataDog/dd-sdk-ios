/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal struct ExposureRequestBuilder: FeatureRequestBuilder {
    /// A custom RUM intake.
    let customIntakeURL: URL?
    /// Telemetry interface.
    let telemetry: Telemetry

    func request(for events: [Event], with context: DatadogContext, execution: ExecutionContext) throws -> URLRequest {
        guard let exposureEventData = events.first?.data else {
            throw InternalError(description: "Found no event in Flags batch")
        }

        let builder = URLRequestBuilder(
            url: url(with: context),
            queryItems: [
                .ddsource(source: context.source)
            ],
            headers: [
                .contentTypeHeader(contentType: .applicationJSON),
                .userAgentHeader(
                    appName: context.applicationName,
                    appVersion: context.version,
                    device: context.device,
                    os: context.os
                ),
                .ddAPIKeyHeader(clientToken: context.clientToken),
                .ddEVPOriginHeader(source: context.ciAppOrigin ?? context.source),
                .ddEVPOriginVersionHeader(sdkVersion: context.sdkVersion),
                .ddRequestIDHeader()
            ],
            telemetry: telemetry
        )

        return builder.uploadRequest(with: exposureEventData, compress: false)
    }

    private func url(with context: DatadogContext) -> URL {
        customIntakeURL ?? context.site.endpoint.appendingPathComponent("api/v2/exposures")
    }
}
