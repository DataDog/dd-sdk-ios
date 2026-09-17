/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
#if os(iOS)
import UIKit
#endif
import TestUtilities
import DatadogInternal
@_spi(Experimental)
@testable import DatadogRUM

class RUMMonitorProtocol_ConvenienceTests: XCTestCase {
    /// Sanity check if calling methods from `RUMMonitorProtocol+Convenience.swift` doesn't cause
    /// infinite loop and crash.
    ///
    /// TODO: RUMM-3347 Remove this test once protocol extension methods are safe by desing
    @MainActor
    func testCallingExtensionMethodsIsSafe() {
        // Given
        let monitor = Monitor(
            dependencies: .mockAny(),
            dateProvider: SystemDateProvider()
        )

        // When & Then (no crash)
        #if !os(watchOS)
        monitor.startView(viewController: mockView)
        monitor.stopView(viewController: mockView)
        #endif
        monitor.startView(key: "view-key")
        monitor.stopView(key: "view-key")
        monitor.addError(message: .mockAny())
        monitor.addError(error: ProgrammerError(description: .mockAny()))
        monitor.startResource(resourceKey: .mockAny(), request: .mockAny())
        monitor.startResource(resourceKey: .mockAny(), url: .mockRandom())
        monitor.startResource(resourceKey: .mockAny(), httpMethod: .mockAny(), urlString: .mockAny())
        monitor.addResourceMetrics(resourceKey: .mockAny(), metrics: .mockAny())
        monitor.stopResource(resourceKey: .mockAny(), response: .mockAny())
        monitor.stopResource(resourceKey: .mockAny(), kind: .mockAny())
        monitor.stopResourceWithError(resourceKey: .mockAny(), error: ProgrammerError(description: .mockAny()))
        monitor.stopResourceWithError(resourceKey: .mockAny(), message: .mockAny())
        monitor.addAction(type: .click, name: .mockAny())
        monitor.startAction(type: .click, name: .mockAny())
        monitor.stopAction(type: .click)
        monitor.startOperation(name: .mockAny())
        monitor.succeedOperation(name: .mockAny())
        monitor.failOperation(name: .mockAny(), reason: .mockAny())
        #if os(iOS)
        if #available(iOS 27.0, *),
           let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            let target = RUMViewTarget.current(in: scene)
            monitor.startResource(resourceKey: "targeted-request", request: .mockAny(), view: target)
            monitor.startResource(resourceKey: "targeted-url", url: .mockRandom(), view: target)
            monitor.startResource(resourceKey: "targeted-method", httpMethod: .get, urlString: "https://example.com", view: target)
            monitor.addAction(type: .custom, name: "targeted", view: target)
            monitor.startAction(type: .custom, name: "targeted", view: target)
            monitor.stopAction(type: .custom, view: target)
            monitor.startOperation(name: "targeted", view: target)
            monitor.succeedOperation(name: "targeted", view: target)
            monitor.failOperation(name: "targeted", reason: .error, view: target)
        }
        #endif
    }
}
