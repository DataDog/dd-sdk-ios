/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import TestUtilities

/// Defines a chain of `AppRunStep`s representing a test scenario for SDK integration testing.
/// Allows building scenarios using `given()`, `when()`, and `then()` for fluent test composition.
internal struct AppRun: Hashable {
    /// Ordered steps to perform in this run.
    private(set) var steps: [AppRunStep]

    /// Starts a new test scenario with the initial step.
    /// - Parameter initialStep: The first step to define the starting point of the test.
    static func given(_ initialStep: AppRunStep) -> Self {
        return AppRun(steps: [initialStep])
    }

    /// Adds a step to the scenario in the "when" phase.
    /// - Parameter step: The next step representing an action or change.
    func when(_ step: AppRunStep) -> Self {
        var new = self
        new.steps.append(step)
        return new
    }

    /// Adds an additional step to the scenario (alias for `when()`).
    /// - Parameter step: The additional step to append to the sequence.
    func and(_ step: AppRunStep) -> Self {
        return when(step)
    }

    /// Executes the defined scenario and returns the resulting RUM sessions.
    /// - Returns: An array of RUM session matchers.
    func then() throws -> [RUMSessionMatcher] {
        let app = AppRunner()
        app.setUp()
        defer { app.tearDown() }

        // Perform all steps:
        steps.forEach { step in
            step.perform(app)
        }

        // Get recorded sessions:
        let sessions = try app.recordedRUMSessions()
        return sessions
    }
}
