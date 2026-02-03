/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if DD_BENCHMARK

import Foundation
import DatadogInternal

/// `URLSessionTaskDelegate` implementation to collect network request metrics during benchmark execution.
internal final class BenchmarkURLSessionTaskDelegate: NSObject, URLSessionTaskDelegate {
    let track: String

    init(track: String) {
        self.track = track
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        bench.meter.gauge(metric: "ios.benchmark.response_latency")
            .record(metrics.taskInterval.duration, attributes: ["track": track])
    }
}

#endif
