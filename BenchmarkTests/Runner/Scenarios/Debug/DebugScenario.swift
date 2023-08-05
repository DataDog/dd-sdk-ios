/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit

internal struct DebugScenario: ScenarioConfiguration {
    let id = "debug"
    let name = "Debug"

    func instantiateInitialViewController() -> UIViewController {
        UIStoryboard.debug.instantiateInitialViewController()!
    }
}
