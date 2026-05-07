/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Represents a single test action to be performed in an `AppRun`.
internal struct AppRunStep: Hashable {
    /// Unique identifier used for distinguishing steps.
    let uuid = UUID()

    /// The action to perform, provided with an `AppRunner` context.
    let perform: (AppRunner) -> Void

    /// Creates a new step with the given execution closure.
    /// - Parameter perform: The closure that defines the step logic using the `AppRunner`.
    init(_ perform: @escaping (AppRunner) -> Void) {
        self.perform = perform
    }

    // MARK: – Equatable

    static func == (lhs: AppRunStep, rhs: AppRunStep) -> Bool { lhs.uuid == rhs.uuid }

    // MARK: – Hashable

    func hash(into hasher: inout Hasher) { hasher.combine(uuid) }
}

// MARK: - App Lifecycle

extension AppRunStep {
    static func appLaunch(type: AppRunner.ProcessLaunchType) -> AppRunStep {
        return AppRunStep({ app in
            app.launch(type)
        })
    }

    static func advanceTime(by duration: TimeInterval) -> AppRunStep {
        return AppRunStep({ app in
            app.advanceTime(by: duration)
        })
    }

    static func appBecomesActive(after dt: TimeInterval) -> AppRunStep {
        return AppRunStep({ app in
            app.advanceTime(by: dt)
            app.transitionToActive()
        })
    }

    static func appEntersBackground(after dt: TimeInterval) -> AppRunStep {
        return AppRunStep({ app in
            app.advanceTime(by: dt)
            app.transitionToBackground()
        })
    }
}
