/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogInternal
import TestUtilities

@_spi(Internal)
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

final class ThreadSafeBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: Value

    init(_ value: Value) {
        self.storedValue = value
    }

    var value: Value {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedValue
        }
        set {
            lock.lock()
            storedValue = newValue
            lock.unlock()
        }
    }

    @discardableResult
    func mutate<Result>(_ mutation: (inout Value) -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return mutation(&storedValue)
    }
}

final class ManualScheduler: @unchecked Sendable {
    private final class ScheduledOperation: @unchecked Sendable {
        let delay: TimeInterval
        let operation: @Sendable () -> Void
        var isCancelled = false
        var hasRun = false

        init(delay: TimeInterval, operation: @escaping @Sendable () -> Void) {
            self.delay = delay
            self.operation = operation
        }
    }

    private let operations = ThreadSafeBox<[ScheduledOperation]>([])

    var scheduledDelays: [TimeInterval] {
        operations.mutate { $0.map(\.delay) }
    }

    var activeDelays: [TimeInterval] {
        operations.mutate {
            $0.filter { !$0.isCancelled && !$0.hasRun }.map(\.delay)
        }
    }

    var schedule: FlagAssignmentsSchedule {
        { [self] delay, operation in
            enqueue(after: delay, operation: operation)
        }
    }

    private func enqueue(
        after delay: TimeInterval,
        operation: @escaping @Sendable () -> Void
    ) -> @Sendable () -> Void {
        let scheduled = ScheduledOperation(delay: delay, operation: operation)
        operations.mutate { $0.append(scheduled) }
        return { [operations] in
            operations.mutate { _ in scheduled.isCancelled = true }
        }
    }

    func runNext(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let operation = operations.mutate { operations -> (@Sendable () -> Void)? in
            guard let scheduled = operations.first(where: { !$0.isCancelled && !$0.hasRun }) else {
                return nil
            }
            scheduled.hasRun = true
            return scheduled.operation
        }
        guard let operation else {
            return XCTFail("No scheduled operation", file: file, line: line)
        }
        operation()
    }
}

func mockFlagAssignmentsFetchResponse(
    statusCode: Int,
    data: Data = .mockAnyFlagAssignmentsResponse(),
    headers: [String: String]? = nil
) -> FlagAssignmentsFetchResponse {
    FlagAssignmentsFetchResponse(
        data: data,
        httpResponse: HTTPURLResponse(
            url: .mockAny(),
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: headers
        )!
    )
}

func XCTAssertFlagAssignmentsURLFailure(
    _ result: Result<FlagAssignmentsFetchResponse, Error>?,
    code: URLError.Code,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    guard
        case .failure(let error) = result,
        (error as? URLError)?.code == code
    else {
        return XCTFail("Expected URL error \(code)", file: file, line: line)
    }
}

func XCTAssertFlagAssignmentsHTTPStatus(
    _ result: Result<FlagAssignmentsFetchResponse, Error>?,
    statusCode: Int,
    message: String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) {
    guard case .success(let response) = result else {
        return XCTFail("Expected an HTTP response. \(message)", file: file, line: line)
    }
    XCTAssertEqual(response.httpResponse.statusCode, statusCode, message, file: file, line: line)
}

func XCTAssertFlagAssignmentsSuccess(
    _ result: Result<FlagAssignmentsFetchResponse, Error>?,
    message: String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) {
    guard let result else {
        return XCTFail("Expected a result. \(message)", file: file, line: line)
    }
    XCTAssertNoThrow(try result.get(), message, file: file, line: line)
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
    var flagsData: FlagsData?
    let state: FlagsStateObservable = NOPStateObservable.notReady
    var setEvaluationContextStub: ((FlagsEvaluationContext, @escaping (Result<Void, FlagsError>) -> Void) -> Void)?

    var context: FlagsEvaluationContext? {
        flagsData?.context
    }

    init(
        clientName: String = .mockAny(),
        flagsData: FlagsData? = nil,
        setEvaluationContextStub: ((FlagsEvaluationContext, @escaping (Result<Void, FlagsError>) -> Void) -> Void)? = nil
    ) {
        self.clientName = clientName
        self.flagsData = flagsData
        self.setEvaluationContextStub = setEvaluationContextStub
    }

    func setEvaluationContext(
        _ context: FlagsEvaluationContext,
        completion: @escaping (Result<Void, FlagsError>) -> Void
    ) {
        setEvaluationContextStub?(context, completion)
    }

    func flagAssignment(for key: String) -> DatadogFlags.FlagAssignment? {
        flagsData?.flags[key]
    }

    func flagAssignments() -> [String: DatadogFlags.FlagAssignment]? {
        flagsData?.flags
    }

    func reset() {
        flagsData = nil
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
