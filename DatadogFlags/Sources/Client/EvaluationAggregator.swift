/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import CryptoKit
import Foundation
import DatadogInternal

internal final class EvaluationAggregator {
    private let flushInterval: TimeInterval
    private let maxAggregations: Int
    private let dateProvider: any DateProvider
    private let featureScope: FeatureScope
    @ReadWriteLock
    private var aggregations: [AggregationKey: AggregatedEvaluation] = [:]
    @ReadWriteLock
    private var lastTargetingKey: TelemetryTargetingKey?
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
        let errorMessage = (flagError ?? (assignment.reason == "ERROR" ? "GENERAL" : nil)).map { error in
            switch error {
            case "PROVIDER_NOT_READY", "PROVIDER_FATAL", "FLAG_NOT_FOUND", "PARSE_ERROR",
                 "TYPE_MISMATCH", "TARGETING_KEY_MISSING", "INVALID_CONTEXT", "GENERAL":
                return error
            default:
                return "GENERAL"
            }
        }
        let observeFullEvaluationData = assignment.observeFullEvaluationData
        let targetingKey = evaluationContext.hasTargetingKey
            ? telemetryTargetingKey(for: evaluationContext.targetingKey, observeFullEvaluationData: observeFullEvaluationData)
            : nil
        // AnyValue, Array and Dictionary are value types: this is an owned copy-on-write value.
        let context = observeFullEvaluationData ? evaluationContext.attributes : [:]
        let now = dateProvider.now.timeIntervalSince1970.dd.toInt64Milliseconds

        let key = AggregationKey(
            flagKey: flagKey,
            variantKey: assignment.variationKey,
            allocationKey: assignment.allocationKey,
            targetingKey: targetingKey,
            errorMessage: errorMessage,
            context: context,
            observeFullEvaluationData: observeFullEvaluationData
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
                    targetingKey: targetingKey,
                    targetingRuleKey: nil,
                    errorMessage: errorMessage,
                    context: context,
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

    private func telemetryTargetingKey(for source: String, observeFullEvaluationData: Bool) -> String? {
        // Swift `==` treats canonically equivalent strings as equal, but their UTF-8 bytes and hashes differ.
        if let cached = lastTargetingKey,
           cached.observeFullEvaluationData == observeFullEvaluationData,
           (cached.source as NSString).isEqual(to: source) {
            return cached.value
        }
        let entry = TelemetryTargetingKey(source: source, observeFullEvaluationData: observeFullEvaluationData)
        lastTargetingKey = entry
        return entry.value
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

/// The targeting key as sent in evaluation telemetry: `sha256_` and the lowercase hex SHA-256 of its UTF-8 bytes
/// without full-data consent, or nil when the key is not valid UTF-16.
internal struct TelemetryTargetingKey {
    let source: String
    let observeFullEvaluationData: Bool
    let value: String?

    init(source: String, observeFullEvaluationData: Bool) {
        self.source = source
        self.observeFullEvaluationData = observeFullEvaluationData
        self.value = Self.value(for: source, observeFullEvaluationData: observeFullEvaluationData)
    }

    private static let hexDigits = Array("0123456789abcdef".utf8)

    private static func value(for source: String, observeFullEvaluationData: Bool) -> String? {
        guard !source.isEmpty else {
            return source
        }
        // A bridged NSString can hold unpaired surrogates, which `String.utf8` replaces with U+FFFD.
        guard let bytes = (source as NSString).data(using: String.Encoding.utf8.rawValue, allowLossyConversion: false) else {
            return nil
        }
        guard !observeFullEvaluationData else {
            return source
        }
        var hex: [UInt8] = []
        hex.reserveCapacity(2 * SHA256.byteCount)
        for byte in SHA256.hash(data: bytes) {
            hex.append(hexDigits[Int(byte >> 4)])
            hex.append(hexDigits[Int(byte & 0x0f)])
        }
        return "sha256_" + String(decoding: hex, as: UTF8.self)
    }
}

private struct AggregationKey: Hashable {
    let flagKey: String
    let variantKey: String
    let allocationKey: String
    let targetingKey: String?
    let errorMessage: String?
    let context: [String: AnyValue]
    let observeFullEvaluationData: Bool

    init(
        flagKey: String,
        variantKey: String,
        allocationKey: String,
        targetingKey: String?,
        errorMessage: String?,
        context: [String: AnyValue],
        observeFullEvaluationData: Bool
    ) {
        self.flagKey = flagKey
        self.variantKey = variantKey
        self.allocationKey = allocationKey
        self.targetingKey = targetingKey
        self.errorMessage = errorMessage
        self.context = context
        self.observeFullEvaluationData = observeFullEvaluationData
    }
}

private struct AggregatedEvaluation {
    let flagKey: String
    let variantKey: String
    let allocationKey: String
    let targetingKey: String?
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
