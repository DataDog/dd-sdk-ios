/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// A detached precomputed snapshot. Parsing does not initialize Flags or perform any I/O.
internal struct PortableFlagsConfiguration {
    enum Failure: Error {
        case invalidEnvelope
        case invalidPrecomputed
    }

    struct Precomputed: Codable {
        let response: String
        let context: [String: AnyValue]?
        let fetchedAt: Double?
        let etag: String?
        let assignments: FlagAssignmentsResponse

        private enum CodingKeys: String, CodingKey {
            case response, context, fetchedAt, etag
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            response = try container.decode(String.self, forKey: .response)
            context = try container.contains(.context) ? container.decode([String: AnyValue].self, forKey: .context) : nil
            fetchedAt = try container.contains(.fetchedAt) ? container.decode(Double.self, forKey: .fetchedAt) : nil
            etag = try container.contains(.etag) ? container.decode(String.self, forKey: .etag) : nil
            if let targetingKey = context?["targetingKey"] {
                guard case .string = targetingKey else { throw Failure.invalidPrecomputed }
            }
            if let fetchedAt, !fetchedAt.isFinite { throw Failure.invalidPrecomputed }
            assignments = try Self.decodeAssignments(response)
        }

        private static func decodeAssignments(_ response: String) throws -> FlagAssignmentsResponse {
            let decoder = JSONDecoder()
            // Unrepresentable JSON numbers reject the entry before per-flag validation.
            let payload = try decoder.decode([String: AnyValue].self, from: Data(response.utf8))
            guard case .dictionary(let data) = payload["data"],
                  case .dictionary(let attributes) = data["attributes"],
                  case .dictionary(let flags) = attributes["flags"],
                  let createdAt = attributes["createdAt"], validTimestamp(createdAt) else {
                throw Failure.invalidPrecomputed
            }

            // Decode flags independently; a malformed assignment must not hide its valid siblings.
            var validFlags: [String: FlagAssignment] = [:]
            var failedFlags: [String: String] = [:]
            let encoder = JSONEncoder()
            for (key, flag) in flags {
                if let normalized = normalize(flag),
                   let encoded = try? encoder.encode(normalized),
                   let assignment = try? decoder.decode(FlagAssignment.self, from: encoded) {
                    validFlags[key] = assignment
                } else {
                    failedFlags[key] = "Invalid precomputed flag configuration"
                }
            }

            // Reuse encoding and opt-out metadata validation without changing the network parser.
            var metadata = attributes
            metadata["flags"] = .dictionary([:])
            let metadataData = try encoder.encode(["data": AnyValue.dictionary(["attributes": .dictionary(metadata)])])
            let parsed = try decoder.decode(FlagAssignmentsResponse.self, from: metadataData)
            if let obfuscation = parsed.obfuscation {
                // Validate even keys whose values failed to decode.
                try obfuscation.validateKeys(flags.keys, codingPath: [])
            }
            return FlagAssignmentsResponse(
                flags: validFlags,
                failedFlags: failedFlags,
                obfuscation: parsed.obfuscation,
                experimentationOptOut: parsed.experimentationOptOut,
                experimentationOptOutMode: parsed.experimentationOptOutMode,
                experimentationOptOutAt: parsed.experimentationOptOutAt,
                hasMalformedOptOutMetadata: parsed.hasMalformedOptOutMetadata
            )
        }

        private static func validTimestamp(_ value: AnyValue) -> Bool {
            switch value {
            case .string, .int: return true
            case .double(let value): return value.isFinite
            default: return false
            }
        }

        private static func normalize(_ value: AnyValue) -> AnyValue? {
            guard case .dictionary(var flag) = value, case .string(let type) = flag["variationType"] else {
                return nil
            }
            // Preserve native numeric types so typed reads match the network parser.
            switch type {
            case "boolean", "string", "number", "integer", "float", "object": break
            case "BOOLEAN": flag["variationType"] = .string("boolean")
            case "STRING": flag["variationType"] = .string("string")
            case "NUMBER", "NUMERIC", "INTEGER": flag["variationType"] = .string("number")
            case "OBJECT", "JSON": flag["variationType"] = .string("object")
            default: return nil
            }
            return .dictionary(flag)
        }
    }

    let precomputed: Precomputed?
    let failure: Failure?

    /// Mirrors the browser's precomputed-only reader; rules entries are not decoded or retained.
    static func fromString(_ wire: String) -> PortableFlagsConfiguration {
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: Data(wire.utf8)) else {
            return .init(precomputed: nil, failure: .invalidEnvelope)
        }
        return .init(precomputed: envelope.precomputed, failure: envelope.failure)
    }

    func toString() throws -> String {
        let envelope = Envelope(precomputed: precomputed, failure: nil)
        return String(decoding: try JSONEncoder().encode(envelope), as: UTF8.self)
    }

    private struct Envelope: Codable {
        let precomputed: Precomputed?
        let failure: Failure?

        private enum CodingKeys: String, CodingKey { case version, precomputed }

        init(precomputed: Precomputed?, failure: Failure?) {
            self.precomputed = precomputed
            self.failure = failure
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let version = try container.decode(Int.self, forKey: .version)
            guard version == 1 || version == 2 else { throw Failure.invalidEnvelope }
            if container.contains(.precomputed) {
                precomputed = try? container.decode(Precomputed.self, forKey: .precomputed)
                failure = precomputed == nil ? .invalidPrecomputed : nil
            } else {
                precomputed = nil
                failure = nil
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(precomputed?.assignments.obfuscation == nil ? 1 : 2, forKey: .version)
            try container.encodeIfPresent(precomputed, forKey: .precomputed)
        }
    }
}
