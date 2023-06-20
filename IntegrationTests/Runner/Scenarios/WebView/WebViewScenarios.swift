/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit
import Datadog
import DatadogRUM
import DatadogLogs

private struct WebViewTrackingScenarioPredicate: UIKitRUMViewsPredicate {
    private let defaultPredicate = DefaultUIKitRUMViewsPredicate()

    func rumView(for viewController: UIViewController) -> RUMView? {
        if viewController is ShopistWebviewViewController {
            return nil // do not consider the webview itself as RUM view
        } else {
            return defaultPredicate.rumView(for: viewController)
        }
    }
}

final class WebViewTrackingScenario: TestScenario {
    static var storyboardName: String = "WebViewTrackingScenario"

    func configureSDK(builder: Datadog.Configuration.Builder) {
        _ = builder
            .trackUIKitRUMViews(using: WebViewTrackingScenarioPredicate())
            .enableRUM(true)
    }

    func configureFeatures() {
        Logs.enable(
            with: Logs.Configuration(
                customIntakeURL: Environment.serverMockConfiguration()?.logsEndpoint
            )
        )
    }
}
