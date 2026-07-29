/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// An error that knows how to sanitize itself for telemetry sent to Datadog's own org.
///
/// By default, errors reported to telemetry go through strict sanitization that discards most
/// contextual information to avoid leaking sensitive data. This protocol is an opt-in mechanism:
/// conforming types report a richer, but still safe, sanitized context instead of the default fallback.
///
/// - Important: Do not retroactively conform a type you don't own (e.g. `NSError`, `URLError`) to this
///   protocol - a conformance is a single, global fact about a (Type, Protocol) pair, so a second,
///   conflicting conformance declared elsewhere would be silently discarded. For some foreign types
///   (e.g. `EncodingError`, `DecodingError`, `NSError`), `Telemetry` instead applies its own internal
///   sanitization with sensible defaults, handled centrally in `sanitizeForTelemetry(_:)`.
public protocol TelemetrySanitizableError {
    func sanitize() -> TelemetrySanitizedError
}

/// A sanitized, telemetry-safe description of an error - safe to forward to Datadog's internal telemetry.
public struct TelemetrySanitizedError {
    public var kind: String
    public let message: String
    public var stack: String?

    public init(kind: String, message: String, stack: String? = nil) {
        self.kind = kind
        self.message = message
        self.stack = stack
    }

    /// Describes `error` by its type name and default string interpolation.
    ///
    /// - Important: Only use this when `error`'s default `"\(error)"` description is known to be
    ///   safe - e.g. an enum whose cases carry no customer data. Never use it for a type that might
    ///   wrap arbitrary or customer-supplied values.
    public init(describing error: Error) {
        self.init(kind: "\(type(of: error))", message: "\(error)")
    }
}

/// Returns a `TelemetrySanitizedError` describing `error`, safe to forward to internal telemetry.
///
/// If `error` conforms to `TelemetrySanitizableError`, its own `sanitize()` is used as-is. Otherwise, it
/// falls back to Telemetry's default sanitization: common types (`EncodingError`, `DecodingError`,
/// `NSError`) get a safe, dedicated summary, while everything else is stripped down to its type name.
public func sanitizeForTelemetry(_ error: Error) -> TelemetrySanitizedError {
    if let sanitizable = error as? TelemetrySanitizableError {
        return sanitizable.sanitize()
    }
    if let encodingError = error as? EncodingError {
        return sanitize(encodingError)
    }
    if let decodingError = error as? DecodingError {
        return sanitize(decodingError)
    }
    if isNSErrorOrItsSubclass(error) {
        return sanitize(error as NSError)
    }
    let kind = "\(type(of: error))"
    return TelemetrySanitizedError(
        kind: kind,
        message: "\(kind) does not conform to TelemetrySanitizableError — reporting type name only",
        stack: "Implement TelemetrySanitizableError on \(kind) to report richer, safe context."
    )
}

/// Sanitizes `EncodingError` for telemetry - only `context.debugDescription`/`codingPath`, never the raw
/// offending value that `EncodingError.invalidValue(_:_:)` embeds as its first associated value.
private func sanitize(_ error: EncodingError) -> TelemetrySanitizedError {
    let context: EncodingError.Context
    let kind: String
    switch error {
    case .invalidValue(_, let ctx):
        context = ctx
        kind = "EncodingError.invalidValue"
    @unknown default:
        context = EncodingError.Context(codingPath: [], debugDescription: "unknown EncodingError case")
        kind = "EncodingError"
    }
    return TelemetrySanitizedError(
        kind: kind,
        message: context.debugDescription,
        stack: describe(codingPath: context.codingPath)
    )
}

/// Sanitizes `DecodingError` for telemetry - only `context.debugDescription`/`codingPath`, never the raw
/// offending value that several `DecodingError` cases embed as their first associated value.
private func sanitize(_ error: DecodingError) -> TelemetrySanitizedError {
    let context: DecodingError.Context
    let kind: String
    switch error {
    case .typeMismatch(_, let ctx):
        context = ctx
        kind = "DecodingError.typeMismatch"
    case .valueNotFound(_, let ctx):
        context = ctx
        kind = "DecodingError.valueNotFound"
    case .keyNotFound(_, let ctx):
        context = ctx
        kind = "DecodingError.keyNotFound"
    case .dataCorrupted(let ctx):
        context = ctx
        kind = "DecodingError.dataCorrupted"
    @unknown default:
        context = DecodingError.Context(codingPath: [], debugDescription: "unknown DecodingError case")
        kind = "DecodingError"
    }
    return TelemetrySanitizedError(
        kind: kind,
        message: context.debugDescription,
        stack: describe(codingPath: context.codingPath)
    )
}

/// Sanitizes `NSError` for telemetry - only `domain`/`code`, never `userInfo`, which can carry
/// customer-supplied data (e.g. `NSLocalizedDescriptionKey`).
private func sanitize(_ error: NSError) -> TelemetrySanitizedError {
    TelemetrySanitizedError(kind: "\(type(of: error))", message: "domain: \(error.domain), code: \(error.code)")
}

private func describe(codingPath: [CodingKey]) -> String? {
    codingPath.isEmpty ? nil : codingPath.map { $0.stringValue }.joined(separator: ".")
}
