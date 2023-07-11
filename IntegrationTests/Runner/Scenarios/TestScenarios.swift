/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import DatadogCore

protocol TestScenario: AnyObject {
    /// The name of the storyboard containing this scenario.
    static var storyboardName: String { get }

    /// The value of initial tracking consent for this scenario.
    /// Defaults to `.granted`
    var initialTrackingConsent: TrackingConsent { get }

    /// Applies additional SDK configuration for running this scenario.
    /// Defaults to no-op.
    func override(configuration: inout Datadog.Configuration)

    /// Applies additional Feature configuration for running this scenario.
    /// Defaults to no-op.
    func configureFeatures()

    init()
}

/// Defaults.
extension TestScenario {
    var initialTrackingConsent: TrackingConsent { .granted }
    func override(configuration: inout Datadog.Configuration) { /* no-op */ }
    func configureFeatures() { /* no-op */ }
}

internal func initializeTestScenario(with className: String) -> TestScenario {
    let canonicalClassName = "Runner.\(className)"
    let scenarioClass = NSClassFromString(canonicalClassName) as? TestScenario.Type

    guard let scenario = scenarioClass?.init() else {
        fatalError("Cannot initialize `TestScenario` with class name: \(className)")
    }

    return scenario
}
