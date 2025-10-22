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

        // Manually decode flags dictionary to handle individual flag failures gracefully
        let flagsContainer = try attributesContainer.nestedContainer(keyedBy: DynamicCodingKey.self, forKey: .flags)

        var successfulFlags: [String: FlagAssignment] = [:]
        var failedFlags: [String: String] = [:]

        for key in flagsContainer.allKeys {
            do {
                let flagAssignment = try flagsContainer.decode(FlagAssignment.self, forKey: key)
                successfulFlags[key.stringValue] = flagAssignment
            } catch {
                // Store the error for telemetry logging
                failedFlags[key.stringValue] = String(describing: error)
            }
        }

        self.flags = successfulFlags
        self.failedFlags = failedFlags
    }

    // Helper for dynamic key decoding
    private struct DynamicCodingKey: CodingKey {
        var stringValue: String
        var intValue: Int?

        init(stringValue: String) {
            self.stringValue = stringValue
            self.intValue = nil
        }

        init?(intValue: Int) {
            self.stringValue = String(intValue)
            self.intValue = intValue
        }
    }

    func encode(to encoder: any Encoder) throws {
        var rootContainer = encoder.container(keyedBy: CodingKeys.self)
        var dataContainer = rootContainer.nestedContainer(keyedBy: CodingKeys.self, forKey: .data)
        var attributesContainer = dataContainer.nestedContainer(keyedBy: CodingKeys.self, forKey: .attributes)
        try attributesContainer.encode(flags, forKey: .flags)
    }
}
