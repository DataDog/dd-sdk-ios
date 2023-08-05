/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

public struct MemoryInstrumentConfiguration: InstrumentConfiguration {
    public let samplingInterval: TimeInterval
    public let metricName: String
    public let metricTags: [String]

    public init(
        samplingInterval: TimeInterval,
        metricName: String,
        metricTags: [String]
    ) {
        self.samplingInterval = samplingInterval
        self.metricName = metricName
        self.metricTags = metricTags
    }

    public func createInstrument(with profilerConfiguration: ProfilerConfiguration) -> Any {
        return MemoryInstrument(
            samplingInterval: samplingInterval,
            metricUploader: MetricUploader(
                apiKey: profilerConfiguration.apiKey,
                metricConfiguration: MetricConfiguration(name: metricName, tags: metricTags, type: .gauge)
            )
        )
    }
}

internal class MemoryInstrument: Instrument {
    struct Sample {
        /// POSIX time in seconds (since 1/1/1970).
        var timestamp: TimeInterval
        /// Memory footprint in bytes.
        var footprint: Double
    }

    private var samples: [Sample] = []
    private var currentSampleIndex = 0

    private let uploader: MetricUploader
    private let samplingInterval: TimeInterval
    private var timer: Timer!

    init(samplingInterval: TimeInterval, metricUploader: MetricUploader) {
        // Ref.: https://developer.apple.com/documentation/foundation/timer
        // > A general rule, set the tolerance to at least 10% of the interval, for a repeating timer.
        // > Even a small amount of tolerance has significant positive impact on the power usage of the application.
        let timerTolerance: Double = 0.1

        self.uploader = metricUploader
        self.samplingInterval = samplingInterval
        self.timer = Timer(timeInterval: samplingInterval, repeats: true) { [weak self] _ in self?.step() }
        self.timer.tolerance = samplingInterval * timerTolerance
    }

    deinit { debug("MemoryInstrument.deinit()") }

    private func step() {
        guard currentSampleIndex < samples.count else {
            return
        }

        if let value = currentMemoryFootprint() {
            samples[currentSampleIndex].timestamp = Date().timeIntervalSince1970
            samples[currentSampleIndex].footprint = value
            currentSampleIndex += 1
        }
    }

    let instrumentName = "Memory Instrument"

    func setUp(measurementDuration: TimeInterval) {
        // To mitigate skews by instrument allocations, pre-allocate most memory before it starts.
        let estimatedNumberOfSamples = Int(measurementDuration / samplingInterval)
        for i in (0..<estimatedNumberOfSamples) {
            // Use distinct values to avoid memory pages being compressed.
            let any = Double(i)
            let sample = Sample(timestamp: any, footprint: any)
            samples.append(sample)
        }
    }

    func start() { RunLoop.main.add(timer, forMode: .common) }
    func stop() { timer.invalidate() }

    func uploadResults(completion: @escaping (InstrumentUploadResult) -> Void) {
        for (idx, sample) in samples.enumerated() {
            debug("Measure #\(idx): \(sample.footprint.bytesAsPrettyKB) -- \(Date(timeIntervalSince1970: sample.timestamp))")
        }

        let dataPoints = samples.map { MetricDataPoint(timestamp: UInt64($0.timestamp), value: $0.footprint) }
        uploader.send(metricPoints: dataPoints, completion: completion)
    }

    func tearDown() {
        timer = nil
    }
}
