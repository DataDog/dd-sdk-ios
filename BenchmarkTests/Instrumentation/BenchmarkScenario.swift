/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit

internal protocol BenchmarkScenario {
    var title: String { get }
    var duration: TimeInterval { get }
    
    func setUp()
    func tearDown()
    
    /// If true, measurements will start automatically, right after the initial view controller for this scenario is presented.
    /// Otherwise, it must be started manually by calling `BenchmarkController.current.startMeasurements()`.
    var startMeasurementsAutomatically: Bool { get }
    
    func instantiateInitialViewController() -> UIViewController
    func instruments() -> [Instrument]
}
