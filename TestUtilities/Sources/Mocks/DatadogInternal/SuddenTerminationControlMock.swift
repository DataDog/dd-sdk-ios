/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Counts calls like the system does, without changing sudden termination of the test process.
public final class SuddenTerminationControlMock: SuddenTerminationControl, @unchecked Sendable {
    /// The number of `disableSuddenTermination()` calls not balanced by `enableSuddenTermination()` yet.
    @ReadWriteLock
    public private(set) var disableCount = 0

    /// Whether sudden termination is disabled.
    public var isDisabled: Bool { disableCount > 0 }

    public init() {}

    public func disableSuddenTermination() {
        _disableCount.mutate { $0 += 1 }
    }

    public func enableSuddenTermination() {
        _disableCount.mutate { $0 -= 1 }
    }
}
