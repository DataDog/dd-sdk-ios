/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2026-Present Datadog, Inc.
 */

import XCTest
@testable import RulesEvaluationPrototype

internal enum FixtureSupport {
    static let date = Date(timeIntervalSince1970: 1_790_553_600) // Fixed time within the fixture's active windows.

    static func data(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    static func evaluator() throws -> RulesEvaluator {
        RulesEvaluator(configuration: try RulesConfiguration.parse(data("ufc-config")))
    }

    static func cases() throws -> [FixtureCase] {
        try JSONDecoder().decode([FixtureCase].self, from: data("evaluation-cases"))
    }
}

internal struct FixtureCase: Decodable {
    struct Expected: Decodable {
        let value: RulesValue
        let reason: RulesReason
        let errorCode: RulesErrorCode?
    }

    let flag: String
    let targetingKey: String?
    let attributes: [String: RulesValue]
    let defaultValue: RulesValue
    let variationType: RulesVariationType
    let result: Expected

    func evaluate(with evaluator: RulesEvaluator) -> RulesEvaluation {
        evaluator.evaluate(
            flagKey: flag,
            type: variationType.valueType,
            defaultValue: defaultValue,
            context: RulesContext(targetingKey: targetingKey, attributes: attributes),
            at: FixtureSupport.date
        )
    }
}
