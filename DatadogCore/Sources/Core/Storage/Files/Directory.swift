/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

extension Data {
    static let empty = Data()
}

/// Provides interfaces for accessing common properties and operations for a directory.
internal protocol DirectoryProtocol: FileProtocol {
    /// Returns list of subdirectories in the directory.
    /// - Returns: list of subdirectories.
    func subdirectories() throws -> [Directory]
}

/// An abstraction over file system directory where SDK stores its files.
internal struct Directory: DirectoryProtocol {
    let url: URL

    /// Creates subdirectory with given path under system caches directory.
    /// RUMM-2169: Use `Directory.cache().createSubdirectory(path:)` instead.
    init(withSubdirectoryPath path: String) throws {
        self.init(url: try Directory.cache().createSubdirectory(path: path).url)
    }

    init(url: URL) {
        self.url = url
    }

    func modifiedAt() throws -> Date? {
        try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
    }

    /// Returns list of subdirectories using system APIs.
    /// - Returns: list of subdirectories.
    func subdirectories() throws -> [Directory] {
        try FileManager.default
            .contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey, .canonicalPathKey])
            .filter { url in
                var isDirectory = ObjCBool(false)
                FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
                return isDirectory.boolValue
            }
            .map { url in Directory(url: url) }
    }

    /// Recursively goes through subdirectories and finds the most recent modified file before given date.
    /// This includes files in subdirectories, files in this directory and itself.
    /// - Parameter before: The date to compare the last modification date of files.
    /// - Returns: The latest modified file or `nil` if no files were modified before given date.
    func mostRecentModifiedFile(before: Date) throws -> FileProtocol? {
        let mostRecentModifiedInSubdirectories = try subdirectories()
            .compactMap { directory in
                try directory.mostRecentModifiedFile(before: before)
            }
            .max { file1, file2 in
                guard let modifiedAt1 = try file1.modifiedAt(), let modifiedAt2 = try file2.modifiedAt() else {
                    return false
                }
                return modifiedAt1 < modifiedAt2
            }

        let files = try self.files()

        return try ([self, mostRecentModifiedInSubdirectories].compactMap { $0 } + files)
            .filter {
                guard let modifiedAt = try $0.modifiedAt() else {
                    return false
                }
                return modifiedAt < before
            }
            .max { file1, file2 in
                guard let modifiedAt1 = try file1.modifiedAt(), let modifiedAt2 = try file2.modifiedAt() else {
                    return false
                }
                return modifiedAt1 < modifiedAt2
            }
    }

    /// Creates subdirectory with given path by creating intermediate directories if needed.
    /// If directory already exists at given `path` it will be used, without being altered.
    func createSubdirectory(path: String) throws -> Directory {
        let subdirectoryURL = url.appendingPathComponent(path, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: subdirectoryURL, withIntermediateDirectories: true, attributes: nil)
        } catch {
            throw InternalError(description: "Cannot create subdirectory in `/Library/Caches/` folder.")
        }
        return Directory(url: subdirectoryURL)
    }

    /// Returns directory at given path or throws if it doesn't exist or given `path` is not a directory.
    func subdirectory(path: String) throws -> Directory {
        let directoryURL = url.appendingPathComponent(path, isDirectory: true)
        var isDirectory = ObjCBool(false)
        let exists = FileManager.default.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory)

        if exists && isDirectory.boolValue {
            return Directory(url: directoryURL)
        } else {
            throw InternalError(description: "Path doesn't exist or is not a directory: \(directoryURL)")
        }
    }

    /// Creates file with given name.
    func createFile(named fileName: String) throws -> File {
        let fileURL = url.appendingPathComponent(fileName, isDirectory: false)
        try Data.empty.write(to: fileURL, options: .atomic)
        return File(url: fileURL)
    }

    /// Checks if a file with given `fileName` exists in this directory.
    func hasFile(named fileName: String) -> Bool {
        let fileURL = url.appendingPathComponent(fileName, isDirectory: false)
        return FileManager.default.fileExists(atPath: fileURL.path)
    }

    /// Returns file with given name or throws an error if file does not exist.
    func file(named fileName: String) throws -> File {
        let fileURL = url.appendingPathComponent(fileName, isDirectory: false)
        guard hasFile(named: fileName) else {
            throw InternalError(description: "File does not exist at path: \(fileURL.path)")
        }
        return File(url: fileURL)
    }

    /// Returns count of files in this directory.
    func filesCount() throws -> Int {
        return try FileManager.default
            .contentsOfDirectory(at: url, includingPropertiesForKeys: [.isRegularFileKey])
            .count
    }

    /// Returns all files of this directory.
    func files() throws -> [File] {
        return try FileManager.default
            .contentsOfDirectory(at: url, includingPropertiesForKeys: [.isRegularFileKey, .canonicalPathKey])
            .map { url in File(url: url) }
    }

    /// Deletes all files in this directory.
    func deleteAllFiles() throws {
        // Instead of iterating over all files and removing them one by one, we create a temporary
        // empty directory and replace source directory content with (empty) temporary folder.
        // This makes the deletion atomic, and is more performant in benchmarks.
        let temporaryDirectory = try Directory(withSubdirectoryPath: "com.datadoghq/\(UUID().uuidString)")
        try retry(times: 3, delay: 0.001) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temporaryDirectory.url)
        }
        if FileManager.default.fileExists(atPath: temporaryDirectory.url.path) {
            try FileManager.default.removeItem(at: temporaryDirectory.url)
        }
    }

    /// Moves all files from this directory to `destinationDirectory`.
    func moveAllFiles(to destinationDirectory: Directory) throws {
        try retry(times: 3, delay: 0.001) {
            try files().forEach { file in
                let destinationFileURL = destinationDirectory.url.appendingPathComponent(file.name)
                try? retry(times: 3, delay: 0.0001) {
                    try FileManager.default.moveItem(at: file.url, to: destinationFileURL)
                }
            }
        }
    }
}

extension Directory {
    /// Returns `Directory` pointing to `/Library/Caches`.
    /// - `/Library/Caches` is exclduded from iTunes and iCloud backups by default.
    /// - System may delete data in `/Library/Cache` to free up disk space which reduces the impact on devices working under heavy space pressure.
    static func cache() throws -> Directory {
        guard let cachesDirectoryURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            throw InternalError(description: "Cannot obtain `/Library/Caches/` url.")
        }
        return Directory(url: cachesDirectoryURL)
    }
}
