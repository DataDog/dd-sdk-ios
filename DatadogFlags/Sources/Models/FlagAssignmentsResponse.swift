/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

internal enum PrecomputedDependencyEvaluation: Equatable, Codable {
    case success(flagKey: String, isPresentInAssignment: Bool)
    case failure(flagKey: String, errorCode: String, errorMessage: String?)

    var flagKey: String {
        switch self {
        case .success(let flagKey, _), .failure(let flagKey, _, _): return flagKey
        }
    }

    private enum CodingKeys: String, CodingKey {
        case flagKey, isPresentInAssignment, reason, errorCode, errorMessage
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let flagKey = try container.decode(String.self, forKey: .flagKey)
        guard !flagKey.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .flagKey, in: container, debugDescription: "Expected a non-empty flag key")
        }
        if container.contains(.reason) {
            guard try container.decode(String.self, forKey: .reason) == "ERROR",
                  !container.contains(.isPresentInAssignment) else {
                throw DecodingError.dataCorruptedError(forKey: .reason, in: container, debugDescription: "Invalid dependency error")
            }
            let errorCode = try container.decode(String.self, forKey: .errorCode)
            guard !errorCode.isEmpty else {
                throw DecodingError.dataCorruptedError(forKey: .errorCode, in: container, debugDescription: "Expected a non-empty error code")
            }
            let errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage)
            guard errorMessage?.isEmpty != true else {
                throw DecodingError.dataCorruptedError(forKey: .errorMessage, in: container, debugDescription: "Expected a non-empty error message")
            }
            self = .failure(flagKey: flagKey, errorCode: errorCode, errorMessage: errorMessage)
        } else {
            guard !container.contains(.errorCode), !container.contains(.errorMessage) else {
                throw DecodingError.dataCorruptedError(forKey: .errorCode, in: container, debugDescription: "Successful dependency contains error fields")
            }
            self = .success(
                flagKey: flagKey,
                isPresentInAssignment: try container.decode(Bool.self, forKey: .isPresentInAssignment)
            )
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(flagKey, forKey: .flagKey)
        switch self {
        case .success(_, let isPresentInAssignment):
            try container.encode(isPresentInAssignment, forKey: .isPresentInAssignment)
        case .failure(_, let errorCode, let errorMessage):
            try container.encode("ERROR", forKey: .reason)
            try container.encode(errorCode, forKey: .errorCode)
            try container.encodeIfPresent(errorMessage, forKey: .errorMessage)
        }
    }

    static func validateUniqueKeys(_ evaluations: [Self], codingPath: [CodingKey]) throws {
        var keys: Set<String> = []
        guard evaluations.allSatisfy({ keys.insert($0.flagKey).inserted }) else {
            throw DecodingError.dataCorrupted(.init(codingPath: codingPath, debugDescription: "Dependency flag keys must be unique"))
        }
    }
}

internal struct FlagEvaluationFailure: Equatable, Codable {
    let errorCode: String
    let errorMessage: String?
    let dependencyEvaluations: [PrecomputedDependencyEvaluation]

    private enum CodingKeys: String, CodingKey {
        case reason, errorCode, errorMessage, dependencyEvaluations
    }

