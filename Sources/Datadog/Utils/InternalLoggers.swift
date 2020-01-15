import Foundation

internal let developerLogger = createSDKDeveloperLogger()
internal let userLogger = createSDKUserLogger()

internal func createSDKDeveloperLogger(
    consolePrintFunction: @escaping (String) -> Void = { print($0) },
    dateProvider: DateProvider = SystemDateProvider(),
    timeFormatter: DateFormatter = LogConsoleOutput.shortTimeFormatter()
) -> Logger? {
    if CompilationConditions.isSDKCompiledForDevelopment == false {
        return nil
    }

    let consoleOutput = LogConsoleOutput(
        logBuilder: LogBuilder(serviceName: "sdk-developer", dateProvider: dateProvider),
        format: .shortWith(prefix: "🐶 → "),
        printingFunction: consolePrintFunction,
        timeFormatter: timeFormatter
    )

    return Logger(logOutput: consoleOutput)
}

internal func createSDKUserLogger(
    consolePrintFunction: @escaping (String) -> Void = { print($0) },
    dateProvider: DateProvider = SystemDateProvider(),
    timeFormatter: DateFormatter = LogConsoleOutput.shortTimeFormatter()
) -> Logger {
    let consoleOutput = LogConsoleOutput(
        logBuilder: LogBuilder(serviceName: "sdk-user", dateProvider: dateProvider),
        format: .shortWith(prefix: "[DATADOG SDK] 🐶 → "),
        printingFunction: consolePrintFunction,
        timeFormatter: timeFormatter
    )

    return Logger(
        logOutput: ConditionalLogOutput(conditionedOutput: consoleOutput) { logLevel in
            logLevel.rawValue >= (Datadog.verbosityLevel?.rawValue ?? .max)
        }
    )
}
