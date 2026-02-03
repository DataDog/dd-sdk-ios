/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// The RUM URL Request Builder for formatting and configuring the `URLRequest`
/// to upload RUM data.
internal struct RequestBuilder: FeatureRequestBuilder {
    /// A custom RUM intake.
    let customIntakeURL: URL?

    /// The RUM view events filter from the payload.
    let eventsFilter: RUMViewEventsFilter

    /// The RUM request body format.
    let format = DataFormat(prefix: "", suffix: "", separator: "\n")

    /// Telemetry interface.
    let telemetry: Telemetry

    func request(
        for events: [Event],
        with context: DatadogContext,
        execution: ExecutionContext
    ) throws -> URLRequest {
        var tags = ["retry_count:\(execution.attempt + 1)"]
        if let previousResponseCode = execution.previousResponseCode {
            tags.append("last_failure_status:\(previousResponseCode)")
        }

        let filteredEvents = eventsFilter.filter(events: events)

        guard !filteredEvents.isEmpty else {
            throw InternalError(description: "All \(events.count) RUM events were filtered out, resulting in empty payload")
        }

        let data = format.format(filteredEvents.map { $0.data })

        let builder = URLRequestBuilder(
            url: url(with: context),
            queryItems: [
                .ddsource(source: context.source),
                .ddtags(tags: tags)
            ],
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
                .ddIdempotencyKeyHeader(key: data.sha1())
            ],
            telemetry: telemetry
        )

        return builder.uploadRequest(with: data)
    }

    private func url(with context: DatadogContext) -> URL {
        customIntakeURL ?? context.site.endpoint.appendingPathComponent("api/v2/rum")
    }
}
