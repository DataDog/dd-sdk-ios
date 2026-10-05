/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
@testable import DatadogInternal

public extension NotificationCenterProvider {
    static func makeTestProvider() -> NotificationCenterProvider {
        #if os(macOS)
        NotificationCenterProvider(applicationCenter: NotificationCenter(), workspaceCenter: NotificationCenter())
        #else
        NotificationCenterProvider(applicationCenter: NotificationCenter())
        #endif
    }
}
