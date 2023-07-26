/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

internal let benchmarkDuration: TimeInterval = 60
internal func benchmarksUploadURL(_ benchmarkName: String) -> URL {
    let base = URL(string: "http://192.168.1.10:8000/")!
    return base.appendingPathComponent(benchmarkName)
}

public class MainThreadTimeSpenBenchmark: Benchmark {
    public init() { super.init(benchmarkDuration: benchmarkDuration, uploadURL: benchmarksUploadURL("main-thread")) }

    private var measures: [Double] = []

    public func add(mainThreadTimeInMs: Double) {
        guard !isEndOfMeasure() else { return }
        measures.append(mainThreadTimeInMs)
    }

    override func preparePayload() -> String {
        measures.map({ "\($0)" }).joined(separator: "\n")
    }
}

public class DiskWritesBenchmark: Benchmark {
    public init() { super.init(benchmarkDuration: benchmarkDuration, uploadURL: benchmarksUploadURL("disk-writes")) }

    private var measures: [UInt64] = []

    public func add(diskWriteSizeInBytes: UInt64) {
        guard !isEndOfMeasure() else { return }
        measures.append(diskWriteSizeInBytes)
    }

    override func preparePayload() -> String {
        measures.map({ "\($0)" }).joined(separator: "\n")
    }
}

public class UploadSizeBenchmark: Benchmark {
    public init() { super.init(benchmarkDuration: benchmarkDuration, uploadURL: benchmarksUploadURL("upload-size")) }

    private var measures: [UInt64] = []

    public func add(uploadSizeInBytes: UInt64) {
        guard !isEndOfMeasure() else { return }
        measures.append(uploadSizeInBytes)
    }

    override func preparePayload() -> String {
        measures.map({ "\($0)" }).joined(separator: "\n")
    }
}

public class Benchmark {
    private let exporter: BenchmarkExporter
    private let startTime: Date
    private let endTime: Date
    private var isMeasuring: Bool

    init(benchmarkDuration: TimeInterval, uploadURL: URL) {
        self.exporter = BenchmarkExporter(uploadURL: uploadURL)
        self.startTime = Date()
        self.endTime = startTime.addingTimeInterval(benchmarkDuration)
        self.isMeasuring = true
    }

    func preparePayload() -> String { fatalError("Abstract method") }
    func isEndOfMeasure() -> Bool {
        if !isMeasuring {
            return true
        } else if Date() > endTime {
            isMeasuring = false
            exporter.upload(payload: preparePayload())
            return true
        } else {
            return false
        }
    }
}

internal class BenchmarkExporter {
    private let session: URLSession
    private let url: URL

    init(uploadURL: URL) {
        let configuration: URLSessionConfiguration = .ephemeral
        configuration.urlCache = nil
        self.session = URLSession(configuration: configuration)
        self.url = uploadURL
    }

    func upload(payload: String) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = payload.data(using: .utf8)!
        let task = session.dataTask(with: request) { [weak self] data, response, error in
            if let response = response {
                print("🧭✅ Benchmark data uploaded to \(request.url?.lastPathComponent ?? "??"), status: \((response as! HTTPURLResponse).statusCode)")
            } else {
                print("🧭🔥 Benchmark data not uploaded  to \(request.url?.lastPathComponent ?? "??"), error: \(error.debugDescription)")

                // Retry (it is expected to fail once due to local network traffic requiring a prompt):
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    self?.upload(payload: payload)
                }
            }
        }
        task.resume()
    }
}
