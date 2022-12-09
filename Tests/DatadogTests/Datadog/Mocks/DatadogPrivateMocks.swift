/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import Datadog

class ObjcExceptionHandlerMock: __dd_private_ObjcExceptionHandler {
    let error: Error

    init(throwingError: Error) {
        self.error = throwingError
    }

    override func rethrowToSwift(tryBlock: @escaping () -> Void) throws {
        throw error
    }
}
