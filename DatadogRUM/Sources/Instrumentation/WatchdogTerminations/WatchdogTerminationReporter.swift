/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Reports Watchdog Termination events to Datadog.
internal protocol WatchdogTerminationReporting {
    /// Sends the Watchdog Termination event to Datadog.
    func send()
}

/// Default implementation of `WatchdogTerminationReporting`.
internal final class WatchdogTerminationReporter: WatchdogTerminationReporting {
    /// Sends the Watchdog Termination event to Datadog.
    func send() {
        DD.logger.error("TODO: WatchdogTerminationReporter.report()")
    }
}
