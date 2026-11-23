/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import SwiftProtobuf

/// Compares every field of the SwiftProtobuf result with the hand-written result. Returns the paths that differ.
struct Comparator {
    var mismatches: [String] = []

    mutating func check<T: Equatable>(_ a: T, _ b: T, _ path: @autoclosure () -> String) {
        if a != b { mismatches.append("\(path()): \(a) != \(b)") }
    }

    mutating func config(_ g: PBConfig, _ h: UFCFlagsConfiguration) {
        check(g.hasCreatedAt, h.createdAt != nil, "createdAt.present")
        if let ts = h.createdAt { check(g.createdAt.seconds, ts.seconds, "createdAt.seconds"); check(g.createdAt.nanos, ts.nanos, "createdAt.nanos") }
        check(g.environmentName, h.environmentName, "environmentName")
        check(g.environmentID, h.environmentID, "environmentID")
        check(g.strings, h.strings, "strings")
        check(g.regexes, h.regexes, "regexes")
        check(g.jsonStrings, h.jsonStrings, "jsonStrings")
        check(g.observeFullEvaluationData, h.observeFullEvaluationData, "observeFullEvaluationData")
        check(g.hasEvaluatorParams, h.evaluatorParams != nil, "evaluatorParams.present")
        if let p = h.evaluatorParams {
            check(g.evaluatorParams.hasMaxDependencyDepth, p.maxDependencyDepth != nil, "evaluatorParams.maxDependencyDepth.present")
            check(g.evaluatorParams.maxDependencyDepth, p.maxDependencyDepth ?? 0, "evaluatorParams.maxDependencyDepth")
        }
        check(g.versions.count, h.versions.count, "versions.count")
        for (i, (gv, hv)) in zip(g.versions, h.versions).enumerated() {
            check(gv.components, hv.components, "versions[\(i)].components")
            check(gv.prerelease, hv.prerelease, "versions[\(i)].prerelease")
        }
        check(g.attributes.count, h.attributes.count, "attributes.count")
        for (i, (ga, ha)) in zip(g.attributes, h.attributes).enumerated() { attribute(ga, ha, "attributes[\(i)]") }
        check(g.conditions.count, h.conditions.count, "conditions.count")
        for (i, (gc, hc)) in zip(g.conditions, h.conditions).enumerated() { condition(gc, hc, "conditions[\(i)]") }
        check(Set(g.flags.keys), Set(h.flags.keys), "flags.keys")
        for (key, gf) in g.flags { if let hf = h.flags[key] { flag(gf, hf, "flags[\(key)]") } }
    }

    mutating func attribute(_ g: Datadog_Ffe_Flagging_Ufc_V1_AttributeReference, _ h: UFCAttributeReference, _ path: String) {
        switch (g.kind, h.kind) {
        case (nil, nil), (.targetingKey?, .targetingKey?): break
        case let (.attributePath(gp)?, .attributePath(hp)?):
            check(gp.segments.count, hp.segments.count, "\(path).segments.count")
            for (i, (gs, hs)) in zip(gp.segments, hp.segments).enumerated() {
                switch (gs.kind, hs.kind) {
                case (nil, nil): break
                case let (.objectKeyStringIndex(a)?, .objectKeyStringIndex(b)?): check(a, b, "\(path).segments[\(i)]")
                case let (.arrayIndex(a)?, .arrayIndex(b)?): check(a, b, "\(path).segments[\(i)]")
                default: mismatches.append("\(path).segments[\(i)].kind")
                }
            }
        default: mismatches.append("\(path).kind")
        }
    }