    init(errorCode: String = "GENERAL", errorMessage: String? = nil, dependencyEvaluations: [PrecomputedDependencyEvaluation] = []) {
        self.errorCode = errorCode
        self.errorMessage = errorMessage
        self.dependencyEvaluations = dependencyEvaluations
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(String.self, forKey: .reason) == "ERROR" else {
            throw DecodingError.dataCorruptedError(forKey: .reason, in: container, debugDescription: "Expected ERROR")
        }
        let errorCode = try container.decode(String.self, forKey: .errorCode)
        guard errorCode == "GENERAL" else {
            throw DecodingError.dataCorruptedError(forKey: .errorCode, in: container, debugDescription: "Root evaluation errors must use GENERAL")
        }
        let errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage)
        guard errorMessage?.isEmpty != true else {
            throw DecodingError.dataCorruptedError(forKey: .errorMessage, in: container, debugDescription: "Expected a non-empty error message")
        }
        let dependencies = try container.decodeIfPresent(
            [PrecomputedDependencyEvaluation].self,
            forKey: .dependencyEvaluations
        ) ?? []
        try PrecomputedDependencyEvaluation.validateUniqueKeys(dependencies, codingPath: container.codingPath)
        self.init(errorCode: errorCode, errorMessage: errorMessage, dependencyEvaluations: dependencies)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("ERROR", forKey: .reason)
        try container.encode(errorCode, forKey: .errorCode)
        try container.encodeIfPresent(errorMessage, forKey: .errorMessage)
        if !dependencyEvaluations.isEmpty {
            try container.encode(dependencyEvaluations, forKey: .dependencyEvaluations)
        }
    }
}

internal enum ResolvedDependencyEvaluation: Equatable {
    case success(flagKey: String, assignment: FlagAssignment, isPresentInAssignment: Bool)
    case failure(flagKey: String, errorCode: String, errorMessage: String?)
}

internal struct FlagAssignmentsResponse: Equatable {
    private(set) var flags: [String: FlagAssignment]
    /// Assignments whose keys are canonically equivalent to, but not byte-equal to, a key in `flags`.
    var keySpellings: [FlagKeySpelling] = []
    private(set) var failedFlags: [String: String] // key -> error description
    /// Failed keys that are canonically equivalent to, but not byte-equal to, a key in `failedFlags`.
    private(set) var failedKeySpellings: [String] = []
    private(set) var flagEvaluationErrors: [String: FlagEvaluationFailure]
    var errorKeySpellings: [FlagEvaluationErrorSpelling] = []
    let obfuscation: FlagKeyObfuscation?
    let experimentationOptOut: Bool?
    let hasMalformedOptOutMetadata: Bool
    let experimentationOptOutMode: String?
    let experimentationOptOutAt: String?
    let observeFullEvaluationData: Bool

    /// Every served key whose assignment cannot be parsed, one entry for each spelling.
    var unparsedFlagKeys: [String] { Array(failedFlags.keys) + failedKeySpellings }

    init(
        flags: [String: FlagAssignment],
        failedFlags: [String: String] = [:],
        flagEvaluationErrors: [String: FlagEvaluationFailure] = [:],
        obfuscation: FlagKeyObfuscation? = nil,
        experimentationOptOut: Bool? = nil,
        experimentationOptOutMode: String? = nil,
        experimentationOptOutAt: String? = nil,
        hasMalformedOptOutMetadata: Bool = false,
        observeFullEvaluationData: Bool = false
    ) {
        self.flags = flags.mapValues { assignment in
            var assignment = assignment
            assignment.observeFullEvaluationData = observeFullEvaluationData
            return assignment
        }
        self.failedFlags = failedFlags
        self.flagEvaluationErrors = flagEvaluationErrors
        self.obfuscation = obfuscation
        self.experimentationOptOut = experimentationOptOut
        self.experimentationOptOutMode = experimentationOptOutMode
        self.experimentationOptOutAt = experimentationOptOutAt
        self.hasMalformedOptOutMetadata = hasMalformedOptOutMetadata
        self.observeFullEvaluationData = observeFullEvaluationData
    }
}

extension FlagAssignmentsResponse: Codable {
    private enum CodingKeys: String, CodingKey {
        case data
        case attributes
        case flags
        case flagEvaluationErrors
        case observeFullEvaluationData
        case obfuscated
        case obfuscation
        case evaluationOptions = "evaluation_options"
        case experimentationOptOut = "experimentation_opt_out"
        case experimentationOptOutMode = "experimentation_opt_out_mode"
        case experimentationOptOutAt = "dd_experimentation_opt_out_at"
    }

