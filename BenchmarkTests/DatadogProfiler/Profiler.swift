/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

public struct ProfilerConfiguration {
    public let apiKey: String

    public init(
        apiKey: String
    ) {
        self.apiKey = apiKey
    }
}

public enum ProfileUploadResult {
    case success([String])
    case failure([String])
}

public class Profiler {
    public internal(set) static var instance: Profiler?

    public static func setUp(
        with configuration: ProfilerConfiguration,
        instruments: [InstrumentConfiguration],
        expectedMeasurementDuration: TimeInterval
    ) {
        precondition(instance == nil, "Only one instance of profiler is allowed")
        instance = Profiler(configuration: configuration, instrumentConfigurations: instruments, expectedMeasurementDuration: expectedMeasurementDuration)
        instance?.setUp()
    }

    /// If `true` no data will be uploaded.
    public static var skipUploads = false

    let configuration: ProfilerConfiguration
    let instruments: [Instrument]
    let expectedMeasurementDuration: TimeInterval

    init(
        configuration: ProfilerConfiguration,
        instrumentConfigurations: [InstrumentConfiguration],
        expectedMeasurementDuration: TimeInterval
    ) {
        self.configuration = configuration
        self.instruments = instrumentConfigurations.map { $0.createInstrument(with: configuration) as! Instrument }
        self.expectedMeasurementDuration = expectedMeasurementDuration
    }

    deinit { debug("Profiler.deinit()") }

    internal func setUp() {
        debug("Profiler.setUp()")
        instruments.forEach { $0.setUp(measurementDuration: expectedMeasurementDuration) }
    }

    public func start(stopAndTearDownAutomatically automaticCompletion: ((ProfileUploadResult) -> Void)? = nil) {
        debug("Profiler.start(automaticCompletion: \(automaticCompletion != nil))")
        instruments.forEach { $0.start() }

        if let automaticCompletion = automaticCompletion {
            mainQueue.asyncAfter(deadline: .now() + expectedMeasurementDuration) { [weak self] in
                self?.stop()
                self?.tearDown(completion: automaticCompletion)
            }
        }
    }

    public func stop() {
        debug("Profiler.stop()")
        instruments.forEach { $0.stop() }
    }

    public func tearDown(completion: @escaping (ProfileUploadResult) -> Void) {
        debug("Profiler.tearDown()")
        var results: [(String, InstrumentUploadResult)] = []

        let group = DispatchGroup()
        instruments.forEach { instrument in
            group.enter()
            instrument.uploadResults { result in
                mainQueue.async {
                    results.append((instrument.instrumentName, result))
                    instrument.tearDown()
                    group.leave()
                }
            }
        }

        group.notify(queue: mainQueue) {
            let result = ProfileUploadResult(instrumentResults: results)
            debug("Profiler result: \(result)")
            completion(result)
            Profiler.instance = nil
        }
    }
}

internal extension ProfileUploadResult {
    init(instrumentResults: [(String, InstrumentUploadResult)]) {
        var summary: [String] = []
        var hasError = false

        for (instrumentName, instrumentResult) in instrumentResults {
            switch instrumentResult {
            case .success:
                summary.append("\(instrumentName) - OK")
            case .error(let errorString):
                summary.append("\(instrumentName) - error: \(errorString)")
                hasError = true
            }
        }

        self = hasError ? .failure(summary) : .success(summary)
    }
}
