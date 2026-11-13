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
/// Numeric getters validate the original JSON number. `Int` reads require a whole value within `Int` range.
/// `Double` reads round fractional values to the nearest finite value and require whole values to remain exact.
/// Overflow and nonzero underflow return the default with ``FlagEvaluationError/typeMismatch``.
public protocol FlagValue: Encodable {}

extension Bool: FlagValue {}
extension String: FlagValue {}
extension Int: FlagValue {}
extension Double: FlagValue {}
extension AnyValue: FlagValue {}