    mutating func condition(_ g: Datadog_Ffe_Flagging_Ufc_V1_Condition, _ h: UFCCondition, _ path: String) {
        switch (g.kind, h.kind) {
        case (nil, nil): break
        case let (.all(a)?, .all(b)?), let (.any(a)?, .any(b)?):
            check(a.conditionIndexes, b.conditionIndexes, "\(path).operands")
        case let (.numeric(a)?, .numeric(b)?):
            check(a.attributeIndex, b.attributeIndex, "\(path).attributeIndex")
            check(Int32(a.comparator.rawValue), b.comparator.raw, "\(path).comparator")
            check(a.comparand, b.comparand, "\(path).comparand")
        case let (.regex(a)?, .regex(b)?):
            check(a.attributeIndex, b.attributeIndex, "\(path).attributeIndex")
            check(a.regexIndex, b.regexIndex, "\(path).regexIndex")
            check(a.negate, b.negate, "\(path).negate")
        case let (.stringMembership(a)?, .stringMembership(b)?):
            check(a.attributeIndex, b.attributeIndex, "\(path).attributeIndex")
            check(a.stringIndexes, b.stringIndexes, "\(path).stringIndexes")
            check(a.negate, b.negate, "\(path).negate")
        case let (.sha256Membership(a)?, .sha256Membership(b)?):
            check(a.attributeIndex, b.attributeIndex, "\(path).attributeIndex")
            check(a.salt, b.salt, "\(path).salt")
            check(a.sha256, b.sha256, "\(path).sha256")
            check(a.negate, b.negate, "\(path).negate")
        case let (.attributePresence(a)?, .attributePresence(b)?):
            check(a.attributeIndex, b.attributeIndex, "\(path).attributeIndex")
            check(a.expectNull, b.expectNull, "\(path).expectNull")
        case let (.version(a)?, .version(b)?):
            check(a.attributeIndex, b.attributeIndex, "\(path).attributeIndex")
            check(Int32(a.comparator.rawValue), b.comparator.raw, "\(path).comparator")
            check(a.versionIndex, b.versionIndex, "\(path).versionIndex")
        case let (.stringComparison(a)?, .stringComparison(b)?):
            check(a.attributeIndex, b.attributeIndex, "\(path).attributeIndex")
            check(Int32(a.comparator.rawValue), b.comparator.raw, "\(path).comparator")
            check(a.stringIndex, b.stringIndex, "\(path).stringIndex")
            check(a.negate, b.negate, "\(path).negate")
        case let (.sha256StringComparison(a)?, .sha256StringComparison(b)?):
            check(a.attributeIndex, b.attributeIndex, "\(path).attributeIndex")
            check(a.salt, b.salt, "\(path).salt")
            check(Int32(a.comparator.rawValue), b.comparator.raw, "\(path).comparator")
            check(a.length, b.length, "\(path).length")
            check(a.sha256, b.sha256, "\(path).sha256")
            check(a.negate, b.negate, "\(path).negate")
        case let (.flagEvaluationStringMembership(a)?, .flagEvaluationStringMembership(b)?):
            check(a.flagKeyStringIndex, b.flagKeyStringIndex, "\(path).flagKeyStringIndex")
            check(a.variantKeyStringIndexes, b.variantKeyStringIndexes, "\(path).variantKeyStringIndexes")
            check(a.negate, b.negate, "\(path).negate")
        default: mismatches.append("\(path).kind")
        }
    }

    mutating func flag(_ g: Datadog_Ffe_Flagging_Ufc_V1_Flag, _ h: UFCFlag, _ path: String) {
        check(g.minimumFeatureLevel, h.minimumFeatureLevel, "\(path).minimumFeatureLevel")
        check(Int32(g.variationType.rawValue), h.variationType.raw, "\(path).variationType")
        check(g.variations.count, h.variations.count, "\(path).variations.count")
        for (i, (gv, hv)) in zip(g.variations, h.variations).enumerated() {
            check(gv.keyStringIndex, hv.keyStringIndex, "\(path).variations[\(i)].keyStringIndex")
            switch (gv.value, hv.value) {
            case (nil, nil): break
            case let (.stringValueIndex(a)?, .stringValueIndex(b)?): check(a, b, "\(path).variations[\(i)].value")
            case let (.integerValue(a)?, .integerValue(b)?): check(a, b, "\(path).variations[\(i)].value")
            case let (.numericValue(a)?, .numericValue(b)?): check(a, b, "\(path).variations[\(i)].value")
            case let (.booleanValue(a)?, .booleanValue(b)?): check(a, b, "\(path).variations[\(i)].value")
            case let (.jsonStringIndex(a)?, .jsonStringIndex(b)?): check(a, b, "\(path).variations[\(i)].value")
            default: mismatches.append("\(path).variations[\(i)].value.kind")
            }
        }
        check(g.allocations.count, h.allocations.count, "\(path).allocations.count")
        for (i, (ga, ha)) in zip(g.allocations, h.allocations).enumerated() { allocation(ga, ha, "\(path).allocations[\(i)]") }
    }

