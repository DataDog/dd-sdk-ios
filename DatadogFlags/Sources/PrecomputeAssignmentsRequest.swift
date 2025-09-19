/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

// MARK: - Request Models

/// Encodable model for the "precompute-assignments-request" payload
internal struct PrecomputeAssignmentsRequest: Encodable {
    let data: DataContainer

    struct DataContainer: Encodable {
        let type: String
        let attributes: Attributes
    }

    struct Attributes: Encodable {
        let environment: Environment
        let subject: Subject

        struct Environment: Encodable {
            let name: String
            let ddEnv: String

            enum CodingKeys: String, CodingKey {
                case name
                case ddEnv = "dd_env"
            }
        }

        struct Subject: Encodable {
            let targetingKey: String
            let targetingAttributes: [String: String]

            enum CodingKeys: String, CodingKey {
                case targetingKey = "targeting_key"
                case targetingAttributes = "targeting_attributes"
            }
        }
    }
}
