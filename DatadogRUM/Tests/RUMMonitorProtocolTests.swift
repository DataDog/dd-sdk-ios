/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal

@testable import DatadogRUM

class NOPRUMMonitorTests: XCTestCase {
    func testWhenUsingNOPRUMMonitorAPIs_itPrintsWarning() {
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        // Given
        let noop = NOPRUMMonitor()

        // When
        noop.addAttribute(forKey: .mockAny(), value: String.mockAny())
        noop.removeAttribute(forKey: .mockAny())
        noop.stopSession()
        noop.startView(viewController: mockView)
        noop.stopView(viewController: mockView)
        noop.startView(key: "view-key", name: "View")
        noop.stopView(key: "view-key")
        noop.addTiming(name: .mockAny())
        noop.addError(message: .mockAny())
        noop.addError(error: ProgrammerError(description: .mockAny()))
        noop.startResourceLoading(resourceKey: .mockAny(), request: .mockAny())
        noop.startResourceLoading(resourceKey: .mockAny(), url: .mockRandom())
        noop.startResourceLoading(resourceKey: .mockAny(), httpMethod: .mockAny(), urlString: .mockAny())
        noop.addResourceMetrics(resourceKey: .mockAny(), metrics: .mockAny())
        noop.stopResourceLoading(resourceKey: .mockAny(), response: .mockAny())
        noop.stopResourceLoading(resourceKey: .mockAny(), statusCode: nil, kind: .mockAny())
        noop.stopResourceLoadingWithError(resourceKey: .mockAny(), error: ProgrammerError(description: .mockAny()))
        noop.stopResourceLoadingWithError(resourceKey: .mockAny(), message: .mockAny())
        noop.addAction(type: .click, name: .mockAny())
        noop.startAction(type: .click, name: .mockAny())
        noop.stopAction(type: .click, name: .mockAny())
        noop.addFeatureFlagEvaluation(name: .mockAny(), value: String.mockAny())
        noop.debug = .mockRandom()
        _ = noop.debug

        // Then
        XCTAssertEqual(dd.logger.criticalLogs.count, 24)
        let actualMessages = dd.logger.criticalLogs.map { $0.message }
        let expectedMessages = [
            "addAttribute(forKey:value:)",
            "removeAttribute(forKey:)",
            "stopSession()",
            "startView(viewController:name:attributes:)",
            "stopView(viewController:attributes:)",
            "startView(key:name:attributes:)",
            "stopView(key:attributes:)",
            "addTiming(name:)",
            "addError(message:type:stack:source:attributes:file:line:)",
            "addError(error:source:attributes:)",
            "startResourceLoading(resourceKey:request:attributes:)",
            "startResourceLoading(resourceKey:url:attributes:)",
            "startResourceLoading(resourceKey:httpMethod:urlString:attributes:)",
            "addResourceMetrics(resourceKey:metrics:attributes:)",
            "stopResourceLoading(resourceKey:response:size:attributes:)",
            "stopResourceLoading(resourceKey:statusCode:kind:size:attributes:)",
            "stopResourceLoadingWithError(resourceKey:error:response:attributes:)",
            "stopResourceLoadingWithError(resourceKey:message:type:response:attributes:)",
            "addAction(type:name:attributes:)",
            "startAction(type:name:attributes:)",
            "stopAction(type:name:attributes:)",
            "addFeatureFlagEvaluation(name:value:)",
            "debug",
            "debug",
        ].map { method in
            """
            Calling `\(method)` on NOPRUMMonitor.
            Make sure RUM feature is enabled before using `RUMMonitor.shared()`.
            """
        }
        XCTAssertEqual(expectedMessages, actualMessages)
    }
}
