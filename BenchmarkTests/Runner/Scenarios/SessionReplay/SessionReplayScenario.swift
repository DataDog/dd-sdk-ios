/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit
import DatadogCore
import DatadogRUM
import DatadogSessionReplay

/// Session Replay scenario - switches between SR snapshots with changing the RUM view each time.
internal class SessionReplayScenario: ScenarioConfiguration {
    let id = "sr"
    let name = "Session Replay"

    private var rootViewController: SessionReplayScenarioViewController! = nil

    func setUp() {
        debug("SessionReplayScenario.setUp()")

        // Pre-load all view controllers before test is started, to ease memory allocations during the test.
        rootViewController = SessionReplayScenarioViewController(
            fixtureViewControllers: Fixture.allCases.map { $0.instantiateViewController() },
            fixtureChangeInterval: 1
        )
        rootViewController.onceAfterAllFixturesLoaded = {
            debug("All fixtures loaded and displayed, start measurements.")
            // start measurements()
        }
    }

    func instantiateInitialViewController() -> UIViewController {
        rootViewController
    }
}
