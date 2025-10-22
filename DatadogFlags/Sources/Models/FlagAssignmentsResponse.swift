/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

internal struct FlagAssignmentsResponse: Equatable {
    let flags: [String: FlagAssignment]
    let failedFlags: [String: String] // key -> error description

    init(flags: [String: FlagAssignment], failedFlags: [String: String] = [:]) {
        self.flags = flags
        self.failedFlags = failedFlags
    }
}

extension FlagAssignmentsResponse: Codable {
    private enum CodingKeys: String, CodingKey {
        case data
        case attributes
        case flags
    }

    init(from decoder: any Decoder) throws {
        let rootContainer = try decoder.container(keyedBy: CodingKeys.self)
        let dataContainer = try rootContainer.nestedContainer(keyedBy: CodingKeys.self, forKey: .data)
        let attributesContainer = try dataContainer.nestedContainer(keyedBy: CodingKeys.self, forKey: .attributes)

        // Decode all flags (including those with unknown variation types)
        let allFlags = try attributesContainer.decode([String: FlagAssignment].self, forKey: .flags)

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
    }
}
