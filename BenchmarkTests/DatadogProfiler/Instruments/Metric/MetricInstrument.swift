/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

public struct MetricInstrumentConfiguration: InstrumentConfiguration {
    public let metricName: String
    public let metricTags: [String]

    public init(
        metricName: String,
        metricTags: [String]
    ) {
        self.metricName = metricName
        self.metricTags = metricTags
    }

    public func createInstrument(with profilerConfiguration: ProfilerConfiguration) -> Any {
        return MetricInstrument(
            instrumentName: metricName,
            metricUploader: MetricUploader(
                apiKey: profilerConfiguration.apiKey,
                metricConfiguration: MetricConfiguration(name: metricName, tags: metricTags, type: .gauge)
            )
        )
    }
    
    public var description: String {
        """
        Metric Instrument:
        - metricName:
            - \(metricName)
        - metricTags:
        \(metricTags.map({ "    - \($0)" }).joined(separator: "\n"))
        """
    }
}

internal class MetricInstrument: Instrument {
    struct Sample {
        /// POSIX time in seconds (since 1/1/1970).
        var timestamp: TimeInterval
        /// Value of the metric.
        var value: Double
    }

    private let uploader: MetricUploader
    private var samples: [Sample] = []

    init(
        instrumentName: String,
        metricUploader: MetricUploader
    ) {
        self.instrumentName = instrumentName
        self.uploader = metricUploader
    }

    let instrumentName: String

    func setUp(measurementDuration: TimeInterval) { /* nop */ }
    func start() { /* nop */ }
    func stop() { /* nop */ }

    func uploadResults(completion: @escaping (InstrumentUploadResult) -> Void) {
        for (idx, sample) in samples.enumerated() {
            debug("Measure #\(idx): \(sample.value) -- \(Date(timeIntervalSince1970: sample.timestamp))")
        }

        let dataPoints = samples.map { MetricDataPoint(timestamp: UInt64($0.timestamp), value: $0.value) }
        uploader.send(metricPoints: dataPoints, completion: completion)
    }
    
    func tearDown() { /* nop */ }
}
