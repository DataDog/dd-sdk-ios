/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit

/// Debug scenario, used mainly to debug and callibrate instrumentations.
internal class DebugScenario: BenchmarkScenario {
    let title: String = "Debug"
    let duration: TimeInterval = 5
    let instruments: [Instrument] = [
        MemoryUsageInstrument(samplingInterval: 0.5)
    ]

    func beforeRun() {
        debug("DebugScenario.beforeRun()")
    }

    func afterRun() {
        debug("DebugScenario.afterRun()")
    }

    func instantiateInitialViewController() -> UIViewController {
        let vc = UIViewController()
        vc.view.backgroundColor = .lightGray
        return vc
    }
}
