/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

extension URLRequest {
    internal static func flagAssignmentsRequest(
        url: URL,
        evaluationContext: FlagsEvaluationContext,
        context: DatadogContext,
        customHeaders: [String: String]?,
        flagSelection: CanonicalFlagSelection?
    ) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        request.setValue("application/vnd.api+json", forHTTPHeaderField: "Content-Type")
        request.setValue("gzip, deflate, br", forHTTPHeaderField: "Accept-Encoding")
        request.setValue(context.clientToken, forHTTPHeaderField: "dd-client-token")
        // Bridge SDKs that consume raw snapshots cannot resolve encoded keys yet.
        if FlagKeyObfuscation.isSupported(source: context.source) {
            request.setValue(
                [FlagKeyObfuscation.capability].sorted().joined(separator: ","),
                forHTTPHeaderField: "X-DD-FEATURE-FLAGS-CAPABILITIES"
            )
        }

        if let applicationId = context.additionalContext(ofType: RUMCoreContext.self)?.applicationID {
            request.setValue(applicationId, forHTTPHeaderField: "dd-application-id")
        }

        if let customHeaders {
            for (key, value) in customHeaders {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }

        let requestBody = FlagAssignmentsRequestBody(
            environment: FlagAssignmentsRequestBody.Environment(
                name: context.env,
                datadogEnvironment: context.env
            ),
            source: FlagAssignmentsRequestBody.Source(
                sdkName: "dd-sdk-ios",
                sdkVersion: context.sdkVersion
            ),
            subject: FlagAssignmentsRequestBody.Subject(
                targetingKey: evaluationContext.targetingKey,
                targetingAttributes: evaluationContext.attributes
            ),
            flagSelection: flagSelection
        )

        let encoder = JSONEncoder.dd.default()
        request.httpBody = try encoder.encode(requestBody)

        return request
    }
}

internal struct FlagAssignmentsRequestBody {
    struct Subject: Encodable {
        private enum CodingKeys: String, CodingKey {
            case targetingKey = "targeting_key"
            case targetingAttributes = "targeting_attributes"
        }

        let targetingKey: String
        let targetingAttributes: [String: AnyValue]
    }

    struct Environment: Encodable {
        private enum CodingKeys: String, CodingKey {
            case name
            case datadogEnvironment = "dd_env"
        }

        let name: String
        let datadogEnvironment: String
    }

    struct Source: Encodable {
        private enum CodingKeys: String, CodingKey {
            case sdkName = "sdk_name"
            case sdkVersion = "sdk_version"
        }

        let sdkName: String
        let sdkVersion: String
    }

    let environment: Environment
    let source: Source
    let subject: Subject
    let flagSelection: CanonicalFlagSelection?
}

extension FlagAssignmentsRequestBody: Encodable {
    private enum CodingKeys: String, CodingKey {
        case type
        case data
        case attributes
        case flags
        case environment = "env"
        case source
        case subject
        case flagSelection = "flag_selection"
    }

    func encode(to encoder: any Encoder) throws {
        var rootContainer = encoder.container(keyedBy: CodingKeys.self)

        var dataContainer = rootContainer.nestedContainer(keyedBy: CodingKeys.self, forKey: .data)
        try dataContainer.encode("precompute-assignments-request", forKey: .type)

        var attributesContainer = dataContainer.nestedContainer(keyedBy: CodingKeys.self, forKey: .attributes)
        try attributesContainer.encode(environment, forKey: .environment)
        try attributesContainer.encode(source, forKey: .source)
        try attributesContainer.encode(subject, forKey: .subject)
        try attributesContainer.encodeIfPresent(flagSelection, forKey: .flagSelection)
    }
}

internal enum FlagSelectionDropReason: String, Error {
    case tooManyValues = "too_many_values"
    case invalidKeyPattern = "invalid_key_pattern"
    case invalidTag = "invalid_tag"

    var limit: String {
        switch self {
        case .tooManyValues: return "each list accepts at most \(CanonicalFlagSelection.maxValues) values"
        case .invalidKeyPattern: return "each key pattern is at most \(CanonicalFlagSelection.maxKeyPatternBytes) UTF-8 bytes"
        case .invalidTag: return "each tag is at most \(CanonicalFlagSelection.maxTagBytes) UTF-8 bytes"
        }
    }
}

