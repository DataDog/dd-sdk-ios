/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */
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
                dataPoint: [name.rawValue: sample.value]
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
