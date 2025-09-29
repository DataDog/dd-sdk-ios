/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogInternal
import TestUtilities

@testable import DatadogFlags

extension ExposureEvent: AnyMockable, RandomMockable {
    public static func mockAny() -> ExposureEvent {
        .init(
            timestamp: .mockAny(),
            allocation: .mockAny(),
            flag: .mockAny(),
            variant: .mockAny(),
            subject: .mockAny()
        )
    }

    public static func mockRandom() -> ExposureEvent {
        .init(
            timestamp: .mockRandom(),
            allocation: .mockRandom(),
            flag: .mockRandom(),
            variant: .mockRandom(),
            subject: .mockRandom()
        )
    }
}

extension ExposureEvent.Identifier: AnyMockable, RandomMockable {
    public static func mockAny() -> ExposureEvent.Identifier {
        .init(key: .mockAny())
    }

    public static func mockRandom() -> ExposureEvent.Identifier {
        .init(key: .mockRandom())
    }
}

extension ExposureEvent.Subject: AnyMockable, RandomMockable {
    public static func mockAny() -> ExposureEvent.Subject {
        .init(id: .mockAny(), attributes: .mockAny())
    }

    public static func mockRandom() -> ExposureEvent.Subject {
        .init(id: .mockRandom(), attributes: .mockRandom())
    }
}

final class ExposureLoggerMock: ExposureLogging {
    var logExposureCalls: [(
        date: Date,
        flagKey: String,
        assignment: FlagAssignment,
        context: FlagsEvaluationContext
    )] = []

    func logExposure(
        at date: Date,
        for flagKey: String,
        assignment: FlagAssignment,
        context: FlagsEvaluationContext
    ) {
        logExposureCalls.append((date, flagKey, assignment, context))
    }
}
