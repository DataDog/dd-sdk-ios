import Foundation

struct TimeseriesPipeline {
    private let provider: DataProvider
    private let config: TimeseriesConfig
    private let metricName: TimeseriesName
    private let batchSize: Int

    init(provider: DataProvider, config: TimeseriesConfig, metricName: TimeseriesName, batchSize: Int = 30) {
        self.provider = provider
        self.config = config
        self.metricName = metricName
        self.batchSize = batchSize
    }

    func processAll() throws -> [Data] {
        let batcher = TimeseriesBatcher(batchSize: batchSize)
        let builder = TimeseriesEventBuilder(config: config)
        let encoder = TimeseriesEncoder()

        var results: [Data] = []

        while let sample = provider.read() {
            batcher.add(sample)
            if batcher.shouldFlush() {
                let batch = batcher.flush()
                let event = builder.build(
                    samples: batch,
                    name: metricName,
                    eventId: UUID().uuidString.lowercased()
                )
                let data = try encoder.encode(event)
                results.append(data)
            }
        }

        if let remaining = batcher.flushRemaining() {
            let event = builder.build(
                samples: remaining,
                name: metricName,
                eventId: UUID().uuidString.lowercased()
            )
            let data = try encoder.encode(event)
            results.append(data)
        }

        return results
    }
}
