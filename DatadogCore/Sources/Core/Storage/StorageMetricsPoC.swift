/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal
import UIKit

// swiftlint:disable force_try
// swiftlint:disable implicitly_unwrapped_optional
// swiftlint:disable force_unwrapping
internal class StorageMetricsPoC {
    /// The name of tracked feature.
    let featureName: String
    let metricFile: File
    let queue: DispatchQueue

    let uploadURL = URL(string: "http://192.168.1.10:8000/metrics/")!

    /// Tracks the number of batches of feature.
    private var folderWatcher: BatchFolderWatcher!
    /// Tracks app state transitions.
    private var appStateWatcher: AppStateWatcher!

    init?(featureName: String, directory: Directory, directoryAccessQueue: DispatchQueue) {
        guard let metricsFolder = try? Directory.cache().createSubdirectory(path: "com.datadoghq.metrics") else {
            fatalError("Failed to obtain metrics folder")
            return nil
        }
        guard let metricFile = try? metricsFolder.createOrGetFile(named: featureName) else {
            fatalError("Failed to obtain metric file")
            return nil
        }

        self.featureName = featureName
        #if targetEnvironment(simulator)
            self.metricFile = Directory.localFile(for: featureName)
        #else
            self.metricFile = metricFile
        #endif
        self.queue = DispatchQueue(label: "com.datadoghq.\(featureName)-metrics")
        self.folderWatcher = BatchFolderWatcher(
            directory: directory,
            directoryAccessQueue: directoryAccessQueue,
            exporter: self
        )
        self.appStateWatcher = AppStateWatcher(
            exporter: self
        )

        // Upload metrics
        uploadMetricFile()
    }

    // MARK: - Writing to file

    private let jsonEncoder = JSONEncoder()
    private let separatorByte = "\n".data(using: .utf8)!

    func saveToMetricFile<T: Encodable>(sample: T) {
        do {
            let jsonData = try jsonEncoder.encode(sample)
            try metricFile.append(data: jsonData + separatorByte)
        } catch {
            print("🧭🔥 '\(featureName)' failed to save sample to file \(sample)")
        }
    }

    // MARK: - Upload to mock server

    func uploadMetricFile() {
        upload(file: metricFile)
    }

    private let httpClient = HTTPClient()

    private func upload(file: File) {
        guard #available(iOS 16.0, *) else {
            fatalError("Run on iOS 16.0+")
        }

        queue.async {
            do {
                let data = try Data(reading: try file.stream())
                let url = self.uploadURL.appending(component: file.name)
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.httpBody = data

                self.httpClient.send(request: request) { result in
                    switch result {
                    case .success:
                        print("🧭✅ '\(self.featureName)' uploaded \(file.name)")
                    case .failure:
                        print("🧭🔥 '\(self.featureName)' failed to upload \(file.name)")
                    }
                }
            } catch {
                print("🧭🔥 '\(self.featureName)' failed to read metric file")
            }
        }
    }
}

/// Tracks the number of batches in folder.
private class BatchFolderWatcher {
    internal struct Sample: Encodable {
        /// The type of this sample.
        let type: String = "batch-folder"
        /// The timestamp of recording this sample - milliseconds since 00:00:00 UTC on 1 January 2001.
        let time: Int64
        /// List of batches existing in watched directory at the moment of recording this sample.
        /// Batches are named by their creation date, so it lists their creation timestamps (milliseconds since 00:00:00 UTC on 1 January 2001).
        let batches: [Int64]
    }

    let directory: Directory
    let directoryAccessQueue: DispatchQueue

    unowned var exporter: StorageMetricsPoC

    /// Interval of collecting samples.
    static let interval: TimeInterval = 1
    /// Tolerance of collecting samples (% deviation from interval).
    static let tolerance: Double = 0.1

