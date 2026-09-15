/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal

@testable import DatadogRUM

#if os(iOS)
private final class SceneTargetedFallbackMonitor: RUMMonitorViewProtocol {
    var starts: [(key: String, name: String?, attributes: [AttributeKey: AttributeValue])] = []
    var stops: [(key: String, attributes: [AttributeKey: AttributeValue])] = []

    func addViewAttribute(forKey key: AttributeKey, value: AttributeValue) {}
    func addViewAttributes(_ attributes: [AttributeKey: AttributeValue]) {}
    func removeViewAttribute(forKey key: AttributeKey) {}
    func removeViewAttributes(forKeys keys: [AttributeKey]) {}
    func startView(
        viewController: UIViewController,
        name: String?,
        attributes: [AttributeKey: AttributeValue]
    ) {}
    func stopView(
        viewController: UIViewController,
        attributes: [AttributeKey: AttributeValue]
    ) {}
    func startView(
        key: String,
        name: String?,
        attributes: [AttributeKey: AttributeValue]
    ) {
        starts.append((key: key, name: name, attributes: attributes))
    }

    func stopView(
        key: String,
        attributes: [AttributeKey: AttributeValue]
    ) {
        stops.append((key: key, attributes: attributes))
    }
    func addTiming(name: String) {}
    func addViewLoadingTime(overwrite: Bool) {}
}
#endif

class NOPMonitorTests: XCTestCase {
    func testWhenUsingNOPMonitorAPIs_itPrintsWarning() {
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        // Given
        let noop = NOPMonitor()

        // When
        noop.addAttribute(forKey: .mockAny(), value: String.mockAny())
        noop.addAttributes(mockRandomAttributes())
        noop.removeAttribute(forKey: .mockAny())
        noop.removeAttributes(forKeys: .mockAny())
        noop.stopSession()
        noop.reportAppFullyDisplayed()
        noop.addViewAttribute(forKey: .mockAny(), value: String.mockAny())
        noop.addViewAttributes(mockRandomAttributes())
        noop.removeViewAttribute(forKey: .mockAny())
        noop.removeViewAttributes(forKeys: .mockAny())
        noop.startView(key: "view-key")
        noop.stopView(key: "view-key")
        noop.addTiming(name: .mockAny())
        noop.addViewLoadingTime(overwrite: .mockAny())
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
        noop.startOperation(name: .mockAny())
        noop.succeedOperation(name: .mockAny())
        noop.failOperation(name: .mockAny(), reason: .mockAny())

        noop.debug = .mockRandom()
        _ = noop.debug

        // Then
        XCTAssertEqual(dd.logger.criticalLogs.count, 33)
        let actualMessages = dd.logger.criticalLogs.map { $0.message }
        let expectedMessages = [
            "addAttribute(forKey:value:)",
            "addAttributes(_:)",
            "removeAttribute(forKey:)",
            "removeAttributes(forKeys:)",
            "stopSession()",
            "reportAppFullyDisplayed()",
            "addViewAttribute(forKey:value:)",
            "addViewAttributes(_:)",
            "removeViewAttribute(forKey:)",
            "removeViewAttributes(forKeys:)",
            "startView(key:name:attributes:)",
            "stopView(key:attributes:)",
            "addTiming(name:)",
            "addViewLoadingTime(overwrite:)",
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
            "startOperation(name:operationKey:attributes:options:)",
            "succeedOperation(name:operationKey:attributes:)",
            "failOperation(name:operationKey:reason:attributes:)",
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

    #if os(iOS)
    @MainActor
    func testWhenUsingSceneTargetedManualViewBridgeOnNOPMonitor_itFallsBackExactlyOnce() {
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        // Given
        let noop: any RUMMonitorProtocol = NOPMonitor()
        let scene = RUMSceneIdentifier(rawValue: "scene-A")

        // When
        RUMSceneTargetedManualViewBridge.startView(
            on: noop,
            key: "compose",
            name: "Compose",
            attributes: [:],
            sceneIdentifier: scene
        )
        RUMSceneTargetedManualViewBridge.stopView(
            on: noop,
            key: "compose",
            attributes: [:],
            sceneIdentifier: scene
        )

        // Then
        XCTAssertEqual(
            dd.logger.criticalLogs.map(\.message),
            [
                """
                Calling `startView(key:name:attributes:)` on NOPMonitor.
                Make sure RUM feature is enabled before using `RUMMonitor.shared()`.
                """,
                """
                Calling `stopView(key:attributes:)` on NOPMonitor.
                Make sure RUM feature is enabled before using `RUMMonitor.shared()`.
                """
            ]
        )
    }

    @MainActor
    func testWhenUsingSceneTargetedManualViewBridgeOnCustomMonitor_itFallsBackExactlyOnce() {
        // Given
        let monitor = SceneTargetedFallbackMonitor()
        let scene = RUMSceneIdentifier(rawValue: "scene-A")

        // When
        RUMSceneTargetedManualViewBridge.startView(
            on: monitor,
            key: "compose",
            name: "Compose",
            attributes: ["start": "attribute"],
            sceneIdentifier: scene
        )
        RUMSceneTargetedManualViewBridge.stopView(
            on: monitor,
            key: "compose",
            attributes: ["stop": "attribute"],
            sceneIdentifier: scene
        )

        // Then
        XCTAssertEqual(monitor.starts.count, 1)
        XCTAssertEqual(monitor.starts.first?.key, "compose")
        XCTAssertEqual(monitor.starts.first?.name, "Compose")
        XCTAssertEqual(monitor.starts.first?.attributes["start"] as? String, "attribute")
        XCTAssertEqual(monitor.stops.count, 1)
        XCTAssertEqual(monitor.stops.first?.key, "compose")
        XCTAssertEqual(monitor.stops.first?.attributes["stop"] as? String, "attribute")
    }
    #endif
}
