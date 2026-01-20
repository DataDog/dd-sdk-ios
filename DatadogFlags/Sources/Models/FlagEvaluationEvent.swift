/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

internal struct BatchedFlagEvaluations: Codable {
    let context: EvaluationContext?
    let flagEvaluations: [FlagEvaluationEvent]

    enum CodingKeys: String, CodingKey {
        case context
        case flagEvaluations
    }
}

internal struct EvaluationContext: Codable {
    let geo: GeoInfo?
    let device: DeviceInfo
    let os: OSInfo
    let service: String
    let version: String
    let env: String
    let rum: RUMInfo?

    struct GeoInfo: Codable {
        let countryIsoCode: String?
        let country: String?

        enum CodingKeys: String, CodingKey {
            case countryIsoCode = "country_iso_code"
            case country
        }
    }

    struct DeviceInfo: Codable {
        let name: String
        let type: String
        let brand: String
        let model: String
    }

    struct OSInfo: Codable {
        let name: String
        let version: String
    }

    struct RUMInfo: Codable {
        let application: ApplicationInfo?
        let view: ViewInfo?

        struct ApplicationInfo: Codable {
            let id: String?
        }

        struct ViewInfo: Codable {
            let url: String?
        }
    }

    enum CodingKeys: String, CodingKey {
        case geo
        case device
        case os
        case service
        case version
        case env
        case rum
    }
}

internal struct FlagEvaluationEvent: Equatable, Codable {
    struct Identifier: Equatable, Codable {
        let key: String
    }

    struct ErrorInfo: Equatable, Codable {
        let message: String
    }

    struct EvaluationEventContext: Equatable, Codable {
        let evaluation: [String: AnyValue]?
        let dd: DatadogInfo?

        struct DatadogInfo: Equatable, Codable {
            let service: String?
            let rum: RUMInfo?

            struct RUMInfo: Equatable, Codable {
                let application: ApplicationInfo?
                let view: ViewInfo?

                struct ApplicationInfo: Equatable, Codable {
                    let id: String?
                }

                struct ViewInfo: Equatable, Codable {
                    let url: String?
                }
            }
        }
    }

    let timestamp: Int64
    let flag: Identifier
    let firstEvaluation: Int64
    let lastEvaluation: Int64
    let evaluationCount: Int
    let variant: Identifier?
    let allocation: Identifier?
    let targetingRule: Identifier?
    let targetingKey: String?
    let runtimeDefaultUsed: Bool?
    let error: ErrorInfo?
    let context: EvaluationEventContext?

    enum CodingKeys: String, CodingKey {
        case timestamp
        case flag
        case firstEvaluation = "first_evaluation"
        case lastEvaluation = "last_evaluation"
        case evaluationCount = "evaluation_count"
        case variant
        case allocation
        case targetingRule = "targeting_rule"
        case targetingKey = "targeting_key"
        case runtimeDefaultUsed = "runtime_default_used"
        case error
        case context
    }
}
