/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

private enum SRRequestException: Error {
    case multipartRequestException(String)
    case multipartDataException(String)
    case multipartFormException(String)
    case segmentException(String)
}

/// Matcher for asserting known elements of Session Replay (multipart) request.
///
/// See: ``DatadogSessionReplay.RequestBuilder`` to understand the encoding of multipart data operated by this matcher.
internal struct SRRequestMatcher {
    /// Creates matcher from Session Replay `URLRequest`.
    /// The `request` must be a valid Session Replay (multipart) request.
    ///
    /// - Parameter request: Session Replay request.
    init(request: URLRequest) throws {
        guard let body = request.httpBody else {
            throw SRRequestException.multipartRequestException("Request must define body")
        }
        try self.init(body: body, headers: request.allHTTPHeaderFields ?? [:])
    }

    /// Creates matcher from request body and headers.
    /// Both `body` and `headers` must describe a valid Session Replay (multipart) request.
    ///
    /// - Parameters:
    ///   - body: The body of request.
    ///   - headers: Request headers.
    init(body: Data, headers: [String: String]) throws {
        let contentTypePrefix = "multipart/form-data; boundary="
        guard let contentType = headers["Content-Type"] else {
            throw SRRequestException.multipartRequestException("Request must define Content-Type header")
        }
        guard contentType.hasPrefix(contentTypePrefix) else {
            throw SRRequestException.multipartRequestException("Content-Type must start with `\(contentTypePrefix)` and must specify boundary")
        }
        let boundary = contentType.removingPrefix(contentTypePrefix)
        guard !boundary.isEmpty else {
            throw SRRequestException.multipartRequestException("Multipart boundary must be a non-empty string")
        }
        try self.init(multipartBody: body, multipartBoundary: boundary)
    }

    /// Underlying (multipart) form data sent with tested request.
    private let multipartForm: MultipartFormDataParser

    /// Creates matcher from HTTP multipart data and given boundary.
    /// - Parameters:
    ///   - multipartBody: The multipart HTTP body.
    ///   - multipartBoundary: The boundary encoded in `multipartBody`.
    init(multipartBody: Data, multipartBoundary: String) throws {
        self.multipartForm = try MultipartFormDataParser(data: multipartBody, boundary: multipartBoundary)
    }

    /// Returns the blob file.
    func blob<T>(_ transform: (Data) throws -> T) throws -> T {
        let data = try dataOfFile(named: "blob", fieldName: "event", mimeType: "application/json")
        return try transform(data)
    }

    /// Data of "segment" file in underlying multipart form.
    func segment(at index: Int) throws -> SRSegmentMatcher {
        let compressedData = try dataOfFile(named: "file\(index)", fieldName: "segment", mimeType: "application/octet-stream")
        guard let data = zlib.decode(compressedData) else {
            throw SRRequestException.segmentException("Failed to decompress segment JSON data: \(compressedData)")
        }

        let object = try data.toJSONObject()
        return SRSegmentMatcher(object: object)
    }

    // MARK: - Querying Multipart Fields and Files

    private func valueOfField(named fieldName: String) throws -> String {
        let contentDispositionHeader = "Content-Disposition: form-data; name=\"\(fieldName)\""
        let field = try part(with: [contentDispositionHeader])
        return field.message.utf8String
    }

    private func dataOfFile(named fileName: String, fieldName: String, mimeType: String) throws -> Data {
        let contentDispositionHeader = "Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(fileName)\""
        let contentTypeHeader = "Content-Type: \(mimeType)"
        let field = try part(with: [contentDispositionHeader, contentTypeHeader])
        return field.message
    }

    private func part(with headers: Set<String>) throws -> MultipartFormDataParser.Part {
        guard let match = multipartForm.parts.first(where: { part in headers.isSubset(of: Set(part.headers)) }) else {
            throw SRRequestException.multipartFormException("No part in multipart form contains expected headers: '\(headers.joined(separator: ", "))'")
        }
        return match
    }
}

// MARK: - Multipart Parsing

/// Basic parser for HTTP multipart data.
///
/// It supports multipart idoms used in ``DatadogSessionReplay.MultipartFormData``. Other generic capabilities of
/// multipart format may not work correctly. Ref.: https://www.w3.org/Protocols/rfc1341/7_2_Multipart.html
private class MultipartFormDataParser {
    private let cr: UInt8 = 13 // CR
    private let lf: UInt8 = 10 // LF
    private let delimiterBytes: [UInt8]
    private let closingDelimiterBytes: [UInt8]

    private var bytes: [UInt8]
    private var offset: Int = 0

    struct Part {
        let headers: [String]
        let message: Data
    }

    private(set) var parts: [Part] = []

    init(data: Data, boundary: String) throws {
        self.delimiterBytes = "--\(boundary)".utf8Bytes + [cr, lf]
        self.closingDelimiterBytes = "--\(boundary)--".utf8Bytes
        self.bytes = [UInt8](data)
        try parseNext()
    }

    private func parseNext() throws {
        if try nextBytesEqual(delimiterBytes) {
            try parseBody()
        } else if try !nextBytesEqual(closingDelimiterBytes) {
            throw exception("Unexpected bytes")
        }
    }

    /// Parses next part delimited by `delimiterBytes`.
    private func parseBody() throws {
        try seek(delimiterBytes.count) // skip delimiter

        // Read headers:
        var headers: [String] = []
        while try !nextBytesEqual([cr, lf]) {
            if let header = try readHeader() {
                headers.append(header)
            }
        }
        try seek(2)

        // Read message:
        let message = try readMessage()

        // Extract new part:
        parts.append(Part(headers: headers, message: message))

        try parseNext()
    }

    /// Reads headers of part delimited by `delimiterBytes`.
    private func readHeader() throws -> String? {
        var header: [UInt8] = []
        while try !nextBytesEqual([cr, lf]) {
            header += try nextBytes(1)
            try seek(1)
        }
        try seek(2) // skip CRLF
        return header.isEmpty ? nil : Data(header).utf8String
    }

    /// Reads message (body) of part delimited by `delimiterBytes`.
    private func readMessage() throws -> Data {
        var message: [UInt8] = []
        while try !nextBytesEqual([cr, lf] + delimiterBytes) && !nextBytesEqual([cr, lf] + closingDelimiterBytes) {
            message += try nextBytes(1)
            try seek(1)
        }
        try seek(2) // skip CRLF
        return Data(message)
    }

    // MARK: - Helpers

    private func nextBytesEqual(_ otherBytes: [UInt8]) throws -> Bool {
        return (try? nextBytes(otherBytes.count)) == otherBytes
    }

    private func nextBytes(_ count: Int) throws -> [UInt8] {
        guard (offset + count) <= bytes.count else {
            throw exception("can't get next \(count) bytes - reached the end of data")
        }
        return Array(bytes[offset..<(offset + count)])
    }

    private func seek(_ size: Int) throws {
        guard (offset + size) <= bytes.count else {
            throw exception("can't seek by \(size) - it will exceed data size")
        }
        return offset += size
    }

    private func exception(_ message: String) -> Error {
        let before = bytes[max(0, offset - 10)..<offset]
        let after = bytes[offset..<min(bytes.count, offset + 10)]

        let context = "on parsing bytes: `(...)\(before.utf8String)-->\(after.utf8String)(...)`"
        return SRRequestException.multipartDataException("Multipart parsing exception: \(message)\n\n\(context)")
    }
}

private extension String {
    var utf8Bytes: [UInt8] { [UInt8](utf8Data) }
}

private extension ArraySlice where Element == UInt8 {
    var utf8String: String { Data(Array(self)).utf8String }
}
