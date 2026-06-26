---
name: dd-sdk-ios:swift-api-design
description: Use when writing, reviewing, or renaming Swift APIs, including declarations, call sites, argument labels, Boolean names, protocols, overloads, documentation comments, and small abstractions.
---

# Swift API Design

Use Swift's API Design Guidelines for clear call sites. Prefer the smallest API that preserves meaning.

Reference: https://www.swift.org/documentation/api-design-guidelines/

## Review

Before adding or renaming a Swift declaration:

1. Read call sites first; isolated declarations can mislead.
2. Search nearby terms, helpers, and overloads. Reuse same-concept names.
3. Draft the one-sentence documentation summary. Redesign if it needs caveats, implementation details, or repeated type names.
4. Add helpers, types, overloads, or wrappers only for real concepts, meaningful repetition, or bug prevention.
5. Re-read final use sites as English. Fix anything artificial, vague, redundant, or ambiguous.

## Names

- Include words needed to avoid ambiguity.
- Omit words that repeat visible type information.
- Name values by role. Use established terms correctly.
- Avoid nonstandard abbreviations. Keep acronyms consistent with Swift casing, such as `URL`, `UTF8`, and `userID`.
- Prefer member APIs when there is a natural receiver.
- Use `make...` for factories that create new values.
- Use properties for cheap, side-effect-free state; methods for work, conversion, or effects.
- Give side-effect-free methods noun-phrase or prepositional names, such as `distance(to:)`; give mutating or side-effecting methods imperative verb names, such as `append(_:)`.
- Name mutating/nonmutating pairs consistently: `sort()` / `sorted()`, `append(_:)` / `appending(_:)`, `union(_:)` / `formUnion(_:)`.
- Name Booleans as positive assertions about the receiver, such as `isEmpty`, `hasBorder`, or `contains(_:)`.
- Name protocols for things as nouns, such as `Collection`; capabilities with `able`, `ible`, or `ing`, such as `Equatable`.

## Argument Labels

Design the whole call, not only the base name.

- Omit the first argument label only when the argument completes the base name or the initializer is a value-preserving conversion.
- Include the first label when it clarifies role, unit, source, destination, or narrowing conversion.
- Make the base name and labels form a clear phrase; do not force awkward grammar.
- Use labels to clarify weakly typed values such as `String`, `Int`, `Any`, `NSObject`, or `AnyObject`.
- Put prepositions where they make the call read naturally, such as `move(from:to:)` or `insert(_:at:)`.

## Overloads and Defaults

- Overloads must share one semantic operation. Different work needs different names.
- Avoid overloads that differ only by return type or weakly typed parameters.
- Defaults should keep common calls clean without hiding important behavior.
- Boolean arguments need clear labels. Prefer an enum when `true` and `false` are not self-explanatory.

## Reject These

- Helpers that wrap simple expressions, such as `hasA || hasB`, without improving the call site.
- Names based on implementation details instead of the caller's role.
- Types created only for future flexibility before a second real use or clear invariant exists.
- Vague verbs such as `process`, `handle`, or `perform` when the actual operation can be named.
