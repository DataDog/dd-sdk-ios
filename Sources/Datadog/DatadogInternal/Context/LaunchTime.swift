/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Provides the application launch time.
public struct LaunchTime: Codable, Equatable, DictionaryEncodable {
    /// The app process launch duration (in seconds) measured as the time from process start time
    /// to receiving `UIApplication.didBecomeActiveNotification` notification.
    ///
    /// If the `UIApplication.didBecomeActiveNotification` has not yet been received the value will be `nil`.
    public let launchTime: TimeInterval?

    /// The date when the application process started.
    public let launchDate: Date

    /// Returns `true` if the application is pre-warmed.
    public let isActivePrewarm: Bool

    public init(
        launchTime: TimeInterval?,
        launchDate: Date,
        isActivePrewarm: Bool
    ) {
        self.launchTime = launchTime
        self.launchDate = launchDate
        self.isActivePrewarm = isActivePrewarm
    }
}
