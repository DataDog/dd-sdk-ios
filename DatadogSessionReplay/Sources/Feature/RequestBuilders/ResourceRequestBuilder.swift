/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation
import DatadogInternal

internal struct ResourceRequestBuilder: FeatureRequestBuilder {
    /// Custom URL for uploading data to.
    let customUploadURL: URL?
    /// Sends telemetry through sdk core.
    let telemetry: Telemetry
    /// Builds multipart form for request's body.
    let multipartBuilder: MultipartFormDataBuilder

    init(
        customUploadURL: URL?,
        telemetry: Telemetry,
        multipartBuilder: MultipartFormDataBuilder = MultipartFormData()
    ) {
        self.customUploadURL = customUploadURL
        self.telemetry = telemetry
        self.multipartBuilder = multipartBuilder
    }

    func request(
        for events: [Event],
        with context: DatadogContext,
        execution: ExecutionContext
    ) throws -> URLRequest {
        var tags = [
            "retry_count:\(execution.attempt + 1)"
        ]

        if let previousResponseCode = execution.previousResponseCode {
            tags.append("last_failure_status:\(previousResponseCode)")
        }

        let decoder = JSONDecoder()
        let resources = try events.map { event in
            try decoder.decode(EnrichedResource.self, from: event.data)
        }
        return try createRequest(resources: resources, context: context, tags: tags)
    }

    private func createRequest(resources: [EnrichedResource], context: DatadogContext, tags: [String]) throws -> URLRequest {
        var multipart = multipartBuilder

        let builder = URLRequestBuilder(
            url: url(with: context),
            queryItems: [
                .ddtags(tags: tags)
            ],
            headers: [
                .contentTypeHeader(contentType: .multipartFormData(boundary: multipart.boundary)),
                .userAgentHeader(
                    appName: context.applicationName,
                    appVersion: context.version,
                    device: context.device,
                    os: context.os
                ),
                .ddAPIKeyHeader(clientToken: context.clientToken),
                .ddEVPOriginHeader(source: context.source),
                .ddEVPOriginVersionHeader(sdkVersion: context.sdkVersion),
                .ddRequestIDHeader(),
            ],
            telemetry: telemetry
        )

        resources.forEach {
            multipart.addFormData(
                name: "image",
                filename: $0.identifier,
                data: $0.data,
                mimeType: "image/png"
            )
        }
        if let context = resources.first?.context {
            let data = try JSONEncoder().encode(context)
            multipart.addFormData(
                name: "event",
                filename: "blob",
                data: data,
                mimeType: "application/json"
            )
        }

        return builder.uploadRequest(with: multipart.build(), compress: true)
    }

    private func url(with context: DatadogContext) -> URL {
        customUploadURL ?? context.site.endpoint.appendingPathComponent("api/v2/replay")
    }
}
#endif
