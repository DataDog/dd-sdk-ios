/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Core utilities for monitoring performance and execution of the SDK.
///
/// These are meant to be shared by all instances of the SDK and `DatadogCore`.
/// `DD` bundles static dependencies that must be available and functional right away,
/// so it is possible to monitor any phase of the SDK execution, including its initialization sequence.
internal struct DD {
    /// The logger providing methods to print debug information and execution errors from Datadog SDK to user console.
    ///
    /// It is meant for debugging purposes when using the SDK, hence **it should log information useful and actionable
    /// to the SDK user**. Think of possible logs that we may want to receive from our users when asking them to enable
    /// SDK verbosity and send us their console log.
    static var logger: CoreLogger = InternalLogger(
        dateProvider: SystemDateProvider(),
        timeZone: .current,
        printFunction: consolePrint,
        verbosityLevel: { Datadog.verbosityLevel }
    )

    /// The telemetry monitor providing methods to send debug information
    /// and execution errors of the Datadog SDK. It is only available if RUM feature is used.
    ///
    /// All collected events are anonymous and get reported to Datadog Telemetry org.
    /// The actual implementation of `Telemetry` provides sampling and throttling
    /// capabilities to ensure fair usage of user quota.
    ///
    /// Regardless internal optimisations, **it should be used wisely to report only useful
    /// and actionable events** that are key to SDK observability.
    static var telemetry: Telemetry = NOPTelemetry()
}
