/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

internal struct FlagsData: Equatable, Codable {
    var flags: [String: FlagAssignment]
    /// Plaintext assignments that `flags` cannot hold beside a canonically equivalent key.
    var keySpellings: [FlagKeySpelling]
    var flagEvaluationErrors: [String: FlagEvaluationFailure]
    /// Plaintext errors that `flagEvaluationErrors` cannot hold beside a canonically equivalent key.
    var errorKeySpellings: [FlagEvaluationErrorSpelling]
    var context: FlagsEvaluationContext
    var date: Date
    let obfuscation: FlagKeyObfuscation?
    let flagSelection: CanonicalFlagSelection?
    // Optional so snapshots written before opt-out support remain readable.
    let experimentationOptOutPolicy: ExperimentationOptOut?
    let observeFullEvaluationData: Bool
    /// Served keys whose assignment the SDK cannot parse. Their evaluations report a parse error, not a missing flag.
    /// An earlier reader ignores this field and reports these keys as missing, as it did before.
    var unparsedFlagKeys: [String]

    init(
        flags: [String: FlagAssignment],
        flagEvaluationErrors: [String: FlagEvaluationFailure] = [:],
        context: FlagsEvaluationContext,
        date: Date,
        obfuscation: FlagKeyObfuscation? = nil,
        flagSelection: CanonicalFlagSelection? = nil,
        experimentationOptOutPolicy: ExperimentationOptOut? = nil,
        observeFullEvaluationData: Bool = false,
        keySpellings: [FlagKeySpelling] = [],
        errorKeySpellings: [FlagEvaluationErrorSpelling] = [],
        unparsedFlagKeys: [String] = []
    ) {
        self.flags = flags.mapValues { assignment in
            var assignment = assignment
            assignment.observeFullEvaluationData = observeFullEvaluationData
            return assignment
        }
        self.keySpellings = keySpellings.map { spelling in
            var spelling = spelling
            spelling.assignment.observeFullEvaluationData = observeFullEvaluationData
            return spelling
        }
        self.flagEvaluationErrors = flagEvaluationErrors
        self.errorKeySpellings = errorKeySpellings
        self.context = context
        self.date = date
        self.obfuscation = obfuscation
        self.flagSelection = flagSelection
        self.experimentationOptOutPolicy = experimentationOptOutPolicy
        self.observeFullEvaluationData = observeFullEvaluationData
        self.unparsedFlagKeys = unparsedFlagKeys
    }

    private enum CodingKeys: String, CodingKey {
        case flags, keySpellings, flagEvaluationErrors, errorKeySpellings, context, date, obfuscation, flagSelection
        case experimentationOptOutPolicy, observeFullEvaluationData, unparsedFlagKeys
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            flags: try container.decode([String: FlagAssignment].self, forKey: .flags),
            flagEvaluationErrors: try container.decodeIfPresent(
                [String: FlagEvaluationFailure].self,
                forKey: .flagEvaluationErrors
            ) ?? [:],
            context: try container.decode(FlagsEvaluationContext.self, forKey: .context),
            date: try container.decode(Date.self, forKey: .date),
            obfuscation: try container.decodeIfPresent(FlagKeyObfuscation.self, forKey: .obfuscation),
            flagSelection: try container.decodeIfPresent(CanonicalFlagSelection.self, forKey: .flagSelection),
            experimentationOptOutPolicy: try container.decodeIfPresent(ExperimentationOptOut.self, forKey: .experimentationOptOutPolicy),
            observeFullEvaluationData: (try? container.decode(Bool.self, forKey: .observeFullEvaluationData)) == true,
            keySpellings: try container.decodeIfPresent([FlagKeySpelling].self, forKey: .keySpellings) ?? [],
            errorKeySpellings: try container.decodeIfPresent(
                [FlagEvaluationErrorSpelling].self,
                forKey: .errorKeySpellings
            ) ?? [],
            unparsedFlagKeys: try container.decodeIfPresent([String].self, forKey: .unparsedFlagKeys) ?? []
        )
        let assignmentKeys = flags.keys.map { Data($0.utf8) }
            + keySpellings.map { Data($0.key.utf8) }
            + unparsedFlagKeys.map { Data($0.utf8) }
        let errorKeys = flagEvaluationErrors.keys.map { Data($0.utf8) } + errorKeySpellings.map { Data($0.key.utf8) }
        guard Set(assignmentKeys).isDisjoint(with: Set(errorKeys)) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: container.codingPath,
                debugDescription: "A flag cannot contain both an assignment and an evaluation error"
            ))
        }
        if let obfuscation {
            guard keySpellings.isEmpty, errorKeySpellings.isEmpty else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: container.codingPath,
                    debugDescription: "Obfuscated flag keys cannot use plaintext spelling sidecars"
                ))
            }
            try obfuscation.validateKeys(flags.keys, codingPath: container.codingPath + [CodingKeys.flags])
            try obfuscation.validateKeys(
                unparsedFlagKeys,
                codingPath: container.codingPath + [CodingKeys.unparsedFlagKeys]
            )
            try obfuscation.validateErrorKeys(
                flagEvaluationErrors.keys,
                codingPath: container.codingPath + [CodingKeys.flagEvaluationErrors]
            )
            try obfuscation.validateDependencyEvaluations(in: flags.values, and: flagEvaluationErrors.values)
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(flags, forKey: .flags)
        if !keySpellings.isEmpty {
            try container.encode(keySpellings, forKey: .keySpellings)
        }
        if !flagEvaluationErrors.isEmpty {
            try container.encode(flagEvaluationErrors, forKey: .flagEvaluationErrors)
        }
        if !errorKeySpellings.isEmpty {
            try container.encode(errorKeySpellings, forKey: .errorKeySpellings)
        }
        try container.encode(context, forKey: .context)
        try container.encode(date, forKey: .date)
        try container.encodeIfPresent(obfuscation, forKey: .obfuscation)
        try container.encodeIfPresent(flagSelection, forKey: .flagSelection)
        try container.encodeIfPresent(experimentationOptOutPolicy, forKey: .experimentationOptOutPolicy)
        try container.encode(observeFullEvaluationData, forKey: .observeFullEvaluationData)
        if !unparsedFlagKeys.isEmpty {
            try container.encode(unparsedFlagKeys, forKey: .unparsedFlagKeys)
        }
    }

    /// Every served flag key, including the spellings in `keySpellings`.
    var allFlagKeys: [String] {
        Array(flags.keys) + keySpellings.map(\.key)
    }

    var containsDependentEvaluations: Bool {
        !flagEvaluationErrors.isEmpty
            || !errorKeySpellings.isEmpty
            || flags.values.contains(where: { !$0.dependencyEvaluations.isEmpty })
            || keySpellings.contains(where: { !$0.assignment.dependencyEvaluations.isEmpty })
    }

    var legacyCompatible: FlagsData {
        var data = self
        data.flags = flags.filter { $0.value.dependencyEvaluations.isEmpty }
        data.keySpellings = keySpellings.filter { $0.assignment.dependencyEvaluations.isEmpty }
        data.flagEvaluationErrors = [:]
        data.errorKeySpellings = []
        return data
    }
}

extension FlagsData: FlagNumericTokenRoot {
    static var flagAssignmentsPath: [String] { ["flags"] }
}
