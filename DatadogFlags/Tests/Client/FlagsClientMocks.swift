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

extension FlagAssignmentsResponse: AnyMockable {
    public static func mockAny() -> FlagAssignmentsResponse {
        .init(flags: [.mockAny(): .mockAny()])
    }
}

extension Data {
    static func mockAnyFlagAssignmentsResponse() -> Data {
        // swiftlint:disable:next force_unwrapping
        try! JSONEncoder().encode(FlagAssignmentsResponse.mockAny())
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
            reason: .mockRandom(),
            doLog: .mockRandom()
        )
    }

    static func mockAnyBoolean(doLog: Bool = true) -> FlagAssignment {
        .init(
            allocationKey: .mockAny(),
            variationKey: .mockAny(),
            variation: .mockAnyBoolean(),
            reason: .mockAny(),
            doLog: doLog
        )
    }

    static func mockAnyString(doLog: Bool = true) -> FlagAssignment {
        .init(
            allocationKey: .mockAny(),
            variationKey: .mockAny(),
            variation: .mockAnyString(),
            reason: .mockAny(),
            doLog: doLog
        )
    }

    static func mockAnyInteger(doLog: Bool = true) -> FlagAssignment {
        .init(
            allocationKey: .mockAny(),
            variationKey: .mockAny(),
            variation: .mockAnyInteger(),
            reason: .mockAny(),
            doLog: doLog
        )
    }

    static func mockAnyDouble(doLog: Bool = true) -> FlagAssignment {
        .init(
            allocationKey: .mockAny(),
            variationKey: .mockAny(),
            variation: .mockAnyDouble(),
            reason: .mockAny(),
            doLog: doLog
        )
    }

    static func mockAnyObject(doLog: Bool = true) -> FlagAssignment {
        .init(
            allocationKey: .mockAny(),
            variationKey: .mockAny(),
            variation: .mockAnyObject(),
            reason: .mockAny(),
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

final class FlagsRepositoryMock: FlagsRepositoryProtocol {
    var clientName: String
    var state: FlagsData?
    var setEvaluationContextStub: ((FlagsEvaluationContext, @escaping (Result<Void, FlagsError>) -> Void) -> Void)?

    var context: FlagsEvaluationContext? {
        state?.context
    }

    init(
        clientName: String = .mockAny(),
        state: FlagsData? = nil,
        setEvaluationContextStub: ((FlagsEvaluationContext, @escaping (Result<Void, FlagsError>) -> Void) -> Void)? = nil
    ) {
        self.clientName = clientName
        self.state = state
        self.setEvaluationContextStub = setEvaluationContextStub
    }

    func setEvaluationContext(
        _ context: FlagsEvaluationContext,
        completion: @escaping (Result<Void, FlagsError>) -> Void
    ) {
        setEvaluationContextStub?(context, completion)
    }

    func flagAssignment(for key: String) -> DatadogFlags.FlagAssignment? {
        state?.flags[key]
    }

    func flagAssignments() -> [String: DatadogFlags.FlagAssignment]? {
        state?.flags
    }

    func reset() {
        state = nil
    }
}

final class FlagAssignmentsFetcherMock: FlagAssignmentsFetching {
    var flagAssignmentsStub: (
        (
            FlagsEvaluationContext,
            @escaping (Result<[String: FlagAssignment], FlagsError>) -> Void
        ) -> Void
    )?

    init(
        flagAssignmentsStub: (
            (
                FlagsEvaluationContext,
                @escaping (Result<[String: FlagAssignment], FlagsError>) -> Void
            ) -> Void
        )? = nil
    ) {
        self.flagAssignmentsStub = flagAssignmentsStub
    }

    func flagAssignments(
        for evaluationContext: FlagsEvaluationContext,
        completion: @escaping (Result<[String: FlagAssignment], FlagsError>) -> Void
    ) {
        flagAssignmentsStub?(evaluationContext, completion)
    }
}

final class RUMFlagEvaluationReporterMock: RUMFlagEvaluationReporting {
    var sendFlagEvaluationCalls: [(String, Any)] = []

    func sendFlagEvaluation<T>(flagKey: String, value: T) where T: FlagValue {
        sendFlagEvaluationCalls.append((flagKey, value))
    }
}
