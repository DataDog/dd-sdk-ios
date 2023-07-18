/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import DatadogLogs
import TestUtilities

extension LoggerProtocol {
    func sendRandomLog(with attributes: [String: Encodable]) {
        let message: String = .mockRandom()
        let error: Error? = Bool.random() ? ErrorMock(.mockRandom()) : nil

        // swiftlint:disable opening_brace
        let allMethods = [
            { self.debug(message, error: error, attributes: attributes) },
            { self.info(message, error: error, attributes: attributes) },
            { self.notice(message, error: error, attributes: attributes) },
            { self.warn(message, error: error, attributes: attributes) },
            { self.error(message, error: error, attributes: attributes) },
            { self.critical(message, error: error, attributes: attributes) },
        ]
        // swiftlint:enable opening_brace

        let randomMethod = allMethods.randomElement()!
        randomMethod()
    }
}

extension Logger.Configuration.ConsoleLogFormat {
    static func random() -> Logger.Configuration.ConsoleLogFormat {
        let allFormats: [Logger.Configuration.ConsoleLogFormat] = [
            .short,
            .shortWith(prefix: .mockRandom())
        ]

        return allFormats.randomElement()!
    }
}
