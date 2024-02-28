/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// The type of metric. The available types are 0 (unspecified), 1 (count), 2 (rate), and 3 (gauge). Allowed enum values: 0,1,2,3
enum MetricType: Int, Codable {
    case unspecified = 0
    case count = 1
    case rate = 2
    case gauge = 3
}

internal struct Serie: Codable {
    struct Point: Codable {
        let timestamp: Int64
        let value: Double
    }

    struct Resource: Codable {
        let name: String
        let type: String
    }

    let type: MetricType
    let interval: Int64?
    let metric: String
    let unit: String?
    let points: [Point]
    let resources: [Resource]
    let tags: [String]
}

internal struct Series: Encodable {
    let series: [Serie]
}

enum SubmissionType: Int, Codable {
    case count
    case gauge
    case histogram
}

internal struct AggregationRequest: Codable {
    struct Metadata: Codable {
        let name: String
        let type: SubmissionType
        let interval: Int64?
        let unit: String?
        let resources: [Serie.Resource]
        let tags: [String]
    }

    let metadata: Metadata
    let point: Serie.Point
}

extension Array where Element == Serie.Point {
    mutating func insert(point: Serie.Point, interval: Int64?) {
        let found = interval.flatMap {
            firstIndex(timestamp: point.timestamp, interval: $0)
        }

        if let index = found {
            self[index] = point
        } else {
            append(point)
        }
    }

    func firstIndex(timestamp: Int64, interval: Int64) -> Int? {
        firstIndex(
            where: { ($0.timestamp - interval..<$0.timestamp).contains(timestamp) }
        )
    }
}
