/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// The Tracing URL Request Builder for formatting and configuring the `URLRequest`
/// to upload traces data.
internal struct TracingRequestBuilder: FeatureRequestBuilder {
    /// The tracing intake.
    let customIntakeURL: URL?

    /// The tracing request body format.
    let format = DataFormat(prefix: "", suffix: "", separator: "\n")

    /// Telemetry interface.
    let telemetry: Telemetry

    func request(
        for events: [Event],
        with context: DatadogContext,
        execution: ExecutionContext
    ) -> URLRequest {
        let builder = URLRequestBuilder(
            url: url(with: context),
            queryItems: [],
            headers: [
                .contentTypeHeader(contentType: .textPlainUTF8),
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

        let data = format.format(events.map { $0.data })
        return builder.uploadRequest(with: data)
    }

    func url(with context: DatadogContext) -> URL {
        customIntakeURL ?? context.site.endpoint.appendingPathComponent("api/v2/spans")
    }
}