    mutating func allocation(_ g: Datadog_Ffe_Flagging_Ufc_V1_Allocation, _ h: UFCAllocation, _ path: String) {
        check(g.key, h.key, "\(path).key")
        check(g.hasTargetingConditionIndex, h.targetingConditionIndex != nil, "\(path).targetingConditionIndex.present")
        check(g.targetingConditionIndex, h.targetingConditionIndex ?? 0, "\(path).targetingConditionIndex")
        check(g.logExposureEvent, h.logExposureEvent, "\(path).logExposureEvent")
        check(g.hasRandomizationActivatedAt, h.randomizationActivatedAt != nil, "\(path).randomizationActivatedAt.present")
        if let ts = h.randomizationActivatedAt {
            check(g.randomizationActivatedAt.seconds, ts.seconds, "\(path).randomizationActivatedAt.seconds")
            check(g.randomizationActivatedAt.nanos, ts.nanos, "\(path).randomizationActivatedAt.nanos")
        }
        check(g.partitionKey.count, h.partitionKey.count, "\(path).partitionKey.count")
        for (i, (gk, hk)) in zip(g.partitionKey, h.partitionKey).enumerated() {
            switch (gk.kind, hk.kind) {
            case (nil, nil), (.time?, .time?): break
            case let (.shardMd5(a)?, .shardMD5(b)?):
                check(a.salt, b.salt, "\(path).partitionKey[\(i)].salt")
                check(a.attributeIndex, b.attributeIndex, "\(path).partitionKey[\(i)].attributeIndex")
                check(a.totalShards, b.totalShards, "\(path).partitionKey[\(i)].totalShards")
            default: mismatches.append("\(path).partitionKey[\(i)].kind")
            }
        }
        check(g.splits.count, h.splits.count, "\(path).splits.count")
        for (i, (gs, hs)) in zip(g.splits, h.splits).enumerated() {
            let p = "\(path).splits[\(i)]"
            check(gs.variationIndex, hs.variationIndex, "\(p).variationIndex")
            check(gs.hasSerialID, hs.serialID != nil, "\(p).serialID.present")
            check(gs.serialID, hs.serialID ?? 0, "\(p).serialID")
            check(Int32(gs.reason.rawValue), hs.reason.raw, "\(p).reason")
            check(gs.ranges.count, hs.ranges.count, "\(p).ranges.count")
            for (r, (gr, hr)) in zip(gs.ranges, hs.ranges).enumerated() {
                check(gr.hasFrom, hr.from != nil, "\(p).ranges[\(r)].from.present")
                check(gr.from, hr.from ?? 0, "\(p).ranges[\(r)].from")
                check(gr.hasTo, hr.to != nil, "\(p).ranges[\(r)].to.present")
                check(gr.to, hr.to ?? 0, "\(p).ranges[\(r)].to")
            }
            check(gs.features.count, hs.features.count, "\(p).features.count")
            for (f, (gf, hf)) in zip(gs.features, hs.features).enumerated() {
                check(gf.key, hf.key, "\(p).features[\(f)].key")
                check(gf.destinations, hf.destinations, "\(p).features[\(f)].destinations")
                switch (gf.value, hf.value) {
                case (nil, nil): break
                case let (.stringValue(a)?, .stringValue(b)?): check(a, b, "\(p).features[\(f)].value")
                case let (.numberValue(a)?, .numberValue(b)?): check(a, b, "\(p).features[\(f)].value")
                case let (.boolValue(a)?, .boolValue(b)?): check(a, b, "\(p).features[\(f)].value")
                default: mismatches.append("\(p).features[\(f)].value.kind")
                }
            }
        }
    }
}

// Raw values of the hand-written enums, for the comparison only.
extension UFCVariationType {
    var raw: Int32 {
        switch self {
        case .unspecified: return 0
        case .string: return 1
        case .integer: return 2
        case .numeric: return 3
        case .boolean: return 4
        case .json: return 5
        case .unrecognized(let value): return value
        }
    }
}

extension UFCNumericComparator {
    var raw: Int32 {
        switch self {
        case .unspecified: return 0
        case .lessThan: return 1
        case .lessThanOrEqual: return 2
        case .greaterThan: return 3
        case .greaterThanOrEqual: return 4
        case .unrecognized(let value): return value
        }
    }
}

extension UFCStringComparator {
    var raw: Int32 {
        switch self {
        case .unspecified: return 0
        case .startsWith: return 1
        case .endsWith: return 2
        case .contains: return 3
        case .unrecognized(let value): return value
        }
    }
}

extension UFCSHA256StringComparator {
    var raw: Int32 {
        switch self {
        case .unspecified: return 0
        case .startsWith: return 1
        case .endsWith: return 2
        case .unrecognized(let value): return value
        }
    }
}

extension UFCVersionComparator {
    var raw: Int32 {
        switch self {
        case .unspecified: return 0
        case .equal: return 1
        case .notEqual: return 2
        case .lessThan: return 3
        case .lessThanOrEqual: return 4
        case .greaterThan: return 5
        case .greaterThanOrEqual: return 6
        case .unrecognized(let value): return value
        }
    }
}

extension UFCReason {
    var raw: Int32 {
        switch self {
        case .unspecified: return 0
        case .targetingMatch: return 1
        case .split: return 2
        case .static: return 3
        case .default: return 4
        case .unrecognized(let value): return value
        }
    }
}
