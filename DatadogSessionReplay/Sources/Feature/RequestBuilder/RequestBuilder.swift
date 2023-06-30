/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal struct RequestBuilder: FeatureRequestBuilder {
    private static let newlineByte = "\n".data(using: .utf8)! // swiftlint:disable:this force_unwrapping

    /// Custom URL for uploading data to.
    let customUploadURL: URL?

    func request(for events: [Event], with context: DatadogContext) throws -> URLRequest {
        let source = SRSegment.Source(rawValue: context.source) ?? .ios // TODO: RUMM-2410 Send telemetry on `?? .ios`
        let segmentBuilder = SegmentJSONBuilder(source: source)

        // If we can't decode `events: [Data]` there is no way to recover, so we throw an
        // error to let the core delete the batch:
        let records = try events.map { try EnrichedRecordJSON(jsonObjectData: $0.data) }
        let segment = try segmentBuilder.createSegmentJSON(from: records)

        // If the SDK was configured with deprecated `set(*Endpoint:)` APIs we don't have `context.site`, so
        // we fallback to `.us1` - TODO: RUMM-2410 Report error with `DD.logger` in such case
        let url = customUploadURL ?? intakeURL(for: context.site)

        return try createRequest(url: url, segment: segment, context: context)
    }

    private func intakeURL(for site: DatadogSite) -> URL {
        // swiftlint:disable force_unwrapping
        switch site {
        case .us1:
            return URL(string: "https://session-replay.browser-intake-datadoghq.com/api/v2/replay")!
        case .us3:
            return URL(string: "https://session-replay.browser-intake-us3-datadoghq.com/api/v2/replay")!
        case .us5:
            return URL(string: "https://session-replay.browser-intake-us5-datadoghq.com/api/v2/replay")!
        case .eu1:
            return URL(string: "https://session-replay.browser-intake-datadoghq.eu/api/v2/replay")!
        case .ap1:
            return URL(string: "https://session-replay.browser-intake-datadoghq.eu/api/v2/replay")!
        case .us1_fed:
            return URL(string: "https://session-replay.browser-intake-ddog-gov.com/api/v2/replay")!
        }
        // swiftlint:enable force_unwrapping
    }

    private func createRequest(url: URL, segment: SegmentJSON, context: DatadogContext) throws -> URLRequest {
        var multipart = MultipartFormData(boundary: UUID())

        let builder = URLRequestBuilder(
            url: url,
            queryItems: [],
            headers: [
                .contentTypeHeader(contentType: .multipartFormData(boundary: multipart.boundary.uuidString)),
                .userAgentHeader(appName: context.applicationName, appVersion: context.version, device: context.device),
                .ddAPIKeyHeader(clientToken: context.clientToken),
                .ddEVPOriginHeader(source: context.source),
                .ddEVPOriginVersionHeader(sdkVersion: context.sdkVersion),
                .ddRequestIDHeader(),
            ]
        )

        // Session Replay BE accepts compressed segment data followed by newline character (before compression):
        var segmentData = try JSONSerialization.data(withJSONObject: segment.toJSONObject())
        segmentData.append(RequestBuilder.newlineByte)
        let compressedSegmentData = try SRCompression.compress(data: segmentData)

        // Compressed segment is sent within multipart form data - with some of segment (metadata)
        // attributes listed as form fields:
        multipart.addFormData(
            name: "segment",
            filename: segment.sessionID,
            data: compressedSegmentData,
            mimeType: "application/octet-stream"
        )
        multipart.addFormField(name: "segment", value: segment.sessionID)
        multipart.addFormField(name: "application.id", value: segment.applicationID)
        multipart.addFormField(name: "session.id", value: segment.sessionID)
        multipart.addFormField(name: "view.id", value: segment.viewID)
        multipart.addFormField(name: "has_full_snapshot", value: segment.hasFullSnapshot ? "true" : "false")
        multipart.addFormField(name: "records_count", value: "\(segment.recordsCount)")
        multipart.addFormField(name: "raw_segment_size", value: "\(compressedSegmentData.count)")
        multipart.addFormField(name: "start", value: "\(segment.start)")
        multipart.addFormField(name: "end", value: "\(segment.end)")
        multipart.addFormField(name: "source", value: "\(context.source)")

        // Data is already compressed, so request building request w/o compression:
        return builder.uploadRequest(with: multipart.data, compress: false)
    }
}
