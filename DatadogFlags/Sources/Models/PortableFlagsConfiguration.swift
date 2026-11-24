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
                  // A flag that failed to evaluate on the server has an error record instead of an assignment.
                  case .dictionary(let evaluationErrors) = attributes["flagEvaluationErrors"] ?? .dictionary([:]),
                  Set(flags.keys).isDisjoint(with: evaluationErrors.keys),
                  let createdAt = attributes["createdAt"], validTimestamp(createdAt) else {
                throw Failure.invalidPrecomputed
            }

            // Reuse encoding and opt-out metadata validation without changing the network parser.
            let encoder = JSONEncoder()
            var metadata = attributes
            metadata["flags"] = .dictionary([:])
            let metadataData = try encoder.encode(["data": AnyValue.dictionary(["attributes": .dictionary(metadata)])])
            let parsed = try decoder.decode(FlagAssignmentsResponse.self, from: metadataData)
            // Dependency evaluations are validated like the browser does, but evaluation does not use them yet.
            var isDependencyKey: (String) -> Bool = { _ in true }
            if let obfuscation = parsed.obfuscation {
                // Validate even keys whose values failed to decode.
                try obfuscation.validateKeys(Array(flags.keys) + evaluationErrors.keys, codingPath: [])
                // An encoded response can list dependencies only if it declares how their keys are encrypted.
                let encryptsKeys = encryptsDependencyKeys(attributes["obfuscation"])
                isDependencyKey = { encryptsKeys && isEncryptedDependencyKey($0) }
            }

            // Decode flags independently; a malformed assignment must not hide its valid siblings.
            var validFlags: [String: FlagAssignment] = [:]
            var failedFlags: [String: String] = [:]
            for (key, flag) in flags {
                // An error result belongs in `flagEvaluationErrors`, not in `flags`.
                if case .dictionary(let fields) = flag, fields["reason"] != .string("ERROR"),
                   validDependencies(fields["dependencyEvaluations"], isKey: isDependencyKey),
                   let normalized = normalize(flag),
                   let encoded = try? encoder.encode(normalized),
                   let assignment = try? decoder.decode(FlagAssignment.self, from: encoded) {
                    validFlags[key] = assignment
                } else {
                    failedFlags[key] = "Invalid precomputed flag configuration"
                }
            }
            // A valid error record leaves its flag absent, so reads keep returning the default value.
            for (key, error) in evaluationErrors where !validEvaluationError(error, isDependencyKey: isDependencyKey) {
                failedFlags[key] = "Invalid precomputed flag evaluation error"
            }
            return FlagAssignmentsResponse(
                flags: validFlags,
                failedFlags: failedFlags,
                obfuscation: parsed.obfuscation,
                experimentationOptOut: parsed.experimentationOptOut,
                experimentationOptOutMode: parsed.experimentationOptOutMode,
                experimentationOptOutAt: parsed.experimentationOptOutAt,
                hasMalformedOptOutMetadata: parsed.hasMalformedOptOutMetadata,
                // Keeps evaluation telemetry consent, as the network parser does.
                observeFullEvaluationData: parsed.observeFullEvaluationData
            )
        }

        private static func validTimestamp(_ value: AnyValue) -> Bool {
            switch value {
            case .string, .int: return true
            case .double(let value): return value.isFinite
            default: return false
            }
        }

        /// Mirrors the browser's `isPrecomputedErrorFlag`.
        private static func validEvaluationError(_ value: AnyValue, isDependencyKey: (String) -> Bool) -> Bool {
            guard case .dictionary(let fields) = value else {
                return false
            }
            return fields["reason"] == .string("ERROR") && fields["errorCode"] == .string("GENERAL")
                && (fields["errorMessage"] == nil || nonEmptyString(fields["errorMessage"]))
                && validDependencies(fields["dependencyEvaluations"], isKey: isDependencyKey)
        }

        /// Mirrors the browser's `isDependencyEvaluations`: an optional list with one result per dependency key.
        private static func validDependencies(_ value: AnyValue?, isKey: (String) -> Bool) -> Bool {
            guard case .array(let dependencies) = value ?? .array([]) else {
                return false
            }
            var keys: Set<String> = []
            for dependency in dependencies {
                guard case .dictionary(let fields) = dependency, case .string(let key) = fields["flagKey"], !key.isEmpty,
                      isKey(key), keys.insert(key).inserted, validDependency(fields) else {
                    return false
                }
            }
            return true
        }

        /// Mirrors the browser's `isDependencyEvaluation`: an error result explains the failure, and any other
        /// result only says whether the dependency is in the assignment.
        private static func validDependency(_ fields: [String: AnyValue]) -> Bool {
            if fields["reason"] == .string("ERROR") {
                return nonEmptyString(fields["errorCode"]) && fields["isPresentInAssignment"] == nil
                    && (fields["errorMessage"] == nil || nonEmptyString(fields["errorMessage"]))
            }
            guard case .bool = fields["isPresentInAssignment"] else {
                return false
            }
            return [fields["reason"], fields["errorCode"], fields["errorMessage"]].allSatisfy { $0 == nil || $0 == .null }
        }

        private static func nonEmptyString(_ value: AnyValue?) -> Bool {
            guard case .string(let string) = value else {
                return false
            }
            return !string.isEmpty
        }

        private static func encryptsDependencyKeys(_ obfuscation: AnyValue?) -> Bool {
            guard case .dictionary(let descriptor) = obfuscation,
                  case .dictionary(let encryption) = descriptor["dependencyKeyEncryption"] else {
                return false
            }
            return encryption["scheme"] == .string("dependency-key-hkdf-sha256-aes-256-gcm-v1")
        }

        /// Mirrors the browser's `isEncryptedDependencyKey`: unpadded base64url text. Keys are not decrypted.
        private static func isEncryptedDependencyKey(_ key: String) -> Bool {
            let length = key.utf8.count
            return length >= 38 && length % 4 != 1
                && key.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
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
