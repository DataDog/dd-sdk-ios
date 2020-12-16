/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Writes data to files.
internal final class FileWriter: Writer {
    /// Data writting format.
    private let dataFormat: DataFormat
    /// Orchestrator producing reference to writable file.
    private let orchestrator: FilesOrchestrator
    /// JSON encoder used to encode data.
    private let jsonEncoder: JSONEncoder

    init(dataFormat: DataFormat, orchestrator: FilesOrchestrator) {
        self.dataFormat = dataFormat
        self.orchestrator = orchestrator
        self.jsonEncoder = JSONEncoder.default()
    }

    // MARK: - Writing data

    /// Encodes given value to JSON data and writes it to the file.
    func write<T: Encodable>(value: T) {
        do {
            let data = try jsonEncoder.encode(value)
            let file = try orchestrator.getWritableFile(writeSize: UInt64(data.count))

            if try file.size() == 0 {
                try file.append(data: data)
            } else {
                let atomicData = dataFormat.separatorData + data
                try file.append(data: atomicData)
            }
        } catch {
            userLogger.error("🔥 Failed to write log: \(error)")
            developerLogger?.error("🔥 Failed to write file: \(error)")
        }
    }
}
