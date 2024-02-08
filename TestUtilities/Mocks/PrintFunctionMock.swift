/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

// MARK: - Global Dependencies Mocks

/// Mock which can be used to intercept messages printed by `developerLogger` or
/// `userLogger` by overwriting `Datadog.consolePrint` function:
///
///     let printFunction = PrintFunctionMock()
///     consolePrint = printFunction.print
///
public class PrintFunctionMock {
    public private(set) var printedMessages: [String] = []

    public var printedMessage: String? { printedMessages.last }

    public init() { }

    public func print(message: String, level: CoreLoggerLevel) {
        printedMessages.append(message)
    }

    public func reset() {
        printedMessages = []
    }
}
