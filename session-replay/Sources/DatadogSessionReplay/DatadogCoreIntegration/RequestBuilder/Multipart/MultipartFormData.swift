/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// A helper facilitating creation of `multipart/form-data` body.
internal struct MultipartFormData {
    let boundary: UUID
    private var body = Data()

    init(boundary: UUID) {
        self.boundary = boundary
    }

    mutating func addFormField(name: String, value: String) {
        body.append(string: "--\(boundary.uuidString)\r\n")
        body.append(string: "Content-Disposition: form-data; name=\"\(name)\"\r\n")
        body.append(string: "\r\n")
        body.append(string: value)
        body.append(string: "\r\n")
    }

    mutating func addFormData(name: String, filename: String, data: Data, mimeType: String) {
        body.append(string: "--\(boundary.uuidString)\r\n")
        body.append(string: "Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
        body.append(string: "Content-Type: \(mimeType)\r\n")
        body.append(string: "\r\n")
        body.append(data)
        body.append(string: "\r\n")
    }

    var data: Data {
        var data = body
        data.append(string: "--\(boundary.uuidString)--")
        return data
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
