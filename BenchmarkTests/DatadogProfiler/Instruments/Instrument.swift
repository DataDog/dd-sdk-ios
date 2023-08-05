/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

internal enum InstrumentUploadResult {
    case success
    case error(String)
}

public protocol InstrumentConfiguration {
    func createInstrument(with profilerConfiguration: ProfilerConfiguration) -> Any // as! Instrument
    var description: String { get }
}

internal protocol Instrument {
    var instrumentName: String { get }

    func setUp(measurementDuration: TimeInterval)
    func start()
    func stop()
    func uploadResults(completion: @escaping (InstrumentUploadResult) -> Void)
    func tearDown()
}
