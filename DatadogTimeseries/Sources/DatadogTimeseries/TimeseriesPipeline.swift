/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */
import Foundation

public struct TimeseriesPipeline {
    private let provider: DataProvider
    private let config: TimeseriesConfig
    private let metricName: TimeseriesName
    private let batchSize: Int
    private let filter: SampleFilter

    public init(provider: DataProvider, config: TimeseriesConfig, metricName: TimeseriesName, batchSize: Int = 30, filter: SampleFilter = PassThroughFilter()) {
        self.provider = provider
        self.config = config
        self.metricName = metricName
        self.batchSize = batchSize
        self.filter = filter
    }

    public func processAll() throws -> [Data] {
        let batcher = TimeseriesBatcher(batchSize: batchSize)
        let builder = TimeseriesEventBuilder(config: config)
        let encoder = TimeseriesEncoder()
        var results: [Data] = []

        func processSamples(_ samples: [Sample]) throws {
            for sample in samples {
                batcher.add(sample)
                if batcher.shouldFlush() {
                    let batch = batcher.flush()
                    let event = builder.build(samples: batch, name: metricName, eventId: UUID().uuidString.lowercased())
                    results.append(try encoder.encode(event))
                }
            }
        }

        while let raw = provider.read() {
            try processSamples(filter.process(raw))
        }

        try processSamples(filter.flush())

        if let remaining = batcher.flushRemaining() {
            let event = builder.build(samples: remaining, name: metricName, eventId: UUID().uuidString.lowercased())
            results.append(try encoder.encode(event))
        }

        return results
    }
}
