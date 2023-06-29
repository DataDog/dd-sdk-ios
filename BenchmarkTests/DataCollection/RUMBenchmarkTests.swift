/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogInternal
import DatadogRUM

class RUMBenchmarkTests: BenchmarkTests {
    var rum: RUMMonitorProtocol { RUMMonitor.shared() }

    func testCreatingOneRUMEvent() {
        let viewController = UIViewController()
        rum.startView(viewController: viewController)

        measure {
            rum.addAction(type: .tap, name: "tap")
        }
    }

    func testCreatingOneRUMEventWithAttributes() {
        let viewController = UIViewController()
        rum.startView(viewController: viewController)

        var attributes: [AttributeKey: AttributeValue] = [:]
        (0..<16).forEach { index in
            attributes["a\(index)"] = "v\(index)"
        }

        measure {
            rum.addAction(type: .tap, name: "tap", attributes: attributes)
        }
    }
}
