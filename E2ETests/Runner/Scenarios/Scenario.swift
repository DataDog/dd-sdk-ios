/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import UIKit

protocol Scenario {
    func start(info: TestInfo) -> UIViewController
}

enum Scenarios: String, Scenario, CaseIterable {
    case sessionReplayWebView

    func start(info: TestInfo) -> UIViewController {
        switch self {
        case .sessionReplayWebView:
            return UIViewController()
        }
    }
}
