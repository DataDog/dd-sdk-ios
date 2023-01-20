/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import Datadog

class DDNoopRUMMonitorTests: XCTestCase {
    func testWhenUsingDDNoopRUMMonitorAPIs_itPrintsWarning() {
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        // Given
        let noop = DDNoopRUMMonitor()

        // When
        noop.startView(viewController: mockView)
        noop.startView(key: "view-key", name: "View")
        noop.stopView(viewController: mockView)
        noop.stopView(key: "view-key")
        noop.addTiming(name: #function)
        noop.addError(message: #function)
        noop.addError(error: ProgrammerError(description: #function))
        noop.startResourceLoading(resourceKey: #function, request: .mockAny())
        noop.startResourceLoading(resourceKey: #function, url: .mockRandom())
        noop.startResourceLoading(resourceKey: #function, httpMethod: .mockAny(), urlString: #function)
        noop.addResourceMetrics(resourceKey: #function, metrics: .mockAny())
        noop.addResourceMetrics(resourceKey: #function, fetch: (start: .mockAny(), end: .mockAny()), redirection: nil, dns: nil, connect: nil, ssl: nil, firstByte: nil, download: nil, responseSize: nil)
        noop.stopResourceLoading(resourceKey: #function, response: .mockAny())
        noop.stopResourceLoading(resourceKey: #function, statusCode: nil, kind: .mockAny())
        noop.stopResourceLoadingWithError(resourceKey: #function, error: ProgrammerError(description: #function))
        noop.stopResourceLoadingWithError(resourceKey: #function, errorMessage: #function)
        noop.startUserAction(type: .click, name: #function)
        noop.stopUserAction(type: .click, name: #function)
        noop.addUserAction(type: .click, name: #function)
        noop.addAttribute(forKey: .mockAny(), value: #function)
        noop.removeAttribute(forKey: .mockAny())

        // Then
        let expectedWarningMessage = """
        The `Global.rum` was called but no `RUMMonitor` is registered. Configure and register the RUM Monitor globally before invoking the feature:
            Global.rum = RUMMonitor.initialize()
        See https://docs.datadoghq.com/real_user_monitoring/ios
        """

        XCTAssertEqual(dd.logger.criticalLogs.count, 21)
        dd.logger.criticalLogs.forEach { log in
            XCTAssertEqual(log.message, expectedWarningMessage)
        }
    }
}
