/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
@testable import Datadog

internal struct RequestBuilder: FeatureRequestBuilder {
    /// An arbitrary uploader.
    let uploader: Uploader

    func request(for events: [Data], with context: DatadogContext) -> URLRequest {
        do {
            let source = SRSegment.Source(rawValue: context.source) ?? .ios // TODO: RUMM-2410 Send telemetry on `?? .ios`
            let builder = SegmentJSONBuilder(source: source)

            let recordJSONs = try events.map { try EnrichedRecordJSON(jsonObjectData: $0) }
            let segmentJSONs = builder.createSegmentJSONs(from: recordJSONs)

            // When SDK was configured with deprecated `set(*Endpoint:)` APIs we don't have `context.site`, so
            // we fallback to `.us1` - TODO: RUMM-2410 Report error with `DD.logger`
            let site = context.site ?? .us1
            let intakeURL = intakeURL(for: site)

            let requests = try segmentJSONs.map { segmentJSON in
                var request = URLRequest(url: intakeURL)
                try configure(&request, with: segmentJSON, context: context)
                return request
            }

            if requests.count > 1 {
                uploader.upload(requests: requests[1..<requests.count])
                return requests[0]
            } else if requests.count == 1 {
                return requests[0]
            } else {
                fatalError()
            }
        } catch {
            fatalError()
        }
    }

    private func intakeURL(for site: DatadogSite) -> URL {
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
    }

    private func configure(_ request: inout URLRequest, with segment: SegmentJSON, context: DatadogContext) throws {
        var multipart = MultipartFormData()
        var segmentData = try JSONSerialization.data(withJSONObject: try segment.toJSONObject())
        segmentData.append("\n".data(using: .utf8)!)
        let compressedSegment = try! SRCompression.compress(data: segmentData)

        multipart.addFormData(
            name: "segment",
            filename: segment.sessionID,
            data: compressedSegment,
            mimeType: "application/octet-stream"
        )
        multipart.addFormField(name: "segment", value: segment.sessionID)
        multipart.addFormField(name: "application.id", value: segment.applicationID)
        multipart.addFormField(name: "session.id", value: segment.sessionID)
        multipart.addFormField(name: "view.id", value: segment.viewID)
        multipart.addFormField(name: "has_full_snapshot", value: segment.hasFullSnapshot ? "true" : "false")
        multipart.addFormField(name: "records_count", value: "\(segment.recordsCount)")
        multipart.addFormField(name: "raw_segment_size", value: "\(compressedSegment.count)")
        multipart.addFormField(name: "start", value: "\(segment.start)")
        multipart.addFormField(name: "end", value: "\(segment.end)")
        multipart.addFormField(name: "source", value: "\(context.source)")

        request.setValue(userAgent(from: context), forHTTPHeaderField: "User-Agent")
        request.setValue(context.clientToken, forHTTPHeaderField: "DD-API-KEY")
        request.setValue(context.source, forHTTPHeaderField: "DD-EVP-ORIGIN")
        request.setValue(context.sdkVersion, forHTTPHeaderField: "DD-EVP-ORIGIN-VERSION")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "DD-REQUEST-ID")
        request.setValue("multipart/form-data; boundary=\(multipart.boundary.uuidString)", forHTTPHeaderField: "Content-Type")

        request.httpMethod = "POST"
        request.httpBody = multipart.data
    }

    private func userAgent(from context: DatadogContext) -> String {
        var sanitizedAppName = context.applicationName

        if let regex = try? NSRegularExpression(pattern: "[^a-zA-Z0-9 -]+") {
            sanitizedAppName = regex.stringByReplacingMatches(
                in: context.applicationName,
                range: NSRange(context.applicationName.startIndex..<context.applicationName.endIndex, in: context.applicationName),
                withTemplate: ""
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let device = context.device
        return "\(sanitizedAppName)/\(context.version) CFNetwork (\(device.name); \(device.osName)/\(device.osVersion))"
    }

}
