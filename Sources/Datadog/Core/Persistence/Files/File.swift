/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import _Datadog_Private

/// Provides convenient interface for reading metadata and appending data to the file.
internal protocol WritableFile {
    /// Name of this file.
    var name: String { get }

    /// Current size of this file.
    func size() throws -> UInt64

    /// Synchronously appends given data at the end of this file.
    func append(transaction: ((Data) throws -> Void) throws -> Void) throws
}

/// Provides convenient interface for reading contents and metadata of the file.
internal protocol ReadableFile {
    /// Name of this file.
    var name: String { get }

    /// Reads the available data in this file.
    func read() throws -> Data

    /// Deletes this file.
    func delete() throws
}

/// An immutable `struct` designed to provide optimized and thread safe interface for file manipulation.
/// It doesn't own the file, which means the file presence is not guaranteed - the file can be deleted by OS at any time (e.g. due to memory pressure).
internal struct File: WritableFile, ReadableFile {
    let url: URL
    let name: String

    init(url: URL) {
        self.url = url
        self.name = url.lastPathComponent
    }

    /// Appends given data at the end of this file.
    func append(transaction: ((Data) throws -> Void) throws -> Void) throws {
        let fileHandle = try FileHandle(forWritingTo: url)
        defer { fileHandle.closeFile() }

        try objcExceptionHandler.rethrowToSwift {
            fileHandle.seekToEndOfFile()
        }

        // Writes given data at the end of the file.
        func appendData(_ data: Data) throws {
            try objcExceptionHandler.rethrowToSwift {
                fileHandle.write(data)
            }
        }

        try transaction { chunkOfData in
            try appendData(chunkOfData)
        }
    }

    func read() throws -> Data {
        let fileHandle = try FileHandle(forReadingFrom: url)
        defer { fileHandle.closeFile() }
        return fileHandle.readDataToEndOfFile()
    }

    func size() throws -> UInt64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return attributes[.size] as? UInt64 ?? 0
    }

    func delete() throws {
        try FileManager.default.removeItem(at: url)
    }
}
