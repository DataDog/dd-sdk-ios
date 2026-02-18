/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal final class EvaluationAggregator {
    private let flushInterval: TimeInterval
    private let maxAggregations: Int
    private let dateProvider: any DateProvider
    private let featureScope: FeatureScope
    @ReadWriteLock
    private var aggregations: [AggregationKey: AggregatedEvaluation] = [:]
    private var flushTimer: Timer?

    init(
        dateProvider: any DateProvider,
        featureScope: FeatureScope,
        flushInterval: TimeInterval,
        maxAggregations: Int = 1_000
    ) {
        self.dateProvider = dateProvider
        self.featureScope = featureScope
        self.flushInterval = flushInterval
        self.maxAggregations = maxAggregations

        startFlushTimer()
    }

    deinit {
        flushTimer?.invalidate()
        // Note: We don't flush here due to exclusivity conflict with DatadogCore.stop()
    }

    func recordEvaluation(
        for flagKey: String,
        assignment: FlagAssignment,
        evaluationContext: FlagsEvaluationContext,
        flagError: String?
    ) {
        let errorMessage = flagError
        let now = dateProvider.now.timeIntervalSince1970.dd.toInt64Milliseconds

        let key = AggregationKey(
            flagKey: flagKey,
            variantKey: assignment.variationKey,
            allocationKey: assignment.allocationKey,
            targetingKey: evaluationContext.targetingKey,
            errorMessage: errorMessage,
            context: evaluationContext.attributes
        )

        var shouldFlush = false

        _aggregations.mutate { aggregations in
            if var existing = aggregations[key] {
                existing.evaluationCount += 1
                existing.lastEvaluation = now
                aggregations[key] = existing
            } else {
                let runtimeDefaultUsed = assignment.reason == "DEFAULT" || errorMessage != nil

                let aggregated = AggregatedEvaluation(
                    flagKey: flagKey,
                    variantKey: assignment.variationKey,
                    allocationKey: assignment.allocationKey,
                    targetingKey: evaluationContext.targetingKey,
                    targetingRuleKey: nil,
                    errorMessage: errorMessage,
                    context: evaluationContext.attributes,
                    firstEvaluation: now,
                    lastEvaluation: now,
                    evaluationCount: 1,
                    runtimeDefaultUsed: runtimeDefaultUsed ? true : nil
                )

                aggregations[key] = aggregated
            }

            shouldFlush = aggregations.count >= self.maxAggregations
        }

        if shouldFlush {
            sendEvaluations()
        }
    }

    func sendEvaluations() {
        var evaluationsToSend: [AggregatedEvaluation] = []

        _aggregations.mutate { aggregations in
            evaluationsToSend = Array(aggregations.values)
            aggregations.removeAll()
        }

        guard !evaluationsToSend.isEmpty else {
            return
        }

        featureScope.eventWriteContext { _, writer in
            for aggregated in evaluationsToSend {
                let event = aggregated.toFlagEvaluationEvent()
                writer.write(value: event)
            }
        }
    }

    private func startFlushTimer() {
        flushTimer = Timer.scheduledTimer(
            withTimeInterval: flushInterval,
            repeats: true
        ) { [weak self] _ in
            self?.sendEvaluations()
        }
    }
}

private struct AggregationKey: Hashable {
    let flagKey: String
    let variantKey: String
    let allocationKey: String
    let targetingKey: String
    let errorMessage: String?
    let contextHash: Int

    init(
        flagKey: String,
        variantKey: String,
        allocationKey: String,
        targetingKey: String,
        errorMessage: String?,
        context: [String: AnyValue]
    ) {
        self.flagKey = flagKey
        self.variantKey = variantKey
        self.allocationKey = allocationKey
        self.targetingKey = targetingKey
        self.errorMessage = errorMessage
        var hasher = Hasher()
        for key in context.keys.sorted() {
            hasher.combine(key)
            hasher.combine(context[key])
        }
        self.contextHash = hasher.finalize()
    }
}

private struct AggregatedEvaluation {
    let flagKey: String
    let variantKey: String
    let allocationKey: String
    let targetingKey: String
    let targetingRuleKey: String?
    let errorMessage: String?
    let context: [String: AnyValue]

    let firstEvaluation: Int64
    var lastEvaluation: Int64
    var evaluationCount: Int
    let runtimeDefaultUsed: Bool?

    func toFlagEvaluationEvent() -> FlagEvaluationEvent {
        let eventContext: FlagEvaluationEvent.EvaluationEventContext? = context.isEmpty ? nil : .init(
            evaluation: context,
            dd: nil
        )

        return FlagEvaluationEvent(
            timestamp: firstEvaluation,
            flag: .init(key: flagKey),
            firstEvaluation: firstEvaluation,
            lastEvaluation: lastEvaluation,
            evaluationCount: evaluationCount,
            variant: runtimeDefaultUsed == true ? nil : .init(key: variantKey),
            allocation: runtimeDefaultUsed == true ? nil : .init(key: allocationKey),
            targetingRule: targetingRuleKey.map { .init(key: $0) },
            targetingKey: targetingKey,
            runtimeDefaultUsed: runtimeDefaultUsed,
            error: errorMessage.map { .init(message: $0) },
            context: eventContext
        )
    }
}
