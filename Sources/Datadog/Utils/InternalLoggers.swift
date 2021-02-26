/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Necessary configuration to instantiate `developerLogger` and `userLogger`.
internal struct InternalLoggerConfiguration {
    let applicationVersion: String
    let environment: String
    let userInfoProvider: UserInfoProvider
    let networkConnectionInfoProvider: NetworkConnectionInfoProviderType
    let carrierInfoProvider: CarrierInfoProviderType
}

/// Global SDK `Logger` using console output.
/// This logger is meant for debugging purposes during SDK development, hence **it should print useful information to SDK developer**.
/// It is only instantiated when `DD_SDK_DEVELOPMENT` compilation condition is set for `Datadog` target.
/// Some information posted with `developerLogger` may be also passed to `userLogger` with `.debug()` level to help SDK users
/// understand why the SDK is not operating.
///
/// This `Logger` may be instantited on above conditions as soon as the SDK is initialized.
internal var developerLogger: Logger? = nil

/// Global SDK `Logger` using console output.
/// This logger is meant for debugging purposes when using SDK, hence **it should print useful information to SDK user**.
/// It is only used when `Datadog.verbosityLevel` value is set.
/// Every information posted to user should be properly classified (most commonly `.debug()` or `.error()`) according to
/// its context: does the message pop up due to user error or user's app environment error? or is it SDK error?
///
/// This no-op `Logger` gets replaced with working instance as soon as the SDK is initialized.
internal var userLogger = createNoOpSDKUserLogger()

internal func createSDKDeveloperLogger(
    configuration: InternalLoggerConfiguration,
    consolePrintFunction: @escaping (String) -> Void = { consolePrint($0) },
    dateProvider: DateProvider = SystemDateProvider(),
    timeZone: TimeZone = .current
) -> Logger? {
    if CompilationConditions.isSDKCompiledForDevelopment == false {
        return nil
    }
    let logBuilder = LogBuilder(
        applicationVersion: configuration.applicationVersion,
        environment: configuration.environment,
        serviceName: "sdk-developer",
        loggerName: "sdk-developer",
        userInfoProvider: configuration.userInfoProvider,
        networkConnectionInfoProvider: configuration.networkConnectionInfoProvider,
        carrierInfoProvider: configuration.carrierInfoProvider,
        dateCorrector: nil
    )
    let consoleOutput = LogConsoleOutput(
        format: .shortWith(prefix: "🐶 → "),
        timeZone: timeZone,
        printingFunction: consolePrintFunction
    )

    return Logger(
        logBuilder: logBuilder,
        logOutput: consoleOutput,
        dateProvider: dateProvider,
        identifier: "sdk-developer",
        rumContextIntegration: nil,
        activeSpanIntegration: nil
    )
}

internal func createNoOpSDKUserLogger() -> Logger {
    return Logger(
        logBuilder: nil,
        logOutput: nil,
        dateProvider: SystemDateProvider(),
        identifier: "no-op",
        rumContextIntegration: nil,
        activeSpanIntegration: nil
    )
}

internal func createSDKUserLogger(
    configuration: InternalLoggerConfiguration,
    consolePrintFunction: @escaping (String) -> Void = { consolePrint($0) },
    dateProvider: DateProvider = SystemDateProvider(),
    timeZone: TimeZone = .current
) -> Logger {
    let logBuilder = LogBuilder(
        applicationVersion: configuration.applicationVersion,
        environment: configuration.environment,
        serviceName: "sdk-user",
        loggerName: "sdk-user",
        userInfoProvider: configuration.userInfoProvider,
        networkConnectionInfoProvider: configuration.networkConnectionInfoProvider,
        carrierInfoProvider: configuration.carrierInfoProvider,
        dateCorrector: nil
    )
    let consoleOutput = LogConsoleOutput(
        format: .shortWith(prefix: "[DATADOG SDK] 🐶 → "),
        timeZone: timeZone,
        printingFunction: consolePrintFunction
    )

    return Logger(
        logBuilder: logBuilder,
        logOutput: ConditionalLogOutput(conditionedOutput: consoleOutput) { log in
            let logSeverity = LogLevel(from: log.status).rawValue
            let threshold = Datadog.verbosityLevel?.rawValue ?? .max
            return logSeverity >= threshold
        },
        dateProvider: dateProvider,
        identifier: "sdk-user",
        rumContextIntegration: nil,
        activeSpanIntegration: nil
    )
}
