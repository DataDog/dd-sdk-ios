/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogTrace
import DatadogRUM
import DatadogLogs
import DatadogCore

internal class StopCoreScenario: TestScenario {
    static let storyboardName = "StopCoreScenario"

    required init() { }

    func configureFeatures() {
        // Enable RUM
        var rumConfig = RUM.Configuration(applicationID: "rum-application-id")
        rumConfig.customEndpoint = Environment.serverMockConfiguration()?.rumEndpoint
        rumConfig.uiKitViewsPredicate = StopCoreScenarioUIKitRUMViewsPredicate()
        rumConfig.uiKitActionsPredicate = DefaultUIKitRUMActionsPredicate()
        rumConfig.urlSessionTracking = .init()
        RUM.enable(with: rumConfig)

        // Enable Trace
        var traceConfig = Trace.Configuration()
        traceConfig.networkInfoEnabled = true
        traceConfig.customEndpoint = Environment.serverMockConfiguration()?.tracesEndpoint
        Trace.enable(with: traceConfig)

        // Enable Logs
        Logs.enable(
            with: Logs.Configuration(
                customEndpoint: Environment.serverMockConfiguration()?.logsEndpoint
            )
        )

        URLSessionInstrumentation.enable(with: .init(delegateClass: CustomURLSessionDelegate.self))
    }
}

private struct StopCoreScenarioUIKitRUMViewsPredicate: UIKitRUMViewsPredicate {
    func rumView(for viewController: UIViewController) -> RUMView? {
        switch viewController {
        case is CSHomeViewController:
            return RUMView(name: "Home")
        case is CSPictureViewController:
            return RUMView(name: "Picture")
        default:
            return nil
        }
    }
}
