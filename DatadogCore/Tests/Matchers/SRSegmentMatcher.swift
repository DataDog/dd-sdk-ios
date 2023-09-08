/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Matcher for asserting known values of Session Replay Segment.
///
/// See: ``DatadogSessionReplay.SRSegment`` to understand how underlying data is encoded.
internal class SRSegmentMatcher: JSONObjectMatcher {
    /// Creates matcher from Session Replay `URLRequest`. The `request` must be a valid Session Replay (multipart) request.
    /// This method extracts SR segment from the "segment" file encoded in multipart request. Other multipart fields are ignored.
    ///
    /// - Parameter request: Session Replay request.
    static func fromURLRequest(_ request: URLRequest) throws -> SRSegmentMatcher {
        let requestMatcher = try SRRequestMatcher(request: request)
        let segmentJSONObjectData = try requestMatcher.segmentJSONData()
        return SRSegmentMatcher(jsonObject: try segmentJSONObjectData.toJSONObject())
    }

    /// Creates matcher from JSON-encoded SR segment.
    /// - Parameter data: JSON-encoded SR segment data (not compressed).
    static func fromJSONData(_ data: Data) throws -> SRSegmentMatcher {
        return SRSegmentMatcher(jsonObject: try data.toJSONObject())
    }

    private init(jsonObject: [String: Any]) {
        super.init(object: jsonObject)
    }
}
