/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

extension DispatchContinuation {
    @discardableResult
    public func waitDispatchContinuation(timeout: TimeInterval = 5) -> DispatchTimeoutResult {
        let semaphore = DispatchSemaphore(value: 0)
        notify { semaphore.signal() }
        return semaphore.wait(timeout: .now() + timeout)
    }
}
