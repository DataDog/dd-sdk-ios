/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogInternal
import TestUtilities

@testable import DatadogFlags

extension FlagsEvaluationContext: AnyMockable, RandomMockable {
    public static func mockAny() -> FlagsEvaluationContext {
        .init(targetingKey: .mockAny(), attributes: .mockAny())
    }

    public static func mockRandom() -> FlagsEvaluationContext {
        .init(targetingKey: .mockRandom(), attributes: .mockRandom())
    }
}

extension FlagAssignment: AnyMockable, RandomMockable {
    public static func mockAny() -> FlagAssignment {
        .mockAnyBoolean()
    }

    public static func mockRandom() -> FlagAssignment {
        .init(
            allocationKey: .mockRandom(),
            variationKey: .mockRandom(),
            variation: .mockRandom(),
            doLog: .mockRandom()
        )
    }

    static func mockAnyBoolean(doLog: Bool = true) -> FlagAssignment {
        .init(
            allocationKey: .mockAny(),
            variationKey: .mockAny(),
            variation: .mockAnyBoolean(),
            doLog: doLog
        )
    }

    static func mockAnyString(doLog: Bool = true) -> FlagAssignment {
        .init(
            allocationKey: .mockAny(),
            variationKey: .mockAny(),
            variation: .mockAnyString(),
            doLog: doLog
        )
    }

    static func mockAnyInteger(doLog: Bool = true) -> FlagAssignment {
        .init(
            allocationKey: .mockAny(),
            variationKey: .mockAny(),
            variation: .mockAnyInteger(),
            doLog: doLog
        )
    }

    static func mockAnyDouble(doLog: Bool = true) -> FlagAssignment {
        .init(
            allocationKey: .mockAny(),
            variationKey: .mockAny(),
            variation: .mockAnyDouble(),
            doLog: doLog
        )
    }

    static func mockAnyObject(doLog: Bool = true) -> FlagAssignment {
        .init(
            allocationKey: .mockAny(),
            variationKey: .mockAny(),
            variation: .mockAnyObject(),
            doLog: doLog
        )
    }
}

extension FlagAssignment.Variation: AnyMockable, RandomMockable {
    public static func mockAny() -> FlagAssignment.Variation {
        .mockAnyBoolean()
    }

    public static func mockRandom() -> FlagAssignment.Variation {
        .boolean(.mockRandom())
    }

    static func mockAnyBoolean() -> FlagAssignment.Variation {
        .boolean(.mockAny())
    }

    static func mockAnyString() -> FlagAssignment.Variation {
        .string(.mockAny())
    }

    static func mockAnyInteger() -> FlagAssignment.Variation {
        .integer(.mockAny())
    }

    static func mockAnyDouble() -> FlagAssignment.Variation {
        .double(.mockAny())
    }

    static func mockAnyObject() -> FlagAssignment.Variation {
        .object(.mockAny())
    }
}

extension AnyValue: AnyMockable, RandomMockable {
    public static func mockAny() -> AnyValue {
        .string(.mockAny())
    }

    public static func mockRandom() -> AnyValue {
        .string(.mockRandom())
    }
}
