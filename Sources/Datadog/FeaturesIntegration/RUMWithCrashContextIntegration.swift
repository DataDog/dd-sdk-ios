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
    private weak var rumViewEventProvider: ValuePublisher<RUMEvent<RUMViewEvent>?>?

    init?() {
        if let crashReportingFeature = CrashReportingFeature.instance {
            self.init(rumViewEventProvider: crashReportingFeature.rumViewEventProvider)
        } else {
            return nil
        }
    }

    init(rumViewEventProvider: ValuePublisher<RUMEvent<RUMViewEvent>?>) {
        self.rumViewEventProvider = rumViewEventProvider
    }

    func update(lastRUMViewEvent: RUMEvent<RUMViewEvent>) {
        rumViewEventProvider?.publishAsync(lastRUMViewEvent)
    }
}
