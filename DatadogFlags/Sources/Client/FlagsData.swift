/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

internal struct FlagsData: Equatable, Codable {
    var flags: [String: FlagAssignment]
    var context: FlagsEvaluationContext
    var date: Date
    let obfuscation: FlagKeyObfuscation?
    let observeFullEvaluationData: Bool

    init(flags: [String: FlagAssignment], context: FlagsEvaluationContext, date: Date, obfuscation: FlagKeyObfuscation? = nil, observeFullEvaluationData: Bool = false) {
        self.flags = flags.mapValues { assignment in
            var assignment = assignment
            assignment.observeFullEvaluationData = observeFullEvaluationData
            return assignment
        }
        self.context = context
        self.date = date
        self.obfuscation = obfuscation
        self.observeFullEvaluationData = observeFullEvaluationData
    }

    private enum CodingKeys: String, CodingKey {
        case flags, context, date, obfuscation, observeFullEvaluationData
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            flags: try container.decode([String: FlagAssignment].self, forKey: .flags),
            context: try container.decode(FlagsEvaluationContext.self, forKey: .context),
            date: try container.decode(Date.self, forKey: .date),
            obfuscation: try container.decodeIfPresent(FlagKeyObfuscation.self, forKey: .obfuscation),
            observeFullEvaluationData: (try? container.decode(Bool.self, forKey: .observeFullEvaluationData)) == true
        )
    }
}

/// One read of the configuration used by an evaluation, including missing-flag results.
internal struct FlagEvaluationSnapshot {
    let context: FlagsEvaluationContext
    let assignment: FlagAssignment?
    let observeFullEvaluationData: Bool
}
