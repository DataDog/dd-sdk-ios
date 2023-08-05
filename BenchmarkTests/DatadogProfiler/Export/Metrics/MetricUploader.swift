/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

internal struct MetricConfiguration {
    let name: String
    let tags: [String]
    let type: MetricEvent.Series.MetricType
}

internal class MetricUploader {
    private let session: URLSession
    private let apiKey: String
    private let metricConfiguration: MetricConfiguration

    init(apiKey: String, metricConfiguration: MetricConfiguration) {
        let configuration: URLSessionConfiguration = .ephemeral
        configuration.urlCache = nil
        self.apiKey = apiKey
        self.session = URLSession(configuration: configuration)
        self.metricConfiguration = metricConfiguration
    }

    func send(metricPoints: [MetricDataPoint], completion: @escaping (InstrumentUploadResult) -> Void) {
        debug("Uploading '\(metricConfiguration.name)' metric, tags: \(metricConfiguration.tags), type: \(metricConfiguration.type)")

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
            let body = try metricEncoder.encode(metric)
            let request = createRequest(with: body)

            if Profiler.skipUploads {
                debug("⏩ Skipping '\(metricConfiguration.name)' upload")
                completion(.error("Skipped"))
                return
            }

            upload(request: request, completion: completion)
        } catch {
            debug("🔥 Error while uploading '\(metricConfiguration.name)': \(error)")
            completion(.error("\(error)"))
        }
    }

    private func createRequest(with body: Data) -> URLRequest {
        var request = URLRequest(url: URL(string: "https://api.datadoghq.com/api/v2/series")!)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "DD-API-KEY")

        if let compressedBody = Deflate.encode(body) {
            request.setValue("deflate", forHTTPHeaderField: "Content-Encoding")
            request.httpBody = compressedBody
        } else {
            request.httpBody = body
        }

        return request
    }

    private func upload(request: URLRequest, completion: @escaping (InstrumentUploadResult) -> Void) {
        let task = session.dataTask(with: request) { data, response, error in
            if let response = response as? HTTPURLResponse {
                if response.statusCode >= 200 && response.statusCode < 300 {
                    debug("✅ Metrics uploaded, status: \(response.statusCode)")
                    completion(.success)
                } else {
                    debug("⚠️ Metrics not uploaded, status: \(response.statusCode)")
                    completion(.error("Unexpected status code: \(response.statusCode)"))
                }
            } else if let error = error {
                debug("🔥 Metrics not uploaded, error: \(error)")
                completion(.error("Transport error: \(error)"))
            } else {
                debug("⁉️ Metrics upload finished with unknown status")
                completion(.error("Unknown upload status"))
            }
        }
        task.resume()
    }
}
