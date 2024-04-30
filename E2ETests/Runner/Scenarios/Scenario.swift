/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import UIKit

/// A `Scenario` is the entry-point of the E2E runner application.
///
/// The compliant objects are responsible for initialization the SDK, enabling
/// Feature, and create the root view-controller.
protocol Scenario {
    /// Starts the scenario.
    /// 
    /// Starting the scenario should intialize the SDK and enable Features based on
    /// the provided ``TestInfo`` and scenarios needs.
    ///
    /// The returned view-controller will be used as the root view controller of the
    /// application window.
    ///
    /// - Parameter info: The test info for configuring the SDK.
    /// - Returns: The root view-controller.
    func start(info: TestInfo) -> UIViewController
}

/// A Synthetic scenario can be initialized by defining a Synthetic Test Variable
/// named `E2E_SCENARIO`.
///
/// see. https://docs.datadoghq.com/mobile_app_testing/mobile_app_tests/#variables
enum SyntheticScenario: String, CaseIterable {
    case sessionReplayWebView
    
    /// Creates the scenario defined by the`E2E_SCENARIO` environment variable.
    ///
    /// - Parameter processInfo: The process info holding the environment variables.
    init?(processInfo: ProcessInfo = .processInfo) {
        guard
            processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == nil, // skip SwiftUI preview
            let rawValue = processInfo.environment["E2E_SCENARIO"],
            let scenario = Self(rawValue: rawValue)
        else {
            return nil
        }

        self = scenario
    }
    
    /// Returns the scenario defined by the environment variable.
    var scenario: Scenario {
        switch self {
        case .sessionReplayWebView:
            return SessionReplayWebViewScenario()
        }
    }
}

extension SyntheticScenario: Scenario {
    /// Starts the underlying scenario.
    ///
    /// - Parameter info: The test info for configuring the SDK.
    /// - Returns: The root view-controller.
    func start(info: TestInfo) -> UIViewController {
        scenario.start(info: info)
    }
}
