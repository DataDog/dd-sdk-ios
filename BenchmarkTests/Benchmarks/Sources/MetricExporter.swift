/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import OpenTelemetrySdk

enum MetricExporterError: Error {
    case unsupportedMetric(aggregation: AggregationType, dataType: Any.Type)
}

/// Replacement of otel `DatadogExporter` for metrics.
///
/// This version does not store data to disk, it uploads to the intake directly.
/// Additionally, it does not crash.
final class MetricExporter: OpenTelemetrySdk.MetricExporter {
    struct Configuration {
        let apiKey: String
        let version: String
    }

    /// The type of metric. The available types are 0 (unspecified), 1 (count), 2 (rate), and 3 (gauge). Allowed enum values: 0,1,2,3
    enum MetricType: Int, Codable {
        case unspecified = 0
        case count = 1
        case rate = 2
        case gauge = 3
    }

    /// https://docs.datadoghq.com/api/latest/metrics/#submit-metrics
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

    let session: URLSession
    let encoder = JSONEncoder()
    let configuration: Configuration

    // swiftlint:disable force_unwrapping
    let intake = URL(string: "https://api.datadoghq.com/api/v2/series")!
    let prefix = "{ \"series\": [".data(using: .utf8)!
    let separator = ",".data(using: .utf8)!
    let suffix = "]}".data(using: .utf8)!
    // swiftlint:enable force_unwrapping

    required init(configuration: Configuration) {
        let sessionConfiguration: URLSessionConfiguration = .ephemeral
        sessionConfiguration.urlCache = nil
        self.session = URLSession(configuration: sessionConfiguration)
        self.configuration = configuration
    }

    func export(metrics: [Metric], shouldCancel: (() -> Bool)?) -> MetricExporterResultCode {
        do {
            let series = try metrics.map(transform)
            try submit(series: series)
            return.success
        } catch {
            return .failureNotRetryable
        }
    }
    
    /// Transforms otel `Metric` to Datadog `serie`.
    ///
    /// - Parameter metric: The otel metric
    /// - Returns: The timeserie.
    func transform(_ metric: Metric) throws -> Serie {
        var tags: Set<String> = []

        let points: [Serie.Point] = try metric.data.map { data in
            let timestamp = Int64(data.timestamp.timeIntervalSince1970)

            data.labels.forEach { tags.insert("\($0):\($1)") }

            switch data {
            case let data as SumData<Double>:
                return Serie.Point(timestamp: timestamp, value: data.sum)
            case let data as SumData<Int>:
                return Serie.Point(timestamp: timestamp, value: Double(data.sum))
            case let data as SummaryData<Double>:
                return Serie.Point(timestamp: timestamp, value: data.sum)
            case let data as SummaryData<Int>:
                return Serie.Point(timestamp: timestamp, value: Double(data.sum))
//            case let data as HistogramData<Int>:
//                return Serie.Point(timestamp: timestamp, value: Double(data.sum))
//            case let data as HistogramData<Double>:
//                return Serie.Point(timestamp: timestamp, value: data.sum)
            default:
                throw MetricExporterError.unsupportedMetric(
                    aggregation: metric.aggregationType,
                    dataType: type(of: data)
                )
            }
        }

        return Serie(
            type: MetricType(metric.aggregationType),
            interval: nil,
            metric: metric.name,
            unit: nil,
            points: points,
            resources: [],
            tags: Array(tags)
        )
    }
    
    /// Submit timeseries to the Metrics intake.
    ///
    /// - Parameter series: The timeseries.
    func submit(series: [Serie]) throws {
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
    }
}

private extension MetricExporter.MetricType {
    init(_ type: OpenTelemetrySdk.AggregationType) {
        switch type {
        case .doubleSum, .intSum:
            self = .count
        case .intGauge, .doubleGauge:
            self = .gauge
        case .doubleSummary, .intSummary, .doubleHistogram, .intHistogram:
            self = .unspecified
        }
    }
}
