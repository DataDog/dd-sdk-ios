/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit
import DatadogCore
import DatadogRUM
import DatadogLogs
import DatadogSessionReplay

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

    func configureFeatures() {
        RUM.enable(
            with: RUM.Configuration(
                applicationID: "rum-application-id",
                uiKitViewsPredicate: WebViewTrackingScenarioPredicate(),
                customEndpoint: Environment.serverMockConfiguration()?.rumEndpoint
            )
        )

        SessionReplay.enable(
            with: SessionReplay.Configuration(
                replaySampleRate: 100,
                customEndpoint: Environment.serverMockConfiguration()?.srEndpoint
            )
        )

        Logs.enable(
            with: Logs.Configuration(
                customEndpoint: Environment.serverMockConfiguration()?.logsEndpoint
            )
        )
    }
}
