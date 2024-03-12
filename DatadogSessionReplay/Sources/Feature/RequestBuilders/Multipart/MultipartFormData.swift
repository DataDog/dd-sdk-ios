/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation

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
#endif
