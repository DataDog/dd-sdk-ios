/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2026-Present Datadog, Inc.
 */

import CryptoKit
import Foundation

internal enum RulesReason: String, Decodable {
    case staticValue = "STATIC", targetingMatch = "TARGETING_MATCH", split = "SPLIT"
    case defaultValue = "DEFAULT", disabled = "DISABLED", error = "ERROR"
}

internal enum RulesErrorCode: String, Decodable {
    case flagNotFound = "FLAG_NOT_FOUND", parseError = "PARSE_ERROR"
    case typeMismatch = "TYPE_MISMATCH", targetingKeyMissing = "TARGETING_KEY_MISSING"
}

internal struct RulesEvaluation: Equatable {
    let value: RulesValue
    let reason: RulesReason
    var variant: String?
    var allocationKey: String?
    var doLog: Bool = false
    var splitSerialID: UInt64?
    var errorCode: RulesErrorCode?
    var preparationError: RulesPreparationError?
    let evaluatedAt: Date
    let observeFullEvaluationData: Bool
}

internal struct RulesEvaluator {
    let configuration: RulesConfiguration

    func evaluate(
        flagKey: String,
        type: RulesValueType,
        defaultValue: RulesValue,
        context: RulesContext,
        at date: Date
    ) -> RulesEvaluation {
        func fallback(_ reason: RulesReason, error: RulesErrorCode? = nil, issue: RulesPreparationError? = nil) -> RulesEvaluation {
            RulesEvaluation(
                value: defaultValue,
                reason: reason,
                errorCode: error,
                preparationError: issue,
                evaluatedAt: date,
                observeFullEvaluationData: configuration.observeFullEvaluationData == true
            )
        }

        guard let entry = configuration.flags[flagKey] else {
            return fallback(.error, error: .flagNotFound)
        }
        let flag: RulesFlag
        switch entry {
        case .valid(let prepared): flag = prepared
        case .invalid(let issue): return fallback(.error, error: .parseError, issue: issue)
        }
        guard flag.enabled else {
            return fallback(.disabled)
        }
        guard type == flag.variationType.valueType, defaultValue.type == type else {
            return fallback(.error, error: .typeMismatch)
        }

        for allocation in flag.allocations where allocation.matches(context, at: date) {
            for split in allocation.splits {
                var matches = true
                for shard in split.shards {
                    guard let key = context.targetingKey else {
                        return fallback(.error, error: .targetingKeyMissing)
                    }
                    let bucket = Self.shard(salt: shard.salt, targetingKey: key, totalShards: shard.totalShards)
                    if !shard.ranges.contains(where: { $0.start <= bucket && bucket < $0.end }) {
                        matches = false
                        break
                    }
                }
                guard matches, let variation = flag.variations[split.variationKey] else {
                    continue
                }
                let reason: RulesReason
                if !(allocation.rules?.isEmpty ?? true) {
                    reason = .targetingMatch
                } else if !split.shards.isEmpty {
                    reason = .split
                } else if allocation.startAt != nil || allocation.endAt != nil {
                    reason = .defaultValue
                } else {
                    reason = .staticValue
                }
                return RulesEvaluation(
                    value: variation.value,
                    reason: reason,
                    variant: variation.key,
                    allocationKey: allocation.key,
                    doLog: allocation.doLog == true,
                    splitSerialID: split.serialId,
                    evaluatedAt: date,
                    observeFullEvaluationData: configuration.observeFullEvaluationData == true
                )
            }
        }
        return fallback(.defaultValue)
    }

    static func shard(salt: String, targetingKey: String, totalShards: Int) -> Int {
        // Configuration validation makes modulo safe. MD5 is the assignment protocol, not a security primitive.
        let digest = Insecure.MD5.hash(data: Data("\(salt)-\(targetingKey)".utf8))
        let prefix = digest.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        return Int(prefix) % totalShards
    }
}
