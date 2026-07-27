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
internal func flattenedTags(_ tags: [String: OTTagValue]) -> FlattenedTags {
    // Each triple keeps the top-level key (`owner`) that produced `leaf`/`value` alongside them, so ownership
    // can be assigned per surviving leaf below instead of per top-level key up front — otherwise a key that
    // loses a same-leaf collision (see the warning below) would still wrongly be recorded as that leaf's owner,
    // and a later `mergeTags` override of the losing key could drop a leaf it never actually produced.
    let triples = tags.sorted { $0.key < $1.key }.flatMap { entry in
        flattenedTagPairs(key: entry.key, value: entry.value).map { leaf, value in (leaf: leaf, value: value, owner: entry.key) }
    }
    let uniqueKeyCount = Set(triples.map { $0.leaf }).count
    _ = warn(
        if: uniqueKeyCount != triples.count,
        message: """
        Two configured tags collide once flattened (e.g. a literal "a.b" key alongside a nested "a": \
        ["b": ...] entry) — only one of them was kept.
        """
    )
    // Last-write-wins per leaf — same rule `Dictionary(pairs, uniquingKeysWith:)` applies below — but keeping
    // `value` and `owner` together in one dictionary so a leaf's recorded owner can never drift out of sync
    // with the value that actually won its collision.
    var winners: [String: (value: OTTagValue, owner: String)] = [:]
    for triple in triples {
        winners[triple.leaf] = (triple.value, triple.owner)
    }
    var owners: [String: Set<String>] = [:]
    for (leaf, winner) in winners {
        owners[winner.owner, default: []].insert(leaf)
    }
    return FlattenedTags(tags: winners.mapValues { $0.value }, owners: owners)
}

/// The result of flattening a group of tags: the flattened leaf tags themselves, plus, for each original
/// top-level key, exactly the leaves its value flattened into. `mergeTags` needs this ownership info to drop a
/// global dictionary tag's leaves on a per-span override of the same key — dropping every tag that merely
/// shares the `"key."` prefix instead would also erase an unrelated, independently-set literal dotted tag
/// (e.g. a global tag literally keyed `"context.foo"`, never a leaf of a `"context"` dictionary).
internal struct FlattenedTags {
    let tags: [String: OTTagValue]
    let owners: [String: Set<String>]
}

/// Removes `leaves` from every owner's set in `owners` — a leaf that just moved to a new owner can no longer be
/// claimed by whichever key used to own it. Shared by `DDSpan.storeFlattenedTags` (a single key takes over some
/// leaves) and `mergeTags` (a user tag takes over leaves a global key used to own).
internal func releaseOwnership(of leaves: Set<String>, in owners: inout [String: Set<String>]) {
    for key in owners.keys {
        owners[key]?.subtract(leaves)
    }
}

/// Merges tracer-level default tags with per-span user tags, user tags winning on key collision.
///
/// `global` must already be flattened — `DatadogTracer.init` does this once for its whole lifetime, so this
/// function only flattens `user`, rather than redoing `global`'s flattening on every call (`DatadogTracer.startSpan`
/// calls this once per span created). A collision that's only visible after flattening `user` (e.g. a global tag
/// literally keyed `"a.b"` colliding with a user tag `["a": ["b": ...]]`) still resolves by the "user wins" rule
/// below, since `global` arrives pre-flattened and `user` is flattened here before merging.
///
/// Before merging, drops only the leaves `global.owners[key]` actually recorded for one of `user`'s own
/// top-level keys, plus `key` itself — otherwise a global dictionary tag, once flattened into leaves at init,
/// no longer has a single key a per-span override could collide with, so e.g. a global `["context": ["foo":
/// "x"]]` (flattened to `"context.foo"`) would sit alongside a per-span `setTag(key: "context", value: "y")`
/// instead of being replaced by it, unlike before flattening existed (when both were a single literal
/// `"context"` key). Dropping every tag that merely shares the `"key."` prefix, instead of only tracked
/// leaves, would also erase an unrelated global tag literally keyed e.g. `"context.foo"` that was never a leaf
/// of a `"context"` dictionary — the same bug shape fixed in `DDSpan.storeFlattenedTags`.
internal func mergeTags(global: FlattenedTags, user: [String: OTTagValue]?) -> FlattenedTags {
    guard let user, !user.isEmpty else {
        return global
    }
    let flattenedUser = flattenedTags(user)
    let newLeafKeys = Set(flattenedUser.tags.keys)
    var reducedTags = global.tags
    var reducedOwners = global.owners
    for key in user.keys {
        let staleChildren = global.owners[key] ?? []
        reducedTags = reducedTags.filter { $0.key != key && !staleChildren.contains($0.key) }
        reducedOwners[key] = nil
    }
    // E.g. a global `"ctx": ["foo": ...]` (flattened to `"ctx.foo"`) later overridden by a user's own literal
    // `"ctx.foo"` tag — without this, "ctx" would still claim "ctx.foo" and a later per-span `setTag(key:
    // "ctx", ...)` would drop the user's own tag.
    releaseOwnership(of: newLeafKeys, in: &reducedOwners)
    return FlattenedTags(
        tags: reducedTags.merging(flattenedUser.tags) { _, user in user },
        owners: reducedOwners.merging(flattenedUser.owners) { _, user in user }
    )
}
