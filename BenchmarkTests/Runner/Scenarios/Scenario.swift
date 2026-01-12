/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import UIKit

/// A `Scenario` is the entry-point of the Benchmark Runner Application.
///
/// The compliant objects are responsible for initializing the SDK, enabling
/// Features, and create the initial view-controller.
protocol Scenario {
    /// The initial view-controller of the scenario
    var initialViewController: UIViewController { get }

    /// Prewarm the application before an instrumented run.
    ///
    /// - Parameter info: The application information to use during prewarming.
    func prewarm(with info: AppInfo)

    /// Start instrumenting the application by enabling the Datadog SDK and
    /// its Features.
    ///
    /// - Parameter info: The application information to use during SDK
    /// initialisation.
    func instrument(with info: AppInfo)
}

extension Scenario {
    func prewarm(with info: AppInfo) {}
}