    init(from decoder: any Decoder) throws {
        let rootContainer = try decoder.container(keyedBy: CodingKeys.self)
        let dataContainer = try rootContainer.nestedContainer(keyedBy: CodingKeys.self, forKey: .data)
        let attributesContainer = try dataContainer.nestedContainer(keyedBy: CodingKeys.self, forKey: .attributes)
        let hasOptions = attributesContainer.contains(.evaluationOptions)
            && (try? attributesContainer.decodeNil(forKey: .evaluationOptions)) != true
        let options = try? attributesContainer.nestedContainer(keyedBy: CodingKeys.self, forKey: .evaluationOptions)
        let hasOptOutValue = options.map {
            $0.contains(.experimentationOptOut) && (try? $0.decodeNil(forKey: .experimentationOptOut)) != true
        } ?? false
        experimentationOptOut = try? options?.decode(Bool.self, forKey: .experimentationOptOut)
        // A present options value or Boolean of the wrong type must not look like an unfiltered response.
        hasMalformedOptOutMetadata = (hasOptions && options == nil) || (hasOptOutValue && experimentationOptOut == nil)
        if let options, options.contains(.experimentationOptOutMode) {
            // Preserve a malformed mode as invalid instead of treating it as an absent legacy acknowledgement.
            experimentationOptOutMode = (try? options.decode(String.self, forKey: .experimentationOptOutMode)) ?? ""
        } else {
            experimentationOptOutMode = nil
        }
        if let options, options.contains(.experimentationOptOutAt) {
            // A present malformed cutoff must not look like an unfiltered response.
            experimentationOptOutAt = (try? options.decode(String.self, forKey: .experimentationOptOutAt)) ?? ""
        } else {
            experimentationOptOutAt = nil
        }

        // Only a literal boolean true opts in. Old or malformed fields fail closed.
        observeFullEvaluationData = (try? attributesContainer.decode(Bool.self, forKey: .observeFullEvaluationData)) == true

        // Decode all flags (including those with unknown variation types)
        let allFlags = try attributesContainer.decode([String: FlagAssignment].self, forKey: .flags)
        let flagEvaluationErrors = try attributesContainer.decodeIfPresent(
            [String: FlagEvaluationFailure].self,
            forKey: .flagEvaluationErrors
        ) ?? [:]
        guard Set(allFlags.keys.map { Data($0.utf8) }).isDisjoint(
            with: Set(flagEvaluationErrors.keys.map { Data($0.utf8) })
        ) else {
            throw DecodingError.dataCorruptedError(
                forKey: .flagEvaluationErrors,
                in: attributesContainer,
                debugDescription: "A flag cannot contain both an assignment and an evaluation error"
            )
        }
        let isObfuscated = attributesContainer.contains(.obfuscated)
            ? try attributesContainer.decode(Bool.self, forKey: .obfuscated) : false
        if isObfuscated {
            let obfuscation = try attributesContainer.decode(FlagKeyObfuscation.self, forKey: .obfuscation)
            try obfuscation.validateKeys(allFlags.keys, codingPath: attributesContainer.codingPath + [CodingKeys.flags])
            try obfuscation.validateErrorKeys(
                flagEvaluationErrors.keys,
                codingPath: attributesContainer.codingPath + [CodingKeys.flagEvaluationErrors]
            )
            try obfuscation.validateDependencyEvaluations(in: allFlags.values, and: flagEvaluationErrors.values)
            self.obfuscation = obfuscation
        } else if attributesContainer.contains(.obfuscation) {
            throw DecodingError.dataCorruptedError(
                forKey: .obfuscation,
                in: attributesContainer,
                debugDescription: "`obfuscation` requires `obfuscated: true`"
            )
        } else {
            self.obfuscation = nil
        }

        // Separate valid flags from unknown variations
        var successfulFlags: [String: FlagAssignment] = [:]
        var failedFlags: [String: String] = [:]

        for (key, assignment) in allFlags {
            if case .unknown(let typeName) = assignment.variation {
                failedFlags[key] = "Unrecognized variation type \(typeName)"
            } else {
                var assignment = assignment
                assignment.observeFullEvaluationData = observeFullEvaluationData
                successfulFlags[key] = assignment
            }
        }

        self.flags = successfulFlags
        self.failedFlags = failedFlags
        self.flagEvaluationErrors = flagEvaluationErrors
    }

