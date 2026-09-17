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

private final class OperationTargetFallbackMonitor: NOPMonitor {
    var starts: [(name: String, key: String?, attributes: [AttributeKey: AttributeValue])] = []
    var successes: [(name: String, key: String?, attributes: [AttributeKey: AttributeValue])] = []
    var failures: [(name: String, key: String?, reason: RUMFeatureOperationFailureReason)] = []

    override func startOperation(
        name: String,
        operationKey: String?,
        attributes: [AttributeKey: AttributeValue],
        options: OperationOptions?
    ) {
        starts.append((name: name, key: operationKey, attributes: attributes))
    }

    override func succeedOperation(
        name: String,
        operationKey: String?,
        attributes: [AttributeKey: AttributeValue]
    ) {
        successes.append((name: name, key: operationKey, attributes: attributes))
    }

    override func failOperation(
        name: String,
        operationKey: String?,
        reason: RUMFeatureOperationFailureReason,
        attributes: [AttributeKey: AttributeValue]
    ) {
        failures.append((name: name, key: operationKey, reason: reason))
    }
}

private final class ResourceTargetFallbackMonitor: NOPMonitor {
    var starts: [(key: String, method: String?, url: String?, attributes: [AttributeKey: AttributeValue])] = []

    override func startResource(resourceKey: String, request: URLRequest, attributes: [AttributeKey: AttributeValue]) {
        starts.append((resourceKey, request.httpMethod, request.url?.absoluteString, attributes))
    }

    override func startResource(resourceKey: String, url: URL, attributes: [AttributeKey: AttributeValue]) {
        starts.append((resourceKey, "GET", url.absoluteString, attributes))
    }

    override func startResource(resourceKey: String, httpMethod: RUMMethod, urlString: String, attributes: [AttributeKey: AttributeValue]) {
        starts.append((resourceKey, httpMethod.rawValue, urlString, attributes))
    }
}

private final class ActionTargetFallbackMonitor: NOPMonitor {
    var actions: [(type: RUMActionType, name: String, attributes: [AttributeKey: AttributeValue])] = []

    override func addAction(
        type: RUMActionType,
        name: String,
        attributes: [AttributeKey: AttributeValue]
    ) {
        actions.append((type: type, name: name, attributes: attributes))
    }
    var starts: [String] = []
    var stops: [String?] = []

    override func startAction(type: RUMActionType, name: String, attributes: [AttributeKey: AttributeValue]) {
        starts.append(name)
    }

    override func stopAction(type: RUMActionType, name: String?, attributes: [AttributeKey: AttributeValue]) {
        stops.append(name)
    }
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

