/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// The Logging URL Request Builder for formatting and configuring the `URLRequest`
/// to upload logs data.
internal struct RequestBuilder: FeatureRequestBuilder {
    /// A custom logs intake.
    let customIntakeURL: URL?

    /// The logs request body format.
    let format = DataFormat(prefix: "[", suffix: "]", separator: ",")

    /// Telemetry interface.
    let telemetry: Telemetry

    init(
        customIntakeURL: URL? = nil,
        telemetry: Telemetry = NOPTelemetry()
    ) {
        self.customIntakeURL = customIntakeURL
        self.telemetry = telemetry
    }

    func request(
        for events: [Event],
        with context: DatadogContext,
        execution: ExecutionContext
    ) -> URLRequest {
        let builder = URLRequestBuilder(
            url: url(with: context),
            queryItems: [
                .ddsource(source: context.source),
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
                .ddRequestIDHeader(),
            ],
            telemetry: telemetry
        )

        let data = format.format(events.map { $0.data })
        return builder.uploadRequest(with: data)
    }

    private func url(with context: DatadogContext) -> URL {
        customIntakeURL ?? context.site.endpoint.appendingPathComponent("api/v2/logs")
    }
}
