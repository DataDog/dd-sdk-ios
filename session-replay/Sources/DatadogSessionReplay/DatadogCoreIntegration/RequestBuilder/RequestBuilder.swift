/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import Datadog

internal struct RequestBuilder: FeatureRequestBuilder {
    private static let newlineByte = "\n".data(using: .utf8)! // swiftlint:disable:this force_unwrapping

    /// An arbitrary uploader.
    /// TODO: RUMM-2509 Remove it when passing multiple requests per batch to `DatadogCore` is possible
    let uploader: Uploader
    /// Custom URL for uploading data to.
    let customUploadURL: URL?

    func request(for events: [Data], with context: DatadogContext) throws -> URLRequest {
        let source = SRSegment.Source(rawValue: context.source) ?? .ios // TODO: RUMM-2410 Send telemetry on `?? .ios`
        let segmentsBuilder = SegmentJSONBuilder(source: source)

        // If we can't decode `events: [Data]` there is no way to recover, so we throw an
        // error to let the core delete the batch:
        let records = try events.map { try EnrichedRecordJSON(jsonObjectData: $0) }
        let segments = segmentsBuilder.createSegmentJSONs(from: records)

        // If the SDK was configured with deprecated `set(*Endpoint:)` APIs we don't have `context.site`, so
        // we fallback to `.us1` - TODO: RUMM-2410 Report error with `DD.logger` in such case
        let url = customUploadURL ?? intakeURL(for: context.site ?? .us1)

        // If we fail to create request for some segments do not rethrow to caller, but instead try with
        // other segments. This is to recover from unexpected failures with maximizing the amount of data sent.
        let requests: [URLRequest] = segments.compactMap {
            do {
                // Errors thrown here indicate either `JSONSerialization` trouble on encoding segment
                // data or ZLIB compression error when compressing it:
                return try createRequest(url: url, segment: $0, context: context)
            } catch {
                return nil // TODO: RUMM-2410 Report error with `DD.logger` and send `DD.telemetry`
            }
        }

        guard let firstRequest = requests.first else {
            throw InternalError(description: "Failed to prepare upload request for session replay segments.")
        }

        // TODO: RUMM-2509 Pass multiple requests per batch to `DatadogCore`
        // Because it is yet not possible to return multiple requests to `DatadogCore`, we give it only
        // the first one and send other with an arbitrary uploader managed by SR module:
        if requests.count > 1 {
            uploader.upload(requests: requests[1..<requests.count])
        }

        return firstRequest
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
        case .us1_fed:
            return URL(string: "https://session-replay.browser-intake-ddog-gov.com/api/v2/replay")!
        }
        // swiftlint:enable force_unwrapping
    }

    private func createRequest(url: URL, segment: SegmentJSON, context: DatadogContext) throws -> URLRequest {
        var multipart = MultipartFormData(boundary: UUID())

        let builder = DDURLRequestBuilder(
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
