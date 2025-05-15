/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Launch report format supported by Datadog SDK.
public struct LaunchReport: AdditionalContext {
    /// The key used to encode/decode the `LaunchReport` in `DatadogContext.baggages`
    public static let key = "launch-report"

    /// Returns `true` if the previous session crashed.
    public let didCrash: Bool

    ///  Creates a new `LaunchReport`.
    /// - Parameter didCrash: `true` if the previous session crashed.
    public init(didCrash: Bool) {
        self.didCrash = didCrash
    }
}

extension LaunchReport: CustomDebugStringConvertible {
    public var debugDescription: String {
        return """
        LaunchReport
        - didCrash: \(didCrash)
        """
    }
}
