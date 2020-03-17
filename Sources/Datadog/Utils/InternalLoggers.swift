/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Global SDK `Logger` using console output.
/// This logger is meant for debugging purposes during SDK development, hence **it should print useful information to SDK developer**.
/// It is only instantiated when `DD_SDK_DEVELOPMENT` compilation condition is set for `Datadog` target.
/// Some information posted with `developerLogger` may be also passed to `userLogger` with `.debug()` level to help SDK users
/// understand why the SDK is not operating.
internal var developerLogger = createSDKDeveloperLogger()

/// Global SDK `Logger` using console output.
/// This logger is meant for debugging purposes when using SDK, hence **it should print useful information to SDK user**.
/// It is only used when `Datadog.verbosityLevel` value is set.
/// Every information posted to user should be properly classified (most commonly `.debug()` or `.error()`) according to
/// its context: does the message pop up due to user error or user's app environment error? or is it SDK error?
internal var userLogger = createSDKUserLogger()

internal func createSDKDeveloperLogger(
    consolePrintFunction: @escaping (String) -> Void = { consolePrint($0) },
    dateProvider: DateProvider = SystemDateProvider(),
    timeFormatter: DateFormatter = LogConsoleOutput.shortTimeFormatter()
) -> Logger? {
    if CompilationConditions.isSDKCompiledForDevelopment == false {
        return nil
    }

    guard let datadog = Datadog.instance else {
        return nil
    }

    let consoleOutput = LogConsoleOutput(
        logBuilder: LogBuilder(
            appContext: datadog.appContext,
            serviceName: "sdk-developer",
            loggerName: "sdk-developer",
            dateProvider: dateProvider,
            userInfoProvider: datadog.userInfoProvider,
            networkConnectionInfoProvider: datadog.networkConnectionInfoProvider,
            carrierInfoProvider: datadog.carrierInfoProvider
        ),
        format: .shortWith(prefix: "🐶 → "),
        printingFunction: consolePrintFunction,
        timeFormatter: timeFormatter
    )

    return Logger(
        logOutput: consoleOutput,
        queue: DispatchQueue(label: "com.datadoghq.logger-sdk-dev")
    )
}

internal func createSDKUserLogger(
    consolePrintFunction: @escaping (String) -> Void = { consolePrint($0) },
    dateProvider: DateProvider = SystemDateProvider(),
    timeFormatter: DateFormatter = LogConsoleOutput.shortTimeFormatter()
) -> Logger {
    guard let datadog = Datadog.instance else {
        return Logger(
            logOutput: NoOpLogOutput(),
            queue: DispatchQueue(label: "com.datadoghq.logger-noop")
        )
    }

    let consoleOutput = LogConsoleOutput(
        logBuilder: LogBuilder(
            appContext: datadog.appContext,
            serviceName: "sdk-user",
            loggerName: "sdk-user",
            dateProvider: dateProvider,
            userInfoProvider: datadog.userInfoProvider,
            networkConnectionInfoProvider: datadog.networkConnectionInfoProvider,
            carrierInfoProvider: datadog.carrierInfoProvider
        ),
        format: .shortWith(prefix: "[DATADOG SDK] 🐶 → "),
        printingFunction: consolePrintFunction,
        timeFormatter: timeFormatter
    )

    return Logger(
        logOutput: ConditionalLogOutput(conditionedOutput: consoleOutput) { logLevel in
            logLevel.rawValue >= (Datadog.verbosityLevel?.rawValue ?? .max)
        },
        queue: DispatchQueue(label: "com.datadoghq.logger-sdk-user")
    )
}
