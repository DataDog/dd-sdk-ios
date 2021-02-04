/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Updates `CrashContext` passed to crash reporter with the last `RUMViewEvent`.
/// When the app restarts after crash, this event is used to create and send `RUMErrorEvent` describing the crash.
///
/// This integration isolates the direct link between RUM and Crash Reporting.
internal struct RUMWithCrashContextIntegration {
    private weak var crashContextProvider: CrashContextProviderType?

    init?() {
        if let crashContextProvider = Global.crashReporter?.crashContextProvider {
            self.init(crashContextProvider: crashContextProvider)
        } else {
            return nil
        }
    }

    init(crashContextProvider: CrashContextProviderType) {
        self.crashContextProvider = crashContextProvider
    }

    func update(lastRUMViewEvent: RUMViewEvent) {
        crashContextProvider?.update(lastRUMViewEvent: lastRUMViewEvent)
    }
}
