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
    // Optional for compatibility with snapshots written before opt-out support.
    let experimentationOptOut: Bool?
    let experimentationOptOutPolicy: ExperimentationOptOut?

    var effectiveOptOut: ExperimentationOptOut? {
        experimentationOptOutPolicy ?? (experimentationOptOut == true ? .immediate : nil)
    }

    init(
        flags: [String: FlagAssignment],
        context: FlagsEvaluationContext,
        date: Date,
        obfuscation: FlagKeyObfuscation? = nil,
        experimentationOptOut: Bool? = nil,
        experimentationOptOutPolicy: ExperimentationOptOut? = nil
    ) {
        self.flags = flags
        self.context = context
        self.date = date
        self.obfuscation = obfuscation
        self.experimentationOptOut = experimentationOptOut
        self.experimentationOptOutPolicy = experimentationOptOutPolicy
    }
}
