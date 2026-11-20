/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

internal struct FlagAssignmentsResponse: Equatable {
    private(set) var flags: [String: FlagAssignment]
    /// Assignments whose keys are canonically equivalent to, but not byte-equal to, a key in `flags`.
    var keySpellings: [FlagKeySpelling] = []
    private(set) var failedFlags: [String: String] // key -> error description
    let obfuscation: FlagKeyObfuscation?
    let experimentationOptOut: Bool?
    let hasMalformedOptOutMetadata: Bool
    let experimentationOptOutMode: String?
    let experimentationOptOutAt: String?
    let observeFullEvaluationData: Bool

    init(
        flags: [String: FlagAssignment],
        failedFlags: [String: String] = [:],
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
        let isObfuscated = attributesContainer.contains(.obfuscated)
            ? try attributesContainer.decode(Bool.self, forKey: .obfuscated) : false
        if isObfuscated {
            let obfuscation = try attributesContainer.decode(FlagKeyObfuscation.self, forKey: .obfuscation)
            try obfuscation.validateKeys(allFlags.keys, codingPath: attributesContainer.codingPath + [CodingKeys.flags])
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
    }

    func encode(to encoder: any Encoder) throws {
        var rootContainer = encoder.container(keyedBy: CodingKeys.self)
        var dataContainer = rootContainer.nestedContainer(keyedBy: CodingKeys.self, forKey: .data)
        var attributesContainer = dataContainer.nestedContainer(keyedBy: CodingKeys.self, forKey: .attributes)
        try attributesContainer.encode(flags, forKey: .flags)
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

extension FlagAssignmentsResponse {
    /// Rebuilds the served plaintext keys that decoding merged into one canonically equivalent key.
    ///
    /// Decoding keeps one key of each group, but its value can come from another spelling in the group.
    /// So every member of a group is decoded again from its own bytes.
    func addingKeySpellings(from data: Data) -> FlagAssignmentsResponse {
        let bytes = Array(data)
        guard obfuscation == nil,
              Self.mayContainNonASCIIKeys(bytes),
              let members = JSONObjectMembers.members(at: Self.flagAssignmentsPath, in: bytes) else {
            return self
        }
        var groups: [String: [JSONObjectMembers.Member]] = [:]
        for member in members {
            groups[member.key, default: []].append(member)
        }
        var response = self
        for group in groups.values where Set(group.map { Array($0.key.utf8) }).count > 1 {
            response.flags.removeValue(forKey: group[0].key)
            response.failedFlags.removeValue(forKey: group[0].key)
            for member in group {
                guard var assignment = try? FlagsNumericJSON.decode(FlagAssignment.self, from: Data(bytes[member.value])) else {
                    continue
                }
                if case .unknown(let typeName) = assignment.variation {
                    if response.failedFlags[member.key] == nil {
                        response.failedFlags[member.key] = "Unrecognized variation type \(typeName)"
                    }
                    continue
                }
                assignment.observeFullEvaluationData = observeFullEvaluationData
                response.place(assignment, for: member.key)
            }
        }
        return response
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