/// A flag selection canonicalized and validated the same way the server does.
internal struct CanonicalFlagSelection: Codable {
    private enum CodingKeys: String, CodingKey {
        case tags
        case keyPatterns = "key_patterns"
    }

    static let maxValues = 31
    static let maxTagBytes = 200
    static let maxKeyPatternBytes = 200

    // The Unicode White_Space property, which Compute trims with Rust's `str::trim`.
    // Listed explicitly so trimming does not depend on the OS Unicode data.
    private static let whiteSpace: Set<Unicode.Scalar> = [
        "\u{0009}", "\u{000A}", "\u{000B}", "\u{000C}", "\u{000D}", "\u{0020}", "\u{0085}", "\u{00A0}", "\u{1680}",
        "\u{2000}", "\u{2001}", "\u{2002}", "\u{2003}", "\u{2004}", "\u{2005}", "\u{2006}", "\u{2007}", "\u{2008}",
        "\u{2009}", "\u{200A}", "\u{2028}", "\u{2029}", "\u{202F}", "\u{205F}", "\u{3000}",
    ]

    let tags: [String]
    let keyPatterns: [String]

    /// Returns `nil` when there is no selection or both lists are empty after canonicalization.
    static func make(from selection: Flags.FlagSelection?) -> Result<CanonicalFlagSelection?, FlagSelectionDropReason> {
        guard let selection else {
            return .success(nil)
        }
        let tags = canonicalize(selection.tags)
        let keyPatterns = canonicalize(selection.keyPatterns)

        if tags.count > maxValues || keyPatterns.count > maxValues {
            return .failure(.tooManyValues)
        }
        if keyPatterns.contains(where: { $0.utf8.count > maxKeyPatternBytes }) {
            return .failure(.invalidKeyPattern)
        }
        if tags.contains(where: { $0.utf8.count > maxTagBytes }) {
            return .failure(.invalidTag)
        }
        if tags.isEmpty && keyPatterns.isEmpty {
            return .success(nil)
        }
        return .success(CanonicalFlagSelection(tags: tags, keyPatterns: keyPatterns))
    }

    /// Canonicalizes the selection, or logs and reports why it is dropped and returns `nil`.
    static func resolve(_ selection: Flags.FlagSelection?, telemetry: Telemetry) -> CanonicalFlagSelection? {
        switch make(from: selection) {
        case .success(let canonical):
            return canonical
        case .failure(let reason):
            DD.logger.error(
                "`Flags.Configuration.flagSelection` was not sent (\(reason.rawValue): \(reason.limit)). Loading the full flag configuration."
            )
            telemetry.debug("Flag selection dropped", attributes: ["reason": reason.rawValue])
            return nil
        }
    }

    private static func canonicalize(_ values: [String]) -> [String] {
        // Dedupe on bytes: Swift `String` equality treats NFC and NFD forms as equal, and Compute does not.
        var seen: Set<Data> = []
        var unique: [String] = []
        for value in values {
            let trimmed = trimmingWhiteSpace(value)
            if !trimmed.isEmpty && seen.insert(Data(trimmed.utf8)).inserted {
                unique.append(trimmed)
            }
        }
        return unique.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
    }

    private static func trimmingWhiteSpace(_ value: String) -> String {
        let scalars = value.unicodeScalars
        guard let first = scalars.firstIndex(where: { !whiteSpace.contains($0) }),
              let last = scalars.lastIndex(where: { !whiteSpace.contains($0) }) else {
            return ""
        }
        return String(scalars[first...last])
    }
}

extension CanonicalFlagSelection: Equatable {
    // Compares bytes: Swift `String` equality treats NFC and NFD forms as equal, and Compute does not.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.tags.elementsEqual(rhs.tags) { $0.utf8.elementsEqual($1.utf8) }
            && lhs.keyPatterns.elementsEqual(rhs.keyPatterns) { $0.utf8.elementsEqual($1.utf8) }
    }
}
