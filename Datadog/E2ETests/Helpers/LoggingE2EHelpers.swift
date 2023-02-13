/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import TestUtilities
import Datadog

extension Logger {
    func sendRandomLog(with attributes: [AttributeKey: AttributeValue]) {
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

extension Logger.Builder.ConsoleLogFormat {
    static func random() -> Logger.Builder.ConsoleLogFormat {
        let allFormats: [Logger.Builder.ConsoleLogFormat] = [
            .short,
            .shortWith(prefix: .mockRandom())
        ]

        return allFormats.randomElement()!
    }
}
