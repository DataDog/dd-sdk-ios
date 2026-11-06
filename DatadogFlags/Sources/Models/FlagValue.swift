/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// A protocol representing types that can be used as feature flag values.
///
/// The SDK supports the following flag value types:
/// - `Bool` for boolean flags
/// - `String` for string flags
/// - `Int` for integer flags
/// - `Double` for numeric flags
/// - ``AnyValue`` for object/JSON flags
///
/// Numeric flags convert between `Int` and `Double` only when the conversion is exact. For example, a flag
/// value of `5` reads as `Int` or `Double`, and `1.2` reads only as `Double`. Otherwise evaluation returns
/// the default value with ``FlagEvaluationError/typeMismatch``.
///
/// Above 2^53 - 1 in magnitude, a value that decodes as `Double` does not read as `Int`, because the `Double` can
/// be the rounded form of a different number. For example, `9007199254740993.0001` decodes as the `Double`
/// `9007199254740994`. In network responses, integer literals that fit `Int`, such as `9007199254740993`, decode as
/// `Int` and keep every digit.
///
/// Known issue: `JSONDecoder` can decode some numbers with a fractional part as `Int`. For example,
/// `9007199254740993.5` decodes as `9007199254740993`, and `4503599627370497.5` as `4503599627370498`. An `Int` read
/// of such a value returns that `Int` instead of ``FlagEvaluationError/typeMismatch``.
public protocol FlagValue: Encodable {}

extension Bool: FlagValue {}
extension String: FlagValue {}
extension Int: FlagValue {}
extension Double: FlagValue {}
extension AnyValue: FlagValue {}
