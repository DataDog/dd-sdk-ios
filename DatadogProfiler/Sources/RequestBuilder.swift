/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal struct RequestBuilder: FeatureRequestBuilder {
    let apiKey: String

    /// Builds multipart form for request's body.
    let multipartBuilder: MultipartFormDataBuilder

    /// Custom URL for uploading data to.
    let customUploadURL: URL?

    /// Sends telemetry through sdk core.
    let telemetry: Telemetry

    init(
        apiKey: String,
        multipartBuilder: MultipartFormDataBuilder = MultipartFormData(),
        customUploadURL: URL? = nil,
        telemetry: Telemetry = NOPTelemetry()
    ) {
        self.apiKey = apiKey
        self.multipartBuilder = multipartBuilder
        self.customUploadURL = customUploadURL
        self.telemetry = telemetry
    }

    func request(for events: [Event], with context: DatadogContext, execution: ExecutionContext) throws -> URLRequest {
        guard events.count == 1, let prof = events.first else {
            throw ProgrammerError(description: "Invalid event count: \(events.count)")
        }

        var multipart = multipartBuilder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let str = try container.decode(String.self)
            return iso8601DateFormatter.date(from: str) ?? Date()
        }

        let profile = try decoder.decode(ProfileEvent.self, from: prof.data)

        let tags: [String] = [
            "service:\(context.service)",
            "version:\(context.version)",
            "env:\(context.env)",
            "source:\(context.source)",
            "runtime:swift",
            "language:swift"
        ]

        var event: [String: Any] = [
            "tags_profiler": "service:\(context.service),version:\(context.version)",
            "family": "go",
            "version": "4",
            "attachments": ["cpu.pprof"],
            "start": iso8601DateFormatter.string(from: profile.start),
            "end": iso8601DateFormatter.string(from: profile.end)
        ]

        event["application"] = ["id": profile.applicationID]
        event["session"] = ["id": profile.sessionID]
//        event["view"] = profile.viewID

        try multipart.addFormData(
            name: "event",
            filename: "event.json",
            data: JSONSerialization.data(withJSONObject: event),
            mimeType: "application/json"
        )

        multipart.addFormData(
            name: "cpu.pprof",
            filename: "cpu.pprof",
            data: profile.cpuProf,
            mimeType: "application/octet-stream"
        )

        let builder = URLRequestBuilder(
            url: url(with: context),
            queryItems: [
//                .ddtags(tags: tags)
            ],
            headers: [
                .contentTypeHeader(contentType: .multipartFormData(boundary: multipart.boundary)),
                .userAgentHeader(appName: context.applicationName, appVersion: context.version, device: context.device),
                .ddAPIKeyHeader(clientToken: apiKey),
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

internal protocol MultipartFormDataBuilder {
    /// The boundary  of this multipart form.
    var boundary: String { get }
    /// Adds a field.
    mutating func addFormField(name: String, value: String)
    /// Adds a file.
    mutating func addFormData(name: String, filename: String, data: Data, mimeType: String)
    /// Returns the entire multipart body data (as it should be applied to request).
    mutating func build() -> Data
}

/// A helper facilitating creation of `multipart/form-data` body.
internal struct MultipartFormData: MultipartFormDataBuilder {
    private var body: Data

    private(set) var boundary: String

    init(boundary: UUID = UUID()) {
        self.body = Data()
        self.boundary = boundary.uuidString
    }

    mutating func addFormField(name: String, value: String) {
        body.append(string: "--\(boundary)\r\n")
        body.append(string: "Content-Disposition: form-data; name=\"\(name)\"\r\n")
        body.append(string: "\r\n")
        body.append(string: value)
        body.append(string: "\r\n")
    }

    mutating func addFormData(name: String, filename: String, data: Data, mimeType: String) {
        body.append(string: "--\(boundary)\r\n")
        body.append(string: "Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
        body.append(string: "Content-Type: \(mimeType)\r\n")
        body.append(string: "\r\n")
        body.append(data)
        body.append(string: "\r\n")
    }

    mutating func build() -> Data {
        defer {
            // reset builder
            body = Data()
            boundary = UUID().uuidString
        }

        body.append(string: "--\(boundary)--")
        return body
    }
}

private extension Data {
    mutating func append(string: String) {
        guard let data = string.data(using: .utf8) else {
            return
        }
        self.append(data)
    }
}
