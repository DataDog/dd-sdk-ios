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
