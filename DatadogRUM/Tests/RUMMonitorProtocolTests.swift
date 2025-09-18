/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal

@testable import DatadogRUM

class NOPMonitorTests: XCTestCase {
    func testWhenUsingNOPMonitorAPIs_itPrintsWarning() {
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        // Given
        let noop = NOPMonitor()

        // When
        noop.addAttribute(forKey: .mockAny(), value: String.mockAny())
        noop.removeAttribute(forKey: .mockAny())
        noop.stopSession()
        noop.startView(viewController: mockView)
        noop.stopView(viewController: mockView)
        noop.startView(key: "view-key")
        noop.stopView(key: "view-key")
        noop.addTiming(name: .mockAny())
        noop.addError(message: .mockAny())
        noop.addError(error: ProgrammerError(description: .mockAny()))
        noop.startResource(resourceKey: .mockAny(), request: .mockAny())
        noop.startResource(resourceKey: .mockAny(), url: .mockRandom())
        noop.startResource(resourceKey: .mockAny(), httpMethod: .mockAny(), urlString: .mockAny())
        noop.addResourceMetrics(resourceKey: .mockAny(), metrics: .mockAny())
        noop.stopResource(resourceKey: .mockAny(), response: .mockAny())
        noop.stopResource(resourceKey: .mockAny(), kind: .mockAny())
        noop.stopResourceWithError(resourceKey: .mockAny(), error: ProgrammerError(description: .mockAny()))
        noop.stopResourceWithError(resourceKey: .mockAny(), message: .mockAny())
        noop.addAction(type: .click, name: .mockAny())
        noop.startAction(type: .click, name: .mockAny())
        noop.stopAction(type: .click)
        noop.addFeatureFlagEvaluation(name: .mockAny(), value: String.mockAny())
        noop.startFeatureOperation(name: .mockAny())
        noop.succeedFeatureOperation(name: .mockAny())
        noop.failFeatureOperation(name: .mockAny(), reason: .mockAny())

        noop.debug = .mockRandom()
        _ = noop.debug

        // Then
        XCTAssertEqual(dd.logger.criticalLogs.count, 27)
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
            "startResource(resourceKey:request:attributes:)",
            "startResource(resourceKey:url:attributes:)",
            "startResource(resourceKey:httpMethod:urlString:attributes:)",
            "addResourceMetrics(resourceKey:metrics:attributes:)",
            "stopResource(resourceKey:response:size:attributes:)",
            "stopResource(resourceKey:statusCode:kind:size:attributes:)",
            "stopResourceWithError(resourceKey:error:response:attributes:)",
            "stopResourceWithError(resourceKey:message:type:response:attributes:)",
            "addAction(type:name:attributes:)",
            "startAction(type:name:attributes:)",
            "stopAction(type:name:attributes:)",
            "addFeatureFlagEvaluation(name:value:)",
            "startFeatureOperation(name:operationKey:attributes:)",
            "succeedFeatureOperation(name:operationKey:attributes:)",
            "failFeatureOperation(name:operationKey:reason:attributes:)",
            "debug",
            "debug",
        ].map { method in
            """
            Calling `\(method)` on NOPMonitor.
            Make sure RUM feature is enabled before using `RUMMonitor.shared()`.
            """
        }
        XCTAssertEqual(expectedMessages, actualMessages)
    }
}
