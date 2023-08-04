/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit

internal enum ScenarioRunType: String {
    case baseline = "baseline"
    case instrumented = "instrumented"
}

internal var allScenarios: [BenchmarkScenario] = [
    DebugScenario(),
    SessionReplayScenario(runType: .baseline),
    SessionReplayScenario(runType: .instrumented),
]

extension UIStoryboard {
    static var main: UIStoryboard { UIStoryboard(name: "Main", bundle: nil) }
    static var debug: UIStoryboard { UIStoryboard(name: "Debug", bundle: nil) }
}
