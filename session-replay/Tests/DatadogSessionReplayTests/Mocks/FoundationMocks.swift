/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

extension Bool: AnyMockable, RandomMockable {
    static func mockAny() -> Bool { true }
    static func mockRandom() -> Bool { .random() }
}

extension Date: AnyMockable, RandomMockable {
    static func mockAny() -> Date {
        return .mockDecember15th2019At10AMUTC()
    }

    static func mockRandom() -> Date {
        let randomTimeInterval = TimeInterval.random(in: 0..<Date().timeIntervalSince1970)
        return Date(timeIntervalSince1970: randomTimeInterval)
    }

    /// The 15th of December 2019 at 10:00.000 AM (UTC).
    static func mockDecember15th2019At10AMUTC(addingTimeInterval timeInterval: TimeInterval = 0) -> Date {
        return mockSpecificUTCGregorianDate(year: 2_019, month: 12, day: 15, hour: 10)
            .addingTimeInterval(timeInterval)
    }

    static func mockSpecificUTCGregorianDate(year: Int, month: Int, day: Int, hour: Int, minute: Int = 0, second: Int = 0) -> Date {
        var dateComponents = DateComponents()
        dateComponents.year = year
        dateComponents.month = month
        dateComponents.day = day
        dateComponents.hour = hour
        dateComponents.minute = minute
        dateComponents.second = second
        dateComponents.timeZone = TimeZone(abbreviation: "UTC")!
        dateComponents.calendar = Calendar(identifier: .gregorian)
        return dateComponents.date!
    }
}

extension FixedWidthInteger where Self: RandomMockable {
    static func mockRandom() -> Self {
        return .random(in: min...max)
    }

    static func mockRandom(min: Self = .min, max: Self = .max, otherThan values: Set<Self> = []) -> Self {
        var random: Self = .random(in: min...max)
        while values.contains(random) { random = .random(in: min...max) }
        return random
    }
}

extension FixedWidthInteger where Self: AnyMockable {
    static func mockAny() -> Self {
        return 42
    }
}

extension Int: AnyMockable, RandomMockable {}
extension Int64: AnyMockable, RandomMockable {}

extension String: AnyMockable, RandomMockable {
    static func mockAny() -> String {
        return "abc"
    }

    static func mockRandom() -> String {
        return mockRandom(length: 10)
    }

    static func mockRandom(length: Int) -> String {
        return mockRandom(among: .alphanumericsAndWhitespace, length: length)
    }

    static func mockRandom(among characters: RandomStringCharacterSet, length: Int = 10) -> String {
        return characters.random(ofLength: length)
    }

    static func mockRepeating(character: Character, times: Int) -> String {
        let characters = (0..<times).map { _ in character }
        return String(characters)
    }

    enum RandomStringCharacterSet {
        private static let alphanumericCharacters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        private static let decimalDigitCharacters = "0123456789"

        /// Only letters and numbers (lower and upper cased).
        case alphanumerics
        /// Letters, numbers and whitespace (lower and upper cased).
        case alphanumericsAndWhitespace
        /// Only numbers.
        case decimalDigits
        /// Custom characters.
        case custom(characters: String)

        func random(ofLength length: Int) -> String {
            var characters: String
            switch self {
            case .alphanumerics:
                characters = RandomStringCharacterSet.alphanumericCharacters
            case .alphanumericsAndWhitespace:
                characters = RandomStringCharacterSet.alphanumericCharacters + " "
            case .decimalDigits:
                characters = RandomStringCharacterSet.decimalDigitCharacters
            case .custom(let customCharacters):
                characters = customCharacters
            }

            return String((0..<length).map { _ in characters.randomElement()! })
        }
    }
}
