/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

internal struct FlagAssignmentsResponse: Equatable {
    let flags: [String: FlagAssignment]
    let failedFlags: [String: String] // key -> error description
    let obfuscation: FlagKeyObfuscation?
    let experimentationOptOut: Bool?
    let hasMalformedOptOutMetadata: Bool
    let experimentationOptOutMode: String?
    let experimentationOptOutAt: String?

    init(
        flags: [String: FlagAssignment],
        failedFlags: [String: String] = [:],
        obfuscation: FlagKeyObfuscation? = nil,
        experimentationOptOut: Bool? = nil,
        experimentationOptOutMode: String? = nil,
        experimentationOptOutAt: String? = nil,
        hasMalformedOptOutMetadata: Bool = false
    ) {
        self.flags = flags
        self.failedFlags = failedFlags
        self.obfuscation = obfuscation
        self.experimentationOptOut = experimentationOptOut
        self.experimentationOptOutMode = experimentationOptOutMode
        self.experimentationOptOutAt = experimentationOptOutAt
        self.hasMalformedOptOutMetadata = hasMalformedOptOutMetadata
    }
}

extension FlagAssignmentsResponse: Codable {
    private enum CodingKeys: String, CodingKey {
        case data
        case attributes
        case flags
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
        if let obfuscation {
            try attributesContainer.encode(true, forKey: .obfuscated)
            try attributesContainer.encode(obfuscation, forKey: .obfuscation)
        }
    }
}
