/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation
import DatadogInternal

internal struct SegmentRequestBuilder: FeatureRequestBuilder {
    private static let newlineByte = "\n".data(using: .utf8)! // swiftlint:disable:this force_unwrapping

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

        guard !events.isEmpty else {
            throw InternalError(description: "[SR] batch events must not be empty.")
        }

        let source = SRSegment.Source(rawValue: context.source) ?? {
            telemetry.error("[SR] Could not create segment source from provided string '\(context.source)'")
            return .ios
        }()

        // If we can't decode `events: [Data]` there is no way to recover, so we throw an
        // error to let the core delete the batch:
        let segments = try events
            .map { try SegmentJSON($0.data, source: source) }
            .merge()

        return try createRequest(segments: segments, context: context, tags: tags)
    }

    private func createRequest(segments: [SegmentJSON], context: DatadogContext, tags: [String]) throws -> URLRequest {
        var multipart = multipartBuilder

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

        let metadata = try segments.enumerated().map { index, segment in
            var json = segment.toJSONObject()
            // Session Replay BE accepts compressed segment data followed by newline character (before compression):
            let data = try JSONSerialization.data(withJSONObject: json) + SegmentRequestBuilder.newlineByte
            let compressedData = try SRCompression.compress(data: data)
            // Compressed segment is sent within multipart form data - with some of segment (metadata)
            // attributes listed as form fields:
            multipart.addFormData(
                name: "segment",
                filename: "file\(index)",
                data: compressedData,
                mimeType: "application/octet-stream"
            )
            // Remove the 'records' for the metadata
            json["records"] = nil
            json["raw_segment_size"] = data.count
            json["compressed_segment_size"] = compressedData.count
            return json
        }

        let data = try JSONSerialization.data(withJSONObject: metadata)
        multipart.addFormData(
            name: "event",
            filename: "blob",
            data: data,
            mimeType: "application/json"
        )

        // Data is already compressed, so request building request w/o compression:
        return builder.uploadRequest(with: multipart.build(), compress: false)
    }

    private func url(with context: DatadogContext) -> URL {
        customUploadURL ?? context.site.endpoint.appendingPathComponent("api/v2/replay")
    }
}

#endif
