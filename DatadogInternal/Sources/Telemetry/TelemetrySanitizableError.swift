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
///   sanitization with sensible defaults, handled centrally in `TelemetrySanitizedError.init(sanitizing:)`.
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

    /// Describes `error` by its type name and default string interpolation, without any sanitization.
    ///
    /// - Important: `unsafely` means what it says - only use this when `error`'s default `"\(error)"`
    ///   description is known to be safe (e.g. an enum whose cases carry no customer data). Never use it
    ///   for a type that might wrap arbitrary or customer-supplied values; use `init(sanitizing:)` instead.
    public init(unsafelyDescribing error: Error) {
        self.init(kind: "\(type(of: error))", message: "\(error)")
    }

    /// Sanitizes `error`, safe to forward to internal telemetry.
    ///
    /// If `error` conforms to `TelemetrySanitizableError`, its own `sanitize()` is used as-is. Otherwise, it
    /// falls back to Telemetry's default sanitization: common types (`EncodingError`, `DecodingError`,
    /// `NSError`) get a safe, dedicated summary, while everything else is stripped down to its type name.
    public init(sanitizing error: Error) {
        if let sanitizable = error as? TelemetrySanitizableError {
            self = sanitizable.sanitize()
            return
        }
        if let encodingError = error as? EncodingError {
            self = sanitize(encodingError)
            return
        }
        if let decodingError = error as? DecodingError {
            self = sanitize(decodingError)
            return
        }
        if isNSErrorOrItsSubclass(error) {
            self = sanitize(error as NSError)
            return
        }
        let kind = "\(type(of: error))"
        self.init(
            kind: kind,
            message: "\(kind) does not conform to TelemetrySanitizableError — reporting type name only",
            stack: "Implement TelemetrySanitizableError on \(kind) to report richer, safe context."
        )
    }
}

/// Sanitizes `EncodingError` for telemetry - only the failing case and how deeply nested the offending
/// value was. Never `context.debugDescription` or `codingPath`: `EncodingError.Context` is a plain struct
/// that whatever `Encodable` threw the error gets to fill in - including a customer-supplied `Encodable`
/// wrapped in `AnyEncodable` (e.g. a custom RUM attribute) - so both fields must be treated as untrusted,
/// not just the value `invalidValue(_:_:)` embeds as its first associated value.
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
        message: "value could not be encoded",
        stack: describe(depthOf: context.codingPath)
    )
}

/// Sanitizes `DecodingError` for telemetry - only the failing case and how deeply nested the offending
/// value was. Never `context.debugDescription` or `codingPath`: `DecodingError.Context` is a plain struct
/// that whatever `Decodable` threw the error gets to fill in, so both fields must be treated as untrusted,
/// not just the raw value some `DecodingError` cases embed as their first associated value.
private func sanitize(_ error: DecodingError) -> TelemetrySanitizedError {
    let context: DecodingError.Context
    let kind: String
    let message: String
    switch error {
    case .typeMismatch(_, let ctx):
        context = ctx
        kind = "DecodingError.typeMismatch"
        message = "decoded value had an unexpected type"
    case .valueNotFound(_, let ctx):
        context = ctx
        kind = "DecodingError.valueNotFound"
        message = "expected value was missing"
    case .keyNotFound(_, let ctx):
        context = ctx
        kind = "DecodingError.keyNotFound"
        message = "expected key was missing"
    case .dataCorrupted(let ctx):
        context = ctx
        kind = "DecodingError.dataCorrupted"
        message = "data was corrupted"
    @unknown default:
        context = DecodingError.Context(codingPath: [], debugDescription: "unknown DecodingError case")
        kind = "DecodingError"
        message = "unknown decoding failure"
    }
    return TelemetrySanitizedError(kind: kind, message: message, stack: describe(depthOf: context.codingPath))
}

/// Sanitizes `NSError` for telemetry - only `domain`/`code`, never `userInfo`, which can carry
/// customer-supplied data (e.g. `NSLocalizedDescriptionKey`).
private func sanitize(_ error: NSError) -> TelemetrySanitizedError {
    TelemetrySanitizedError(kind: "\(type(of: error))", message: "domain: \(error.domain), code: \(error.code)")
}

/// Describes how deeply nested the offending value was, without naming any of the coding keys along the
/// way - a key can be a dynamic, customer-supplied name (e.g. a custom attribute or an HTTP header name
/// encoded through a `[String: Any]` container), so reporting `codingPath` verbatim would risk the same
/// class of leak this sanitizer exists to prevent.
private func describe(depthOf codingPath: [CodingKey]) -> String? {
    guard !codingPath.isEmpty else {
        return nil
    }
    return codingPath.count == 1 ? "1 level deep" : "\(codingPath.count) levels deep"
}
