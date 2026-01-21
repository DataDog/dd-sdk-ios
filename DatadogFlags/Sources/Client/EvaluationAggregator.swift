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
    private let featureScope: any FeatureScope
    private let queue = DispatchQueue(label: "com.datadoghq.flags.evaluation-aggregator")
    private var aggregations: [AggregationKey: AggregatedEvaluation] = [:]
    private var flushTimer: Timer?

    init(
        dateProvider: any DateProvider,
        featureScope: any FeatureScope,
        flushInterval: TimeInterval = 10.0,
        maxAggregations: Int = 1_000
    ) {
        self.dateProvider = dateProvider
        self.featureScope = featureScope
        self.flushInterval = min(max(flushInterval, 1.0), 60.0)
        self.maxAggregations = maxAggregations

        startFlushTimer()
    }

    deinit {
        stopFlushTimer()
        flush()
    }

    func recordEvaluation(
        for flagKey: String,
        assignment: FlagAssignment,
        evaluationContext: FlagsEvaluationContext,
        flagError: String?
    ) {
        let workItem = DispatchWorkItem { [self] in
            let errorMessage = flagError
            let now = self.dateProvider.now.timeIntervalSince1970.dd.toInt64Milliseconds

            let key = AggregationKey(
                flagKey: flagKey,
                variantKey: assignment.variationKey,
                allocationKey: assignment.allocationKey,
                targetingKey: evaluationContext.targetingKey,
                errorMessage: errorMessage,
                context: evaluationContext.attributes
            )

            if var existing = self.aggregations[key] {
                existing.evaluationCount += 1
                existing.lastEvaluation = now
                self.aggregations[key] = existing
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

                self.aggregations[key] = aggregated
            }

            if self.aggregations.count >= self.maxAggregations {
                self.flush()
            }
        }
        queue.async(execute: workItem)
    }

    func flush() {
        flush(completion: nil)
    }

    internal func flush(completion: (() -> Void)?) { // completion handler is for testing
        queue.async { // strong capture ensures flush completes even if called from deinit
            let evaluationsToSend = Array(self.aggregations.values)
            self.aggregations.removeAll()

            guard !evaluationsToSend.isEmpty else {
                completion?()
                return
            }

            self.featureScope.eventWriteContext { _, writer in
                for aggregated in evaluationsToSend {
                    let event = aggregated.toFlagEvaluationEvent()
                    writer.write(value: event)
                }
            }

            completion?()
        }
    }

    private func startFlushTimer() {
        DispatchQueue.main.async {
            self.flushTimer = Timer.scheduledTimer(
                withTimeInterval: self.flushInterval,
                repeats: true
            ) { [weak self] _ in
                self?.flush()
            }
        }
    }

    private func stopFlushTimer() {
        DispatchQueue.main.async {
            self.flushTimer?.invalidate()
            self.flushTimer = nil
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
        self.contextHash = context.keys.sorted().joined(separator: ",").hashValue
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
