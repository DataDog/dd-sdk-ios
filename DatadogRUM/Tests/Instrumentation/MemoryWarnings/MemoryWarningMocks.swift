/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogRUM
import TestUtilities

final class MemoryWarningReporterMock: MemoryWarningReporting {
    let didReportMemoryWarning: () -> Void

    init(didReport: @escaping () -> Void) {
        self.didReportMemoryWarning = didReport
    }

    func reportMemoryWarning() {
        didReportMemoryWarning()
    }

    /// nop
    func publish(to subscriber: any DatadogRUM.RUMCommandSubscriber) {
    }
}

extension MemoryWarningMonitor: RandomMockable {
    public static func mockRandom() -> MemoryWarningMonitor {
        return .init(
            memoryWarningReporter: MemoryWarningReporterMock.mockRandom(),
            notificationCenter: .default
        )
    }
}

extension MemoryWarningReporterMock: RandomMockable {
    static func mockRandom() -> MemoryWarningReporterMock { .init {}}
}
