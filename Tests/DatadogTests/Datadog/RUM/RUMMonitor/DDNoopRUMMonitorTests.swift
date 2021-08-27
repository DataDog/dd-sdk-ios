/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class DDNoopRUMMonitorTests: XCTestCase {
    func testWhenUsingDDNoopRUMMonitorAPIs_itPrintsWarning() {
        let previousUserLogger = userLogger
        defer { userLogger = previousUserLogger }

        let output = LogOutputMock()
        userLogger = .mockWith(logOutput: output)

        // Given
        let noop = DDNoopRUMMonitor()

        // When
        noop.startView(viewController: mockView)
        noop.startView(key: "view-key", name: "View")
        noop.stopView(viewController: mockView)
        noop.stopView(key: "view-key")

        // Then
        let expectedWarningMessage = """
        The `Global.rum` was called but no `RUMMonitor` is registered. Configure and register the RUM Monitor globally before invoking the feature:
            Global.rum = RUMMonitor.initialize()
        See https://docs.datadoghq.com/real_user_monitoring/ios
        """

        XCTAssertEqual(output.allRecordedLogs.count, 2)
        output.allRecordedLogs.forEach { log in
            XCTAssertEqual(log.status, .warn)
            XCTAssertEqual(log.message, expectedWarningMessage)
        }
    }
}
