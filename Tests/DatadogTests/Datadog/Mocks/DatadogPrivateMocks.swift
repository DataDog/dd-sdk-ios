/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import _Datadog_Private

/*
 A collection of mocks for `_Datadog_Private` module.
 */

class ObjcExceptionHandlerMock: ObjcExceptionHandler {
    let error: Error

    init(throwingError: Error) {
        self.error = throwingError
    }

    override func rethrowToSwift(tryBlock: @escaping () -> Void) throws {
        throw error
    }
}

/// An `ObjcExceptionHandler` which results with no error for the first `afterTimes` number of calls.
/// Throws given `throwingError` for all other calls.
class ObjcExceptionHandlerDeferredMock: ObjcExceptionHandler {
    private let succeedingCallsCounts: Int
    private var currentCallsCount = 0

    let error: Error

    init(throwingError: Error, afterSucceedingCallsCounts succeedingCallsCounts: Int) {
        self.error = throwingError
        self.succeedingCallsCounts = succeedingCallsCounts
    }

    override func rethrowToSwift(tryBlock: @escaping () -> Void) throws {
        if currentCallsCount >= succeedingCallsCounts {
            throw error
        } else {
            tryBlock()
        }
        currentCallsCount += 1
    }
}

/// An `ObjcExceptionHandler` which throws given error with given probability.
class ObjcExceptionHandlerNonDeterministicMock: ObjcExceptionHandler {
    private let probability: Int
    let error: Error

    /// Probability should be described as a number between `0` and `1`
    init(throwingError: Error, withProbability probability: Double) {
        self.error = throwingError
        self.probability = Int(probability * 1_000)
    }

    override func rethrowToSwift(tryBlock: @escaping () -> Void) throws {
        if Int.random(in: 0...1_000) < probability {
            throw error
        } else {
            tryBlock()
        }
    }
}
