/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal protocol EvaluationLogging {
    func logEvaluation(
        for flagKey: String,
        assignment: FlagAssignment,
        evaluationContext: FlagsEvaluationContext,
        flagError: String?
    )
}

internal final class EvaluationLogger: EvaluationLogging {
    private let aggregator: EvaluationAggregator

    init(aggregator: EvaluationAggregator) {
        self.aggregator = aggregator
    }

    func logEvaluation(
        for flagKey: String,
        assignment: FlagAssignment,
        evaluationContext: FlagsEvaluationContext,
        flagError: String?
    ) {
        aggregator.recordEvaluation(
            for: flagKey,
            assignment: assignment,
            evaluationContext: evaluationContext,
            flagError: flagError
        )
    }
}

internal final class NOPEvaluationLogger: EvaluationLogging {
    func logEvaluation(
        for flagKey: String,
        assignment: FlagAssignment,
        evaluationContext: FlagsEvaluationContext,
        flagError: String?
    ) {
        // No-op
    }
}
