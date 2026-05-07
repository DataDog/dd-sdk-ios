/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
@testable import DatadogCore

extension AppRunStep {
    // MARK: - SDK Setup

    /// Initializes the SDK without enabling any feature.
    static func initializeSDK(sdkSetup: AppRunner.SDKSetup? = nil) -> AppRunStep {
        return AppRunStep({ app in
            app.initializeSDK(sdkSetup ?? { _ in })
        })
    }

    // MARK: - User Info

    static func setUserInfo(
        after dt: TimeInterval = 0,
        id: String? = nil,
        name: String? = nil,
        email: String? = nil,
        extraInfo: [String: any Encodable] = [:]
    ) -> AppRunStep {
        return AppRunStep({ app in
            app.advanceTime(by: dt)
            app.setUserInfo(id: id, name: name, email: email, extraInfo: extraInfo)
        })
    }

    static func addUserExtraInfo(after dt: TimeInterval = 0, _ extraInfo: [String: (any Encodable)?]) -> AppRunStep {
        return AppRunStep({ app in
            app.advanceTime(by: dt)
            app.addUserExtraInfo(extraInfo)
        })
    }

    static func clearUserInfo(after dt: TimeInterval = 0) -> AppRunStep {
        return AppRunStep({ app in
            app.advanceTime(by: dt)
            app.clearUserInfo()
        })
    }

    // MARK: - Test Utils

    static func flushDatadogContext() -> AppRunStep {
        AppRunStep { app in
            app.flush()
        }
    }
}
