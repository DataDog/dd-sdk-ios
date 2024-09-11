/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogRUM
import TestUtilities

final class MemoryWarningReporterMock: MemoryWarningReporting {
    let didReport: (MemoryWarning) -> Void

    init(didReport: @escaping (MemoryWarning) -> Void) {
        self.didReport = didReport
    }

    func report(warning: DatadogRUM.MemoryWarning) {
        didReport(warning)
    }

    /// nop
    func publish(to subscriber: any DatadogRUM.RUMCommandSubscriber) {
    }
}

extension MemoryWarningMonitor: RandomMockable {
    public static func mockRandom() -> MemoryWarningMonitor {
        return .init(
            backtraceReporter: nil,
            memoryWarningReporter: MemoryWarningReporterMock.mockRandom(),
            notificationCenter: .default
        )
    }
}

extension MemoryWarningReporterMock: RandomMockable {
    static func mockRandom() -> MemoryWarningReporterMock {
        return .init { _ in }
    }
}
