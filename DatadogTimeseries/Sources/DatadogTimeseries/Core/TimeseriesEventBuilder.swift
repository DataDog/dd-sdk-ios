import Foundation

struct TimeseriesEventBuilder {
    private let config: TimeseriesConfig

    init(config: TimeseriesConfig) {
        self.config = config
    }

    func build(samples: [Sample], name: TimeseriesName, eventId: String) -> TimeseriesEvent {
        let start = samples.first?.timestamp ?? 0
        let end = samples.last?.timestamp ?? 0
        let dateMs = start / 1_000_000

        let dataPoints = samples.map { sample in
            TimeseriesEvent.DataPoint(
                timestamp: sample.timestamp,
                dataPointValue: sample.value
            )
        }

        return TimeseriesEvent(
            dd: TimeseriesEvent.DD(formatVersion: 2),
            application: TimeseriesEvent.Application(id: config.applicationId),
            date: dateMs,
            session: TimeseriesEvent.Session(id: config.sessionId, type: config.sessionType),
            source: config.source,
            type: "timeseries",
            service: config.service,
            version: config.version,
            timeseries: TimeseriesEvent.Timeseries(
                id: eventId,
                name: name,
                start: start,
                end: end,
                data: dataPoints
            )
        )
    }
}