    func encode(to encoder: any Encoder) throws {
        var rootContainer = encoder.container(keyedBy: CodingKeys.self)
        var dataContainer = rootContainer.nestedContainer(keyedBy: CodingKeys.self, forKey: .data)
        var attributesContainer = dataContainer.nestedContainer(keyedBy: CodingKeys.self, forKey: .attributes)
        try attributesContainer.encode(flags, forKey: .flags)
        if !flagEvaluationErrors.isEmpty {
            try attributesContainer.encode(flagEvaluationErrors, forKey: .flagEvaluationErrors)
        }
        if experimentationOptOut != nil || experimentationOptOutMode != nil || experimentationOptOutAt != nil {
            var options = attributesContainer.nestedContainer(keyedBy: CodingKeys.self, forKey: .evaluationOptions)
            try options.encodeIfPresent(experimentationOptOut, forKey: .experimentationOptOut)
            try options.encodeIfPresent(experimentationOptOutMode, forKey: .experimentationOptOutMode)
            try options.encodeIfPresent(experimentationOptOutAt, forKey: .experimentationOptOutAt)
        }
        try attributesContainer.encode(observeFullEvaluationData, forKey: .observeFullEvaluationData)
        if let obfuscation {
            try attributesContainer.encode(true, forKey: .obfuscated)
            try attributesContainer.encode(obfuscation, forKey: .obfuscation)
        }
    }
}

extension FlagAssignmentsResponse: FlagNumericTokenRoot {
    static var flagAssignmentsPath: [String] { ["data", "attributes", "flags"] }
}

/// A plaintext assignment kept outside `[String: FlagAssignment]`, which can hold only one of two canonically
/// equivalent keys such as `caf\u{00E9}` and `cafe\u{0301}`.
internal struct FlagKeySpelling: Equatable, Codable {
    let key: String
    var assignment: FlagAssignment
}

/// A plaintext evaluation error kept outside the dictionary when another key has a canonically equivalent spelling.
internal struct FlagEvaluationErrorSpelling: Equatable, Codable {
    let key: String
    var failure: FlagEvaluationFailure
}

