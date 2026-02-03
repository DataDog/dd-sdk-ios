/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Provides interfaces for accessing common properties and operations for a file.
internal protocol FileProtocol {
    /// URL of the file on the disk.
    var url: URL { get }

    /// Returns the date when the file was last modified. Returns `nil` if the file does not exist.
    /// If the file is created and never modified, the creation date is returned.
    /// - Returns: The date when the file was last modified.
    func modifiedAt() throws -> Date?
}

/// Provides convenient interface for reading metadata and appending data to the file.
internal protocol WritableFile {
    /// Name of this file.
    var name: String { get }

    /// Current size of this file.
    func size() throws -> UInt64

    /// Synchronously appends given data at the end of this file.
    func append(data: Data) throws
}

/// Provides convenient interface for reading contents and metadata of the file.
internal protocol ReadableFile {
    /// Name of this file.
    var name: String { get }

    /// Current size of this file.
    func size() throws -> UInt64

    /// Creates InputStream for reading the available data from this file.
    func stream() throws -> InputStream

    /// Deletes this file.
    func delete() throws
}

private enum FileError: Error {
    case unableToCreateInputStream
}

/// An immutable `struct` designed to provide optimized and thread safe interface for file manipulation.
/// It doesn't own the file, which means the file presence is not guaranteed - the file can be deleted by OS at any time (e.g. due to memory pressure).
internal struct File: WritableFile, ReadableFile, FileProtocol, Equatable {
    let url: URL
    let name: String

    init(url: URL) {
        self.url = url
        self.name = url.lastPathComponent
    }

    func modifiedAt() throws -> Date? {
        try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
    }

    /// Appends given data at the end of this file.
    func append(data: Data) throws {
        let fileHandle = try FileHandle(forWritingTo: url)

        // NOTE: RUMM-669
        // https://github.com/DataDog/dd-sdk-ios/issues/214
        // https://en.wikipedia.org/wiki/Xcode#11.x_series
        // compiler version needs to have iOS 13.4+ as base SDK
        #if compiler(>=5.2)
        /**
         Even though the `fileHandle.seekToEnd()` should be available since iOS 13.0:
         ```
         @available(OSX 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
         public func seekToEnd() throws -> UInt64
         ```
         it crashes on iOS Simulators prior to iOS 13.4:
         ```
         Symbol not found: _$sSo12NSFileHandleC10FoundationE9seekToEnds6UInt64VyKF
         ```
         This is fixed in iOS 14/Xcode 12
        */
        if #available(iOS 13.4, tvOS 13.4, *) {
            defer { try? fileHandle.close() }
            try fileHandle.seekToEnd()
            try fileHandle.write(contentsOf: data)
        } else {
            try legacyAppend(data, to: fileHandle)
        }
        #else
        try legacyAppend(data, to: fileHandle)
        #endif
    }

    func write(data: Data) throws {
        // The `.atomic` option writes data to an auxiliary file first and then replace the original
        // file with the auxiliary file when the write completes
        try data.write(to: url, options: .atomic)
    }

    private func legacyAppend(_ data: Data, to fileHandle: FileHandle) throws {
        defer {
            try? objc_rethrow {
                fileHandle.closeFile()
            }
        }
        try objc_rethrow {
            fileHandle.seekToEndOfFile()
            fileHandle.write(data)
        }
    }

    func stream() throws -> InputStream {
        guard let stream = InputStream(url: url) else {
            throw FileError.unableToCreateInputStream
        }
        return stream
    }

    func size() throws -> UInt64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return attributes[.size] as? UInt64 ?? 0
    }

    func delete() throws {
        try FileManager.default.removeItem(at: url)
    }
}
