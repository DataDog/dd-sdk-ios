/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest

@testable import Datadog

extension DatadogContextProvider {
    /// Reads to the `context` synchronously.
    func read(timeout: DispatchTimeInterval = .seconds(5)) throws -> DatadogContext {
        let semaphore = DispatchSemaphore(value: 0)
        var context: DatadogContext! // swiftlint:disable:this implicitly_unwrapped_optional

        read {
            context = $0
            semaphore.signal()
        }

        switch semaphore.wait(timeout: .now() + timeout) {
        case .success:
            return context
        case .timedOut:
            throw XCTestError(.timeoutWhileWaiting)
        }
    }
}