extension FlagAssignmentsResponse {
    /// Rebuilds the served plaintext keys that decoding merged into one canonically equivalent key.
    ///
    /// Decoding keeps one key of each group, but its value can come from another spelling in the group.
    /// So every member of a group is decoded again from its own bytes.
    func addingKeySpellings(from data: Data) throws -> FlagAssignmentsResponse {
        let bytes = Array(FlagsNumericJSON.utf8(data))
        guard obfuscation == nil,
              Self.mayContainNonASCIIKeys(bytes) else {
            return self
        }
        var response = self

        if let members = JSONObjectMembers.members(at: Self.flagAssignmentsPath, in: bytes) {
            var groups: [String: [JSONObjectMembers.Member]] = [:]
            for member in members {
                groups[member.key, default: []].append(member)
            }
            for group in groups.values where Set(group.map { Array($0.key.utf8) }).count > 1 {
                response.flags.removeValue(forKey: group[0].key)
                response.failedFlags.removeValue(forKey: group[0].key)
                for member in group {
                    guard var assignment = try? FlagsNumericJSON.decode(FlagAssignment.self, from: Data(bytes[member.value])) else {
                        continue
                    }
                    if case .unknown(let typeName) = assignment.variation {
                        response.fail(member.key, "Unrecognized variation type \(typeName)")
                        continue
                    }
                    assignment.observeFullEvaluationData = observeFullEvaluationData
                    response.place(assignment, for: member.key)
                }
            }
        }

        let errorPath = ["data", "attributes", "flagEvaluationErrors"]
        if let members = JSONObjectMembers.members(at: errorPath, in: bytes) {
            var groups: [String: [JSONObjectMembers.Member]] = [:]
            for member in members {
                groups[member.key, default: []].append(member)
            }
            for group in groups.values where Set(group.map { Array($0.key.utf8) }).count > 1 {
                response.flagEvaluationErrors.removeValue(forKey: group[0].key)
                for member in group {
                    if let failure = try? JSONDecoder().decode(
                        FlagEvaluationFailure.self,
                        from: Data(bytes[member.value])
                    ) {
                        response.place(failure, for: member.key)
                    }
                }
            }
        }

        let assignmentKeys = response.flags.keys.map { Data($0.utf8) }
            + response.keySpellings.map { Data($0.key.utf8) }
            + response.unparsedFlagKeys.map { Data($0.utf8) }
        let errorKeys = response.flagEvaluationErrors.keys.map { Data($0.utf8) }
            + response.errorKeySpellings.map { Data($0.key.utf8) }
        guard Set(assignmentKeys).isDisjoint(with: Set(errorKeys)) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: [],
                debugDescription: "A flag cannot contain both an assignment and an evaluation error"
            ))
        }
        return response
    }

    /// Records a failure under the exact bytes of `key`. A later duplicate of the same bytes keeps the first one.
    private mutating func fail(_ key: String, _ description: String) {
        guard let index = failedFlags.index(forKey: key) else {
            failedFlags[key] = description
            return
        }
        if !failedFlags[index].key.utf8.elementsEqual(key.utf8),
           !failedKeySpellings.contains(where: { $0.utf8.elementsEqual(key.utf8) }) {
            failedKeySpellings.append(key)
        }
    }

    /// Stores `assignment` under the exact bytes of `key`. A later duplicate of the same bytes replaces it.
    private mutating func place(_ assignment: FlagAssignment, for key: String) {
        if let index = flags.index(forKey: key) {
            if flags[index].key.utf8.elementsEqual(key.utf8) {
                flags[key] = assignment
            } else if let spelling = keySpellings.firstIndex(where: { $0.key.utf8.elementsEqual(key.utf8) }) {
                keySpellings[spelling].assignment = assignment
            } else {
                keySpellings.append(FlagKeySpelling(key: key, assignment: assignment))
            }
        } else {
            flags[key] = assignment
        }
    }

    /// Stores an evaluation failure under the exact UTF-8 bytes of `key`.
    private mutating func place(_ failure: FlagEvaluationFailure, for key: String) {
        if let index = flagEvaluationErrors.index(forKey: key) {
            if flagEvaluationErrors[index].key.utf8.elementsEqual(key.utf8) {
                flagEvaluationErrors[key] = failure
            } else if let spelling = errorKeySpellings.firstIndex(where: { $0.key.utf8.elementsEqual(key.utf8) }) {
                errorKeySpellings[spelling].failure = failure
            } else {
                errorKeySpellings.append(FlagEvaluationErrorSpelling(key: key, failure: failure))
            }
        } else {
            flagEvaluationErrors[key] = failure
        }
    }

    /// Only non-ASCII bytes or `\u` escapes can spell two keys that Swift compares as equal.
    private static func mayContainNonASCIIKeys(_ bytes: [UInt8]) -> Bool {
        for index in bytes.indices {
            if bytes[index] >= 0x80 {
                return true
            }
            if bytes[index] == UInt8(ascii: "\\"), index + 1 < bytes.count, bytes[index + 1] == UInt8(ascii: "u") {
                return true
            }
        }
        return false
    }
}

