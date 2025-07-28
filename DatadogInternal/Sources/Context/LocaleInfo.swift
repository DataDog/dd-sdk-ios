/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Describes current locale information.
public struct LocaleInfo: Codable, Equatable {
    /// Device locale(s) - list of preferred languages set by the user in system settings, in order of priority
    public let locales: [String]

    /// Current Locale (language + region) - active locale that influences system formatting (e.g. "en-US")
    public let currentLocale: String

    /// Time zone identifier (e.g. "Europe/Berlin")
    public let timeZoneIdentifier: String

    internal init(
        locales: [String],
        currentLocale: Locale,
        timeZone: TimeZone
    ) {
        self.locales = locales
        self.currentLocale = currentLocale.identifier.replacingOccurrences(of: "_", with: "-")
        self.timeZoneIdentifier = timeZone.identifier
    }
}

extension LocaleInfo {
    /// Creates locale info with current system values.
    public init() {
        self.init(
            locales: Locale.preferredLanguages,
            currentLocale: Locale.current,
            timeZone: TimeZone.current
        )
    }
}
