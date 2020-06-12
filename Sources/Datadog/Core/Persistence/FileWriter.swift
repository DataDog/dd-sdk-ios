/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

internal final class FileWriter {
    /// Comma separator used to separate data values written to file.
    private let commaSeparatorData: Data = ",".data(using: .utf8)! // swiftlint:disable:this force_unwrapping
    /// Orchestrator producing reference to writable file.
    private let orchestrator: FilesOrchestrator
    /// JSON encoder used to encode data.
    private let jsonEncoder: JSONEncoder
    /// Queue used to synchronize files access (read / write) and perform decoding on background thread.
    private let queue: DispatchQueue

    init(orchestrator: FilesOrchestrator, queue: DispatchQueue) {
        self.orchestrator = orchestrator
        self.queue = queue
        self.jsonEncoder = JSONEncoder.default()
    }

    // MARK: - Writing data

    /// Encodes given value to JSON data and writes it to file.
    /// Comma is used to separate consecutive values in the file.
    func write<T: Encodable>(value: T) {
        queue.async { [weak self] in
            self?.synchronizedWrite(value: value)
        }
    }

    private func synchronizedWrite<T: Encodable>(value: T) {
        do {
            let data = try jsonEncoder.encode(value)
            let file = try orchestrator.getWritableFile(writeSize: UInt64(data.count))

            if try file.size() == 0 {
                try file.append { (write: (Data) throws -> Void) in
                    try write(data)
                }
            } else {
                let atomicData = commaSeparatorData + data
                try file.append { write in
                    try write(atomicData)
                }
            }
        } catch {
            userLogger.error("🔥 Failed to write log: \(error)")
            developerLogger?.error("🔥 Failed to write file: \(error)")
        }
    }
}
