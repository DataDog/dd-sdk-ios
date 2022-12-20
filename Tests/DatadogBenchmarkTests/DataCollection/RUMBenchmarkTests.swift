/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Datadog
import XCTest

class RUMBenchmarkTests: BenchmarkTests {
    func testCreatingOneRUMEvent() {
        let viewController = UIViewController()
        Global.rum.startView(viewController: viewController)

        measure {
            Global.rum.addUserAction(type: .tap, name: "tap")
        }
    }

    func testCreatingOneRUMEventWithAttributes() {
        let viewController = UIViewController()
        Global.rum.startView(viewController: viewController)

        var attributes: [AttributeKey: AttributeValue] = [:]
        (0..<16).forEach { index in
            attributes["a\(index)"] = "v\(index)"
        }

        measure {
            Global.rum.addUserAction(type: .tap, name: "tap", attributes: attributes)
        }
    }
}
