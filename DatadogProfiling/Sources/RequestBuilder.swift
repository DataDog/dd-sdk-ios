/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal struct RequestBuilder: FeatureRequestBuilder {
    /// Builds multipart form for request's body.
    let multipartBuilder: MultipartFormDataBuilder

    /// Custom URL for uploading data to.
    let customUploadURL: URL?

    /// Sends telemetry through sdk core.
    let telemetry: Telemetry

    init(
        multipartBuilder: MultipartFormDataBuilder = MultipartFormData(),
        customUploadURL: URL? = nil,
        telemetry: Telemetry = NOPTelemetry()
    ) {
        self.multipartBuilder = multipartBuilder
        self.customUploadURL = customUploadURL
        self.telemetry = telemetry
    }

    func request(for events: [Event], with context: DatadogContext, execution: ExecutionContext) throws -> URLRequest {
        guard events.count == 1, let prof = events.first else {
            throw ProgrammerError(description: "Invalid event count: \(events.count)")
        }

        guard let event = prof.metadata else {
            throw ProgrammerError(description: "Profile must include an event metadata")
        }

        var multipart = multipartBuilder

        multipart.addFormData(
            name: "event",
            filename: ProfileEvent.Constants.eventFilename,
            data: event,
            mimeType: "application/json"
        )

        let decoder = JSONDecoder()

        try multipart.addFormData(
            name: ProfileEvent.Constants.wallFilename,
            filename: ProfileEvent.Constants.wallFilename,
            data: decoder.decode(Data.self, from: prof.data),
            mimeType: "application/octet-stream"
        )

        var tags = ["retry_count:\(execution.attempt + 1)"]
        if let previousResponseCode = execution.previousResponseCode {
            tags.append("last_failure_status:\(previousResponseCode)")
        }

        let builder = URLRequestBuilder(
            url: url(with: context),
            queryItems: [
                .ddtags(tags: tags)
            ],
            headers: [
                .contentTypeHeader(contentType: .multipartFormData(boundary: multipart.boundary)),
                .userAgentHeader(appName: context.applicationName, appVersion: context.version, device: context.device),
                .ddAPIKeyHeader(clientToken: context.clientToken),
                .ddEVPOriginHeader(source: context.source),
                .ddEVPOriginVersionHeader(sdkVersion: context.sdkVersion),
                .ddRequestIDHeader(),
            ],
            telemetry: telemetry
        )

        return builder.uploadRequest(with: multipart.build(), compress: false)
    }

    private func url(with context: DatadogContext) -> URL {
        customUploadURL ?? context.site.endpoint.appendingPathComponent("api/v2/profile")
    }
}
