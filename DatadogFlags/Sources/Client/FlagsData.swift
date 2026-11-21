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
    var context: FlagsEvaluationContext
    var date: Date
    let obfuscation: FlagKeyObfuscation?
    let flagSelection: CanonicalFlagSelection?
    // Proofs are process-local and cannot be restored by decoding an ordinary disk cache.
    var verification: FlagsResponseVerification? = nil
    var responseSigningCacheScope: String? = nil
    // Optional so snapshots written before opt-out support remain readable.
    let experimentationOptOutPolicy: ExperimentationOptOut?
    let observeFullEvaluationData: Bool

    init(
        flags: [String: FlagAssignment],
        context: FlagsEvaluationContext,
        date: Date,
        obfuscation: FlagKeyObfuscation? = nil,
        flagSelection: CanonicalFlagSelection? = nil,
        experimentationOptOutPolicy: ExperimentationOptOut? = nil,
        observeFullEvaluationData: Bool = false,
        keySpellings: [FlagKeySpelling] = []
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
        self.context = context
        self.date = date
        self.obfuscation = obfuscation
        self.flagSelection = flagSelection
        self.experimentationOptOutPolicy = experimentationOptOutPolicy
        self.observeFullEvaluationData = observeFullEvaluationData
    }

    private enum CodingKeys: String, CodingKey {
        case flags, keySpellings, context, date, obfuscation, flagSelection, experimentationOptOutPolicy, observeFullEvaluationData
        case responseSigningCacheScope
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            flags: try container.decode([String: FlagAssignment].self, forKey: .flags),
            context: try container.decode(FlagsEvaluationContext.self, forKey: .context),
            date: try container.decode(Date.self, forKey: .date),
            obfuscation: try container.decodeIfPresent(FlagKeyObfuscation.self, forKey: .obfuscation),
            flagSelection: try container.decodeIfPresent(CanonicalFlagSelection.self, forKey: .flagSelection),
            experimentationOptOutPolicy: try container.decodeIfPresent(ExperimentationOptOut.self, forKey: .experimentationOptOutPolicy),
            observeFullEvaluationData: (try? container.decode(Bool.self, forKey: .observeFullEvaluationData)) == true,
            keySpellings: try container.decodeIfPresent([FlagKeySpelling].self, forKey: .keySpellings) ?? []
        )
        // Only the observe cache scope is persisted. A verification proof is never decoded from disk.
        responseSigningCacheScope = try container.decodeIfPresent(String.self, forKey: .responseSigningCacheScope)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(flags, forKey: .flags)
        if !keySpellings.isEmpty {
            try container.encode(keySpellings, forKey: .keySpellings)
        }
        try container.encode(context, forKey: .context)
        try container.encode(date, forKey: .date)
        try container.encodeIfPresent(obfuscation, forKey: .obfuscation)
        try container.encodeIfPresent(flagSelection, forKey: .flagSelection)
        try container.encodeIfPresent(experimentationOptOutPolicy, forKey: .experimentationOptOutPolicy)
        try container.encode(observeFullEvaluationData, forKey: .observeFullEvaluationData)
        try container.encodeIfPresent(responseSigningCacheScope, forKey: .responseSigningCacheScope)
    }

    /// Every served flag key, including the spellings in `keySpellings`.
    var allFlagKeys: [String] {
        Array(flags.keys) + keySpellings.map(\.key)
    }
}

extension FlagsData: FlagNumericTokenRoot {
    static var flagAssignmentsPath: [String] { ["flags"] }
}
