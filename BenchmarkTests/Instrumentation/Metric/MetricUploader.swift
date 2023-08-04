/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal struct MetricConfiguration {
    let name: String
    let tags: [String]
    let type: MetricEvent.Series.MetricType
}

internal class MetricUploader {
    private let session: URLSession
    private let requestBuilder: URLRequestBuilder
    private let metricConfiguration: MetricConfiguration

    init(metricConfiguration: MetricConfiguration) {
        let configuration: URLSessionConfiguration = .ephemeral
        configuration.urlCache = nil
        self.session = URLSession(configuration: configuration)
        self.requestBuilder = URLRequestBuilder(
            url: URL(string: "https://api.datadoghq.com/api/v2/series")!,
            queryItems: [],
            headers: [
                .contentTypeHeader(contentType: .applicationJSON),
                .ddAPIKeyHeader(clientToken: Environment.readMetricsAPIKey()),
            ]
        )
        self.metricConfiguration = metricConfiguration
    }


    func send(metricPoints: [MetricEvent.Series.Point], completion: @escaping (Bool) -> Void) {
        debug("Uploading '\(metricConfiguration.name)' metric, tags: \(metricConfiguration.tags)")

        let metric = MetricEvent(
            series: [
                MetricEvent.Series(
                    metric: metricConfiguration.name,
                    points: metricPoints,
                    tags: metricConfiguration.tags,
                    type: metricConfiguration.type
                )
            ]
        )

        do {
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            let body = try encoder.encode(metric)
            let request = requestBuilder.uploadRequest(with: body)

            if Environment.skipUploadingBenchmarkResult {
                debug("⏩ Skipping '\(metricConfiguration.name)' upload")
                completion(false)
                return
            }

            upload(request: request, completion: completion)
        } catch {
            debug("🔥 Error when preparing metric: \(error)")
            completion(false)
        }
    }

    private func upload(request: URLRequest, completion: @escaping (Bool) -> Void) {
        let task = session.dataTask(with: request) { data, response, error in
            if let response = response as? HTTPURLResponse {
                if response.statusCode >= 200 && response.statusCode < 300 {
                    debug("🧭✅ Metrics uploaded, status: \(response.statusCode)")
                    completion(true)
                } else {
                    debug("🧭⚠️ Metrics not uploaded, status: \(response.statusCode)")
                    completion(false)
                }
            } else {
                debug("🧭🔥 Metrics not uploaded, error: \(error.debugDescription)")
                completion(false)
            }
        }
        task.resume()
    }
}
