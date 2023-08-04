/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit

internal protocol BenchmarkScenario {
    var title: String { get }
    var duration: TimeInterval { get }

    func beforeRun()
    func afterRun()

    func instantiateInitialViewController() -> UIViewController
    func instruments() -> [Instrument]
}
