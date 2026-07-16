/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-Present Datadog, Inc.
*/

/// Values of `OTSpan`tags.
public typealias OTTagValue = Encodable & Sendable

private let specialSpanTagKeys: Set<String> = [SpanTags.resource, SpanTags.operation, SpanTags.service]

/// Recursively flattens a tag value into leaf `(key, value)` pairs. A `Dictionary` value is expanded under
/// `"\(key).\(subKey)"`, recursively; any other value is returned unchanged as a single pair.
///
/// Same idea as `Dictionary<String, OpenTelemetryApi.AttributeValue>.tags` in
/// `OTelAttributeValue+Datadog.swift`, for OTel attributes instead of arbitrary `Encodable` tag values — the two
/// can't share code (different source types: a closed OTel enum there, vs. any `Encodable` here). Known,
/// accepted inconsistency between them: an empty `Dictionary` here produces no tags at all, while an empty
/// collection there produces one tag with value `""`. Not unified on purpose — each matches the natural default
/// for its own source type, and a caller working with plain dictionary tags never sees the OTel path or vice
/// versa — but any further change to one's flattening rules is still worth checking against the other.
internal func flattenedTagPairs(key: String, value: OTTagValue) -> [(String, OTTagValue)] {
    guard let dict = value as? [String: OTTagValue] else {
        return [(key, value)]
    }
    return flattenedTagPairs(key: key, dict: dict)
}

/// Same as `flattenedTagPairs(key:value:)`, for a value that's already known to be a `Dictionary` — e.g. an
/// `OTSpan.setTag(key:value:)` overload parameter, which can't itself be passed as a single `OTTagValue` (a
/// `[String: OTTagValue]` doesn't conform to `Encodable`).
///
/// Processes `dict`'s own entries in key-sorted order — same rationale as `flattenedTags(_:)` below — so a
/// same-dictionary collision reached through this entry point (e.g. a single `setTag(key:value: [String:
/// OTTagValue])` call, which never goes through `flattenedTags(_:)`) is just as deterministic as one reached
/// through it.
internal func flattenedTagPairs(key: String, dict: [String: OTTagValue]) -> [(String, OTTagValue)] {
    let pairs = dict.sorted { $0.key < $1.key }.flatMap { flattenedTagPairs(key: "\(key).\($0.key)", value: $0.value) }
    let specialKeys = Set(pairs.map { $0.0 }).intersection(specialSpanTagKeys).sorted()
    _ = warn(
        if: !specialKeys.isEmpty,
        message: """
        Flattening a dictionary span tag produced special Datadog tag key(s): \
        \(specialKeys.map { "\"\($0)\"" }.joined(separator: ", ")). These tags keep their usual semantics and \
        may override the span's resource, operation, or service name, the same as setting those keys directly.
        """
    )
    return pairs
}

/// Flattens every entry of `tags`, applying the same key-sorted determinism as `flattenedTagPairs(key:dict:)`
/// at the top level too (e.g. for a same-dictionary collision between a literal `"a.b"` key and an `"a":
/// ["b": ...]` entry — an unusual input, but not one this function should resolve arbitrarily).
///
/// Warns if that collision actually occurs (same mechanism `DDSpan.storeFlattenedTags` uses for the identical
/// shape reached via `setTag`) — this function is `DatadogTracer`'s only entry point for flattening global/
/// initial tags, so it's the only place that could otherwise silently drop one of them with zero diagnostic.
internal func flattenedTags(_ tags: [String: OTTagValue]) -> [String: OTTagValue] {
    let pairs = tags.sorted { $0.key < $1.key }.flatMap { flattenedTagPairs(key: $0.key, value: $0.value) }
    let uniqueKeyCount = Set(pairs.map { $0.0 }).count
    _ = warn(
        if: uniqueKeyCount != pairs.count,
        message: """
        Two configured tags collide once flattened (e.g. a literal "a.b" key alongside a nested "a": \
        ["b": ...] entry) — only one of them was kept.
        """
    )
    return Dictionary(pairs, uniquingKeysWith: { _, new in new })
}

/// Merges tracer-level default tags with per-span user tags, user tags winning on key collision.
///
/// `global` must already be flattened — `DatadogTracer.init` does this once for its whole lifetime, so this
/// function only flattens `user`, rather than redoing `global`'s flattening on every call (`DatadogTracer.startSpan`
/// calls this once per span created). A collision that's only visible after flattening `user` (e.g. a global tag
/// literally keyed `"a.b"` colliding with a user tag `["a": ["b": ...]]`) still resolves by the "user wins" rule
/// below, since `global` arrives pre-flattened and `user` is flattened here before merging.
///
/// Before merging, drops every `global` leaf under one of `user`'s own top-level keys (exact match, or a
/// `"key."`-prefixed child) — otherwise a global dictionary tag, once flattened into leaves at init, no longer
/// has a single key a per-span override could collide with, so e.g. a global `["context": ["foo": "x"]]`
/// (flattened to `"context.foo"`) would sit alongside a per-span `setTag(key: "context", value: "y")` instead
/// of being replaced by it, unlike before flattening existed (when both were a single literal `"context"` key).
internal func mergeTags(global: [String: OTTagValue], user: [String: OTTagValue]?) -> [String: OTTagValue] {
    guard let user, !user.isEmpty else {
        return global
    }
    var reducedGlobal = global
    for key in user.keys {
        reducedGlobal = reducedGlobal.filter { $0.key != key && !$0.key.hasPrefix("\(key).") }
    }
    return reducedGlobal.merging(flattenedTags(user)) { _, user in user }
}
