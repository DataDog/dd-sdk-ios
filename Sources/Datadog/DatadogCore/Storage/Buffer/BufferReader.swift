/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

internal final class BufferReader {

    let file: URL

    let queue: DispatchQueue

    let encryption: DataEncryption?

    private var reader: DataBlockReader?

    init(
        file: URL,
        queue: DispatchQueue,
        encryption: DataEncryption?
    ) {
        self.file = file
        self.queue = queue
        self.encryption = encryption
    }

    func read<T>(_ block: (BufferStream) throws -> T) rethrows -> T {
        try queue.sync {
            guard let reader = DataBlockReader(url: file) else {
                throw InternalError(description: "Unable to open buffer reader")
            }

            let streamer = Streamer(reader: reader, encryption: encryption)
            self.reader = reader
            return try block(streamer)
        }
    }

    func flush() {
        queue.async {
            guard let reader = self.reader else {
                return
            }

            do {
                let fs = FileManager.default
                let tmp = self.file.appendingPathExtension("tmp")
                if fs.fileExists(atPath: tmp.path) {
                    try fs.removeItem(at: tmp)
                }

                fs.createFile(atPath: tmp.path, contents: nil)

                guard let output = OutputStream(url: tmp, append: false) else {
                    return
                }

                output.open()
                reader.flush(to: output)
                output.close()

                try fs.removeItem(at: self.file)
                try fs.moveItem(at: tmp, to: self.file)

                self.reader = nil
            } catch {
                DD.telemetry.error("Failed to flush buffer upload", error: error)
            }
        }
    }
}

private final class Streamer: BufferStream {

    let reader: DataBlockReader

    let encryption: DataEncryption?

    init(reader: DataBlockReader, encryption: DataEncryption?) {
        self.reader = reader
        self.encryption = encryption
    }

    func stream(_ next: (DataBlock) throws -> Bool) throws {
        guard let block = try self.next() else {
            throw BufferStreamError.noData
        }

        guard try next(block) else {
            return
        }

        while let block = try self.next() {
            guard try next(block) else {
                return
            }
        }
    }

    private func next() throws -> DataBlock? {
        guard var block = try reader.next() else {
            return nil
        }

        if let encryption = encryption {
            block.data = try encryption.decrypt(data: block.data)
        }

        return block
    }
}
