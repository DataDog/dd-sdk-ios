/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Updates `CrashContext` passed to crash reporter with the last RUM view and RUM session state.
/// When the app restarts after crash, this event is used to create and send `RUMErrorEvent` describing the crash.
///
/// This integration isolates the direct link between RUM and Crash Reporting.
internal struct RUMWithCrashContextIntegration {
    private weak var rumViewEventProvider: ValuePublisher<RUMViewEvent?>?
    private weak var rumSessionStateProvider: ValuePublisher<RUMSessionState?>?

    init(crashReporting: CrashReportingFeature) {
        self.init(
            rumViewEventProvider: crashReporting.rumViewEventProvider,
            rumSessionStateProvider: crashReporting.rumSessionStateProvider
        )
    }

    init(
        rumViewEventProvider: ValuePublisher<RUMViewEvent?>,
        rumSessionStateProvider: ValuePublisher<RUMSessionState?>
    ) {
        self.rumViewEventProvider = rumViewEventProvider
        self.rumSessionStateProvider = rumSessionStateProvider
    }

    func update(lastRUMViewEvent: RUMViewEvent?) {
        rumViewEventProvider?.publishAsync(lastRUMViewEvent)
    }

    func update(lastRUMSessionState: RUMSessionState) {
        rumSessionStateProvider?.publishAsync(lastRUMSessionState)
    }
}
