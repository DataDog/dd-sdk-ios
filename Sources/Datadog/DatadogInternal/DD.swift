/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Core utilities for monitoring performance and execution of the SDK.
/// These are meant to be shared by all instances of the SDK and `DatadogCore`.
internal var dd = DD()

/// Bundles core utilities for monitoring performance and execution of the SDK.
internal final class DD {
    /// The logger providing methods to print debug information and execution errors from Datadog SDK to user console.
    ///
    /// It is meant for debugging purposes when using the SDK, hence **it should log information useful and actionable
    /// to the SDK user**. Think of possible logs that we may want to receive from our users when asking them to enable
    /// SDK verbosity and send us their console log.
    let logger: CoreLoggerType

    // TODO: RUMM-2239 Move `Telemetry` in here

    init() {
        self.logger = CoreLogger(
            dateProvider: SystemDateProvider(),
            timeZone: .current,
            printFunction: consolePrint,
            verbosityLevel: { Datadog.verbosityLevel }
        )
    }
}
