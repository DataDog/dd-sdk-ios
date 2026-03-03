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
        guard events.count == 1, let event = events.first else {
            throw ProgrammerError(description: "Invalid event count: \(events.count)")
        }

        guard let metadataData = event.metadata else {
            throw ProgrammerError(description: "Profile must include an event metadata")
        }

        let decoder = JSONDecoder()
        let attachments = try decoder.decode(ProfileAttachments.self, from: metadataData)

        var multipart = multipartBuilder

        multipart.addFormData(
            name: "event",
            filename: ProfileAttachments.Constants.profileEventFilename,
            data: event.data,
            mimeType: "application/json"
        )

        multipart.addFormData(
            name: ProfileAttachments.Constants.wallFilename,
            filename: ProfileAttachments.Constants.wallFilename,
            data: attachments.pprof,
            mimeType: "application/octet-stream"
        )

        if let rumEvents = attachments.rumEvents {
            multipart.addFormData(
                name: ProfileAttachments.Constants.rumEventsFilename,
                filename: ProfileAttachments.Constants.rumEventsFilename,
                data: rumEvents,
                mimeType: "application/json"
            )
        }

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

        return builder.uploadRequest(with: multipart.build(), compress: true)
    }

    private func url(with context: DatadogContext) -> URL {
        customUploadURL ?? context.site.endpoint.appendingPathComponent("api/v2/profile")
    }
}
