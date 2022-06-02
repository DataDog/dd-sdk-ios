/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Global SDK `Logger` using console output.
/// This logger is meant for debugging purposes when using SDK, hence **it should print useful information to SDK user**.
/// It is only used when `Datadog.verbosityLevel` value is set.
/// Every information posted to user should be properly classified (most commonly `.debug()` or `.error()`) according to
/// its context: does the message pop up due to user error or user's app environment error? or is it SDK error?
///
/// This no-op `Logger` gets replaced with working instance as soon as the SDK is initialized.
internal var userLogger = createNoOpSDKUserLogger()

internal func createNoOpSDKUserLogger() -> Logger {
    return Logger(
        core: NOOPDatadogCore(),
        identifier: "no-op",
        serviceName: nil,
        loggerName: nil,
        sendNetworkInfo: false,
        useCoreOutput: false,
        validation: nil,
        rumContextIntegration: nil,
        activeSpanIntegration: nil,
        additionalOutput: nil,
        logEventMapper: nil
    )
}

internal func createSDKUserLogger(
    in core: DatadogCoreProtocol,
    consolePrintFunction: @escaping (String) -> Void = { consolePrint($0) },
    timeZone: TimeZone = .current
) -> Logger {
    return Logger(
        core: core,
        identifier: "sdk-user",
        serviceName: "sdk-user",
        loggerName: "sdk-user",
        sendNetworkInfo: true,
        useCoreOutput: false,
        validation: { log in
            let logSeverity = LogLevel(from: log.status)?.rawValue ?? .max
            let threshold = Datadog.verbosityLevel?.rawValue ?? .max
            return logSeverity >= threshold
        },
        rumContextIntegration: nil,
        activeSpanIntegration: nil,
        additionalOutput: LogConsoleOutput(
            format: .shortWith(prefix: "[DATADOG SDK] 🐶 → "),
            timeZone: timeZone,
            printingFunction: consolePrintFunction
        ),
        logEventMapper: nil
    )
}
