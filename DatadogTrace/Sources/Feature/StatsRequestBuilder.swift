/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Builds URL requests for uploading client-side stats payloads to `/api/v0.2/stats`.
///
/// The final implementation will encode payloads as MessagePack. For now the stub
/// uses JSON so we can validate the pipeline end-to-end.
internal struct StatsRequestBuilder: FeatureRequestBuilder {
    let customIntakeURL: URL?
    let telemetry: Telemetry

    func request(
        for events: [Event],
        with context: DatadogContext,
        execution: ExecutionContext
    ) throws -> URLRequest {
        let builder = URLRequestBuilder(
            url: url(with: context),
            queryItems: [],
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
                .ddRequestIDHeader(),
            ],
            telemetry: telemetry
        )

        let data = events.reduce(Data()) { $0 + $1.data }
        return builder.uploadRequest(with: data)
    }

    private func url(with context: DatadogContext) -> URL {
        customIntakeURL ?? context.site.endpoint.appendingPathComponent("api/v0.2/stats")
    }
}
