/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal class MetricsUploader {
    private let session: URLSession
    private let requestBuilder = URLRequestBuilder(
        url: URL(string: "https://api.datadoghq.com/api/v2/series")!,
        queryItems: [],
        headers: [
            .contentTypeHeader(contentType: .applicationJSON),
            .ddAPIKeyHeader(clientToken: Environment.readMetricsAPIKey()),
        ]
    )

    init() {
        let configuration: URLSessionConfiguration = .ephemeral
        configuration.urlCache = nil
        session = URLSession(configuration: configuration)
    }

    func send() {
        let request = requestBuilder.uploadRequest(with: body())
        upload(request: request)
    }

    private func body() -> Data {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = .prettyPrinted

        let now = UInt64(Date().timeIntervalSince1970)

        let event = MetricEvent(
            series: [
                MetricEvent.Series(
                    metric: "test.benchmark.ios.memory",
                    points: [
                        .init(timestamp: now - 60 * 5, value: 1),
                        .init(timestamp: now - 60 * 4, value: 2),
                        .init(timestamp: now - 60 * 3, value: 3),
                        .init(timestamp: now - 60 * 2, value: 2),
                        .init(timestamp: now - 60 * 1, value: 5),
                    ],
                    tags: ["benchmarks"],
                    type: .gauge
                )
            ]
        )

        let encoded = try! encoder.encode(event)
        print(String(data: encoded, encoding: .utf8)!)
        return encoded
    }

    private func upload(request: URLRequest) {
        let task = session.dataTask(with: request) { data, response, error in
            if let response = response {
                print("🧭✅ Metrics uploaded, status: \((response as! HTTPURLResponse).statusCode)")
            } else {
                print("🧭🔥 Metrics not uploaded, error: \(error.debugDescription)")
//                // Retry (it is expected to fail once due to local network traffic requiring a prompt):
//                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
//                    self?.upload(request: request)
//                }
            }
        }
        task.resume()
    }
}
