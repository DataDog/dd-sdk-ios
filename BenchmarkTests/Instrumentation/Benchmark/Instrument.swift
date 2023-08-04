/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

internal protocol Instrument {
    func beforeStart(scenario: BenchmarkScenario)
    func start()
    func stop()
    func afterStop(scenario: BenchmarkScenario, completion: @escaping (Bool) -> Void)
}