/// Lists the members of a JSON object from its bytes, so that every served key keeps its own spelling.
private enum JSONObjectMembers {
    typealias Member = (key: String, value: Range<Int>)

    static func members(at path: [String], in bytes: [UInt8]) -> [Member]? {
        var start = 0
        for key in path {
            guard let member = members(ofObjectAt: start, in: bytes)?.first(where: { $0.key == key }) else {
                return nil
            }
            start = member.value.lowerBound
        }
        return members(ofObjectAt: start, in: bytes)
    }

    private static func members(ofObjectAt start: Int, in bytes: [UInt8]) -> [Member]? {
        var index = skipWhitespace(from: start, in: bytes)
        guard index < bytes.count, bytes[index] == UInt8(ascii: "{") else {
            return nil
        }
        var members: [Member] = []
        index = skipWhitespace(from: index + 1, in: bytes)
        if index < bytes.count, bytes[index] == UInt8(ascii: "}") {
            return members
        }
        while index < bytes.count {
            guard bytes[index] == UInt8(ascii: "\""),
                  let keyEnd = stringEnd(from: index, in: bytes),
                  let key = try? JSONDecoder().decode([String].self, from: Data([UInt8(ascii: "[")] + bytes[index..<keyEnd] + [UInt8(ascii: "]")])).first else {
                return nil
            }
            index = skipWhitespace(from: keyEnd, in: bytes)
            guard index < bytes.count, bytes[index] == UInt8(ascii: ":") else {
                return nil
            }
            let valueStart = skipWhitespace(from: index + 1, in: bytes)
            guard let valueEnd = valueEnd(from: valueStart, in: bytes) else {
                return nil
            }
            members.append((key, valueStart..<valueEnd))
            index = skipWhitespace(from: valueEnd, in: bytes)
            guard index < bytes.count else {
                return nil
            }
            if bytes[index] == UInt8(ascii: "}") {
                return members
            }
            guard bytes[index] == UInt8(ascii: ",") else {
                return nil
            }
            index = skipWhitespace(from: index + 1, in: bytes)
        }
        return nil
    }

    private static func skipWhitespace(from start: Int, in bytes: [UInt8]) -> Int {
        var index = start
        while index < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[index]) {
            index += 1
        }
        return index
    }

    /// Returns the index after the closing quote of the string that starts at `start`.
    private static func stringEnd(from start: Int, in bytes: [UInt8]) -> Int? {
        var index = start + 1
        while index < bytes.count {
            if bytes[index] == UInt8(ascii: "\\") {
                index += 2
            } else if bytes[index] == UInt8(ascii: "\"") {
                return index + 1
            } else {
                index += 1
            }
        }
        return nil
    }

    private static func valueEnd(from start: Int, in bytes: [UInt8]) -> Int? {
        guard start < bytes.count else {
            return nil
        }
        switch bytes[start] {
        case UInt8(ascii: "\""):
            return stringEnd(from: start, in: bytes)
        case UInt8(ascii: "{"), UInt8(ascii: "["):
            var depth = 0
            var index = start
            while index < bytes.count {
                switch bytes[index] {
                case UInt8(ascii: "\""):
                    guard let end = stringEnd(from: index, in: bytes) else {
                        return nil
                    }
                    index = end
                    continue
                case UInt8(ascii: "{"), UInt8(ascii: "["):
                    depth += 1
                case UInt8(ascii: "}"), UInt8(ascii: "]"):
                    depth -= 1
                    if depth == 0 {
                        return index + 1
                    }
                default:
                    break
                }
                index += 1
            }
            return nil
        default:
            var index = start
            while index < bytes.count, ![UInt8(ascii: ","), UInt8(ascii: "}"), UInt8(ascii: "]"), 0x20, 0x09, 0x0A, 0x0D].contains(bytes[index]) {
                index += 1
            }
            return index
        }
    }
}