    init(directory: Directory, directoryAccessQueue: DispatchQueue, exporter: StorageMetricsPoC) {
        self.directory = directory
        self.directoryAccessQueue = directoryAccessQueue
        self.exporter = exporter

        let timer = Timer(timeInterval: BatchFolderWatcher.interval, repeats: true) { [weak self] _ in
            self?.takeSample()
        }
        timer.tolerance = timer.timeInterval * BatchFolderWatcher.tolerance
        RunLoop.main.add(timer, forMode: .common)
    }

    private var wasEmpty = true

    private func takeSample() {
        exporter.queue.async {
            self.directoryAccessQueue.async {
                do {
                    let time = Date()
                    let batches = try self.directory.files()
                    self.exporter.queue.async {
                        let sample = Sample(
                            time: time.timeIntervalSinceReferenceDate.toInt64Milliseconds,
                            batches: batches
                                .map { file in fileCreationDateFrom(fileName: file.name) }
                                .map { fileCreationDate in fileCreationDate.timeIntervalSinceReferenceDate.toInt64Milliseconds }
                        )
                        self.exporter.saveToMetricFile(sample: sample)
                    }
                    if !self.wasEmpty && batches.isEmpty {
                        self.exporter.uploadMetricFile()
                    }
                    self.wasEmpty = batches.isEmpty
                } catch {
                    print("🧭🔥 '\(self.exporter.featureName)' failed to read all batches")
                }
            }
        }
    }
}

/// Tracks application state transitions.
private class AppStateWatcher {
    internal struct Sample: Encodable {
        /// The type of this sample.
        let type: String = "app-state"
        /// The timestamp of recording this sample - milliseconds since 00:00:00 UTC on 1 January 2001.
        let time: Int64
        /// The state application transitioned to ("active", "inactive" or "background").
        let newState: String
    }

    unowned var exporter: StorageMetricsPoC

    init(exporter: StorageMetricsPoC) {
        self.exporter = exporter

        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(applicationDidBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
        nc.addObserver(self, selector: #selector(applicationWillResignActive), name: UIApplication.willResignActiveNotification, object: nil)
        nc.addObserver(self, selector: #selector(applicationDidEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        nc.addObserver(self, selector: #selector(applicationWillEnterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
    }

    @objc
    private func applicationDidBecomeActive() {
        takeSample(newState: "active")
    }

    @objc
    private func applicationWillResignActive() {
        takeSample(newState: "inactive")
    }

    @objc
    private func applicationDidEnterBackground() {
        takeSample(newState: "background")
    }

    @objc
    private func applicationWillEnterForeground() {
        takeSample(newState: "inactive")
    }

    private func takeSample(newState: String) {
        let time = Date()
        self.exporter.queue.async {
            let sample = Sample(
                time: time.timeIntervalSinceReferenceDate.toInt64Milliseconds,
                newState: newState
            )
            self.exporter.saveToMetricFile(sample: sample)
        }
    }
}

// MARK: - Helpers

private extension Directory {
    func createOrGetFile(named name: String) throws -> File {
        return hasFile(named: name) ? try file(named: name) : try createFile(named: name)
    }

    static func localFile(for featureName: String) -> File {
        guard #available(iOS 16.0, *) else {
            fatalError("Requires iOS 16.0")
        }
        let dir = Directory(url: URL(filePath: "/Users/maciek.grzybowski/Desktop/batch-metrics/v1/"))
        if dir.hasFile(named: featureName) {
            return try! dir.file(named: featureName)
        } else {
            return try! dir.createFile(named: featureName)
        }
    }
}

private extension Data {
    init(reading input: InputStream) throws {
        self.init()
        input.open()
        defer {
            input.close()
        }

        let bufferSize = 1_024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer {
            buffer.deallocate()
        }
        while input.hasBytesAvailable {
            let read = input.read(buffer, maxLength: bufferSize)
            if read < 0 {
                //Stream error occured
                throw input.streamError!
            } else if read == 0 {
                //EOF
                break
            }
            self.append(buffer, count: read)
        }
    }
}

// swiftlint:enable force_try
// swiftlint:enable implicitly_unwrapped_optional
// swiftlint:enable force_unwrapping
