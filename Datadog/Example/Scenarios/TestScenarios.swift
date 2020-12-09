/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Datadog

protocol TestScenario {
    /// The name of the storyboard containing this scenario.
    static var storyboardName: String { get }

    /// An identifier for this scenario used to pass its reference in environment variable.
    /// Defaults to `storyboardName`.
    static func envIdentifier() -> String

    /// The value of initial tracking consent for this scenario.
    /// Defaults to `.granted`
    var initialTrackingConsent: TrackingConsent { get }

    /// Applies additional SDK configuration for running this scenario.
    /// Defaults to no-op.
    func configureSDK(builder: Datadog.Configuration.Builder)

    init()
}

/// Defaults.
extension TestScenario {
    static func envIdentifier() -> String { storyboardName }
    var initialTrackingConsent: TrackingConsent { .granted }
    func configureSDK(builder: Datadog.Configuration.Builder) { /* no-op */ }
}

/// Returns `TestScenario` for given env identifier.
func createTestScenario(for envIdentifier: String) -> TestScenario {
    let allScenarios = allLoggingScenarios + allTracingScenarios + allRUMScenarios
    let scenarioClass = allScenarios.first { $0.envIdentifier() == envIdentifier }

    guard let scenario = scenarioClass?.init() else {
        fatalError("Cannot find `TestScenario` for `envIdentifier`: \(envIdentifier)")
    }

    return scenario
}
