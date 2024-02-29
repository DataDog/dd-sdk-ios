/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

internal protocol Aggregator {
    mutating func add(_ submission: Submission)

    func flush() -> [Serie]
}

internal final class CountAggregator: Aggregator {
    var metadata: Submission.Metadata?
    var points: [Serie.Point] = []

    func add(_ submission: Submission) {
        metadata = submission.metadata

        let found = points.firstIndex(
            timestamp: submission.point.timestamp,
            interval: submission.metadata.interval
        )

        guard let index = found else {
            return points.append(submission.point)
        }

        let current = points[index]
        points[index] = Serie.Point(
            timestamp: current.timestamp,
            value: current.value + submission.point.value
        )
    }

    func flush() -> [Serie] {
        guard let metadata = metadata else {
            return []
        }

        return [Serie(
            type: .count,
            interval: metadata.interval,
            metric: metadata.name,
            unit: metadata.unit,
            points: points,
            resources: metadata.resources,
            tags: metadata.tags
        )]
    }
}

internal final class GaugeAggregator: Aggregator {
    var metadata: Submission.Metadata?
    var points: [Serie.Point] = []

    func add(_ submission: Submission) {
        metadata = submission.metadata

        let found = points.firstIndex(
            timestamp: submission.point.timestamp,
            interval: submission.metadata.interval
        )

        guard let index = found else {
            return points.append(submission.point)
        }

        let current = points[index]
        points[index] = Serie.Point(
            timestamp: current.timestamp,
            value: submission.point.value
        )
    }

    func flush() -> [Serie] {
        guard let metadata = metadata else {
            return []
        }

        return [Serie(
            type: .count,
            interval: metadata.interval,
            metric: metadata.name,
            unit: metadata.unit,
            points: points,
            resources: metadata.resources,
            tags: metadata.tags
        )]
    }
}


internal final class HistogramAggregator: Aggregator {
    func add(_ submission: Submission) { }

    func flush() -> [Serie] {
        []
    }
}

extension Array where Element == Serie.Point {
    func firstIndex(timestamp: Int64, interval: Int64?) -> Int? {
        interval.flatMap { interval in
            firstIndex(where: { ($0.timestamp..<$0.timestamp + interval).contains(timestamp) })
        }
    }
}
