/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Metric exporter that sends metrics directly to Datadog's intake API.
///
/// This version does not store data to disk, it uploads to the intake directly.
public final class MetricExporter {
    public struct Configuration {
        public let apiKey: String
        public let version: String

        public init(apiKey: String, version: String) {
            self.apiKey = apiKey
            self.version = version
        }
    }

    /// The type of metric. The available types are 0 (unspecified), 1 (count), 2 (rate), and 3 (gauge). Allowed enum values: 0,1,2,3
    public enum MetricType: Int, Codable {
        case unspecified = 0
        case count = 1
        case rate = 2
        case gauge = 3
    }

    /// https://docs.datadoghq.com/api/latest/metrics/#submit-metrics
    public struct Serie: Codable {
        public struct Point: Codable {
            public let timestamp: Int64
            public let value: Double

            public init(timestamp: Int64, value: Double) {
                self.timestamp = timestamp
                self.value = value
            }
        }

        public struct Resource: Codable {
            public let name: String
            public let type: String

            public init(name: String, type: String) {
                self.name = name
                self.type = type
            }
        }

        public let type: MetricType
        public let interval: Int64?
        public let metric: String
        public let unit: String?
        public let points: [Point]
        public let resources: [Resource]
        public let tags: [String]

        public init(
            type: MetricType,
            interval: Int64?,
            metric: String,
            unit: String?,
            points: [Point],
            resources: [Resource],
            tags: [String]
        ) {
            self.type = type
            self.interval = interval
            self.metric = metric
            self.unit = unit
            self.points = points
            self.resources = resources
            self.tags = tags
        }
    }

    let session: URLSession
    let encoder = JSONEncoder()
    let configuration: Configuration

    // swiftlint:disable force_unwrapping
    let intake = URL(string: "https://api.datadoghq.com/api/v2/series")!
    let prefix = "{ \"series\": [".data(using: .utf8)!
    let separator = ",".data(using: .utf8)!
    let suffix = "]}".data(using: .utf8)!
    // swiftlint:enable force_unwrapping

    public init(configuration: Configuration) {
        let sessionConfiguration: URLSessionConfiguration = .ephemeral
        sessionConfiguration.urlCache = nil
        self.session = URLSession(configuration: sessionConfiguration)
        self.configuration = configuration
    }

    /// Submit timeseries to the Metrics intake.
    ///
    /// - Parameter series: The timeseries.
    public func submit(series: [Serie]) {
        guard !series.isEmpty else {
            return
        }

        do {
            var data = try series.reduce(Data()) { data, serie in
                try data + encoder.encode(serie) + separator
            }

            // remove last separator
            data.removeLast(separator.count)

            var request = URLRequest(url: intake)
            request.httpMethod = "POST"
            request.allHTTPHeaderFields = [
                "Content-Type": "application/json",
                "DD-API-KEY": configuration.apiKey,
                "DD-EVP-ORIGIN": "ios",
                "DD-EVP-ORIGIN-VERSION": configuration.version,
                "DD-REQUEST-ID": UUID().uuidString,
            ]

            request.httpBody = prefix + data + suffix
            session.dataTask(with: request).resume()
        } catch {
            // Silently fail - this is a benchmark tool, not critical infrastructure
        }
    }
}
