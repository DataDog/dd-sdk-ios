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
public protocol FlagValue: Encodable {}

extension Bool: FlagValue {}
extension String: FlagValue {}
extension Int: FlagValue {}
extension Double: FlagValue {}
extension AnyValue: FlagValue {}
