/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import Datadog

/// Scenario which uses RUM only. Blocks the main thread and expects to have non-zero MobileVitals values
final class WebViewTrackingScenario: TestScenario {
    static var storyboardName: String = "WebViewTrackingScenario"

    func configureSDK(builder: Datadog.Configuration.Builder) {
        _ = builder
            .trackUIKitRUMViews()
            .enableLogging(true)
            .enableRUM(true)
    }
}
