/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
internal import SwiftProtobuf

/// The rules-based flags configuration, as the client rules endpoint serves it.
internal typealias RulesConfiguration = Datadog_Ffe_Flagging_Ufc_V1_FlagsConfiguration

/// Decodes the protobuf body of the client rules endpoint.
internal enum RulesConfigurationDecoder {
    /// Decodes a rules-based flags configuration.
    ///
    /// Unknown fields are kept, so a newer backend schema does not break this SDK version.
    /// - Throws: `RulesConfigurationDecodingError.invalidData` if `data` is not a valid configuration.
    static func decode(_ data: Data) throws -> RulesConfiguration {
        do {
            return try RulesConfiguration(serializedBytes: data)
        } catch {
            throw RulesConfigurationDecodingError.invalidData
        }
    }
}

/// An error that occurs when the rules-based configuration cannot be decoded.
internal enum RulesConfigurationDecodingError: Error, Equatable {
    /// The data is not a valid protobuf flags configuration.
    case invalidData
}