    @MainActor
    func testResourceTargetBridgePreservesCustomAndNOPMonitorCompatibility() throws {
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }
        let custom = ResourceTargetFallbackMonitor()
        let url = try XCTUnwrap(URL(string: "https://example.com/resource"))
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let target = RUMCommandTarget.scene(RUMSceneIdentifier(rawValue: "scene-A"))
        for monitor in [custom, NOPMonitor()] {
            RUMResourceViewTargetBridge.startResource(
                on: monitor, resourceKey: "request", request: request, attributes: ["form": "request"], explicitTarget: target
            )
            RUMResourceViewTargetBridge.startResource(
                on: monitor, resourceKey: "url", url: url, attributes: ["form": "url"], explicitTarget: target
            )
            RUMResourceViewTargetBridge.startResource(
                on: monitor, resourceKey: "method", httpMethod: .put, urlString: url.absoluteString, attributes: ["form": "method"], explicitTarget: target
            )
        }
        XCTAssertEqual(custom.starts.map(\.key), ["request", "url", "method"])
        XCTAssertEqual(custom.starts.map(\.method), ["POST", "GET", "PUT"])
        XCTAssertEqual(custom.starts.map(\.url), Array(repeating: url.absoluteString, count: 3))
        XCTAssertEqual(custom.starts.map { $0.attributes["form"] as? String }, ["request", "url", "method"])
        XCTAssertEqual(dd.logger.criticalLogs.count, 3)
        for signature in ["startResource(resourceKey:request:attributes:)", "startResource(resourceKey:url:attributes:)", "startResource(resourceKey:httpMethod:urlString:attributes:)"] {
            XCTAssertEqual(dd.logger.criticalLogs.filter { $0.message.contains(signature) }.count, 1)
        }
    }

    @MainActor
    func testWhenUsingActionViewTargetBridgeOnNOPMonitor_itFallsBackExactlyOnce() {
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        RUMActionViewTargetBridge.addAction(
            on: NOPMonitor(),
            type: .custom,
            name: "targeted",
            attributes: [:],
            explicitTarget: .scene(RUMSceneIdentifier(rawValue: "scene-A"))
        )

        XCTAssertEqual(
            dd.logger.criticalLogs.map(\.message),
            [
                """
                Calling `addAction(type:name:attributes:)` on NOPMonitor.
                Make sure RUM feature is enabled before using `RUMMonitor.shared()`.
                """
            ]
        )
    }

    @MainActor
    func testWhenUsingActionViewTargetBridgeOnCustomMonitor_itFallsBackExactlyOnce() {
        let monitor = ActionTargetFallbackMonitor()

        RUMActionViewTargetBridge.addAction(
            on: monitor,
            type: .custom,
            name: "targeted",
            attributes: ["test": "attribute"],
            explicitTarget: .scene(RUMSceneIdentifier(rawValue: "scene-A"))
        )

        XCTAssertEqual(monitor.actions.count, 1)
        XCTAssertEqual(monitor.actions.first?.type, .custom)
        XCTAssertEqual(monitor.actions.first?.name, "targeted")
        XCTAssertEqual(monitor.actions.first?.attributes["test"] as? String, "attribute")
    }

    @MainActor
    func testWhenUsingContinuousActionTargetBridgeOnCustomOrNOPMonitor_itFallsBackExactlyOnce() {
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }
        let custom = ActionTargetFallbackMonitor()
        let target = RUMCommandTarget.scene(RUMSceneIdentifier(rawValue: "scene-A"))
        for monitor in [custom, NOPMonitor()] {
            RUMActionViewTargetBridge.startAction(
                on: monitor, type: .custom, name: "start", attributes: [:], explicitTarget: target
            )
            RUMActionViewTargetBridge.stopAction(
                on: monitor, type: .custom, name: nil, attributes: [:], explicitTarget: target
            )
        }
        XCTAssertEqual(custom.starts, ["start"])
        XCTAssertEqual(custom.stops, [nil])
        XCTAssertEqual(dd.logger.criticalLogs.map(\.message), [
            """
            Calling `startAction(type:name:attributes:)` on NOPMonitor.
            Make sure RUM feature is enabled before using `RUMMonitor.shared()`.
            """,
            """
            Calling `stopAction(type:name:attributes:)` on NOPMonitor.
            Make sure RUM feature is enabled before using `RUMMonitor.shared()`.
            """
        ])
    }

    @MainActor
    func testWhenUsingOperationViewTargetBridgeOnCustomMonitor_itFallsBackExactlyOnce() {
        // Given
        let monitor = OperationTargetFallbackMonitor()
        let target = RUMCommandTarget.scene(
            RUMSceneIdentifier(rawValue: "scene-A")
        )

        // When
        RUMOperationViewTargetBridge.startOperation(
            on: monitor,
            name: "thread_open",
            operationKey: "key-123",
            attributes: ["start": "attribute"],
            options: nil,
            explicitTarget: target
        )
        RUMOperationViewTargetBridge.succeedOperation(
            on: monitor,
            name: "thread_open",
            operationKey: "key-123",
            attributes: ["success": "attribute"],
            explicitTarget: target
        )
        RUMOperationViewTargetBridge.failOperation(
            on: monitor,
            name: "thread_open",
            operationKey: "key-123",
            reason: .error,
            attributes: ["failure": "attribute"],
            explicitTarget: target
        )

        // Then
        XCTAssertEqual(monitor.starts.count, 1)
        XCTAssertEqual(monitor.starts.first?.name, "thread_open")
        XCTAssertEqual(monitor.starts.first?.key, "key-123")
        XCTAssertEqual(monitor.starts.first?.attributes["start"] as? String, "attribute")
        XCTAssertEqual(monitor.successes.count, 1)
        XCTAssertEqual(monitor.successes.first?.name, "thread_open")
        XCTAssertEqual(monitor.successes.first?.key, "key-123")
        XCTAssertEqual(monitor.successes.first?.attributes["success"] as? String, "attribute")
        XCTAssertEqual(monitor.failures.count, 1)
        XCTAssertEqual(monitor.failures.first?.name, "thread_open")
        XCTAssertEqual(monitor.failures.first?.key, "key-123")
        XCTAssertEqual(monitor.failures.first?.reason, .error)
    }
    #endif
}
