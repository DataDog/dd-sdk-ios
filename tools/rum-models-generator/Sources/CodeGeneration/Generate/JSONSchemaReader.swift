/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-Present Datadog, Inc.
*/

import Foundation

/// Reads `JSONSchema` from file.
internal class JSONSchemaReader {
    private let decoder: JSONDecoder

    init(decoder: JSONDecoder = .init()) {
        self.decoder = decoder
    }

    func read(_ file: URL) throws -> JSONSchema {
        let schema: JSONSchema = try withErrorContext(context: "Error while decoding \(file)") {
            let data = try Data(contentsOf: file)
            return try decoder.decode(JSONSchema.self, from: data)
        }

        try schema.resolveReferences(in: file.deletingLastPathComponent(), using: self)

        return schema
    }
}
