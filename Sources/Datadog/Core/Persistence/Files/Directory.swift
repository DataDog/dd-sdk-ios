/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// An abstraction over file system directory where SDK stores its files.
internal struct Directory {
    let url: URL

    /// Creates subdirectory with given path under system caches directory.
    init(withSubdirectoryPath path: String) throws {
        self.init(url: try createCachesSubdirectoryIfNotExists(subdirectoryPath: path))
    }

    init(url: URL) {
        self.url = url
    }

    /// Creates file with given name.
    func createFile(named fileName: String) throws -> File {
        let fileURL = url.appendingPathComponent(fileName, isDirectory: false)
        guard FileManager.default.createFile(atPath: fileURL.path, contents: nil, attributes: nil) == true else {
            throw InternalError(description: "Cannot create file at path: \(fileURL.path)")
        }
        return File(url: fileURL)
    }

    /// Returns file with given name.
    func file(named fileName: String) throws -> File {
        let fileURL = url.appendingPathComponent(fileName, isDirectory: false)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw InternalError(description: "File does not exist at path: \(fileURL.path)")
        }
        return File(url: fileURL)
    }

    /// Returns all files of this directory.
    func files() throws -> [File] {
        return try FileManager.default
            .contentsOfDirectory(at: url, includingPropertiesForKeys: [.isRegularFileKey, .canonicalPathKey])
            .map { url in File(url: url) }
    }
}

/// Creates subdirectory at given path in `/Library/Caches` if it does not exist. Might throw `ProgrammerError` when it's not possible.
/// * `/Library/Caches` is exclduded from iTunes and iCloud backups by default.
/// * System may delete data in `/Library/Cache` to free up disk space which reduces the impact on devices working under heavy space pressure.
private func createCachesSubdirectoryIfNotExists(subdirectoryPath: String) throws -> URL {
    guard let cachesDirectoryURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
        throw ProgrammerError(description: "Cannot obtain `/Library/Caches/` url.")
    }
    let subdirectoryURL = cachesDirectoryURL.appendingPathComponent(subdirectoryPath, isDirectory: true)
    do {
        try FileManager.default.createDirectory(at: subdirectoryURL, withIntermediateDirectories: true, attributes: nil)
    } catch {
        throw ProgrammerError(description: "Cannot create subdirectory in `/Library/Caches/` folder.")
    }
    return subdirectoryURL
}
