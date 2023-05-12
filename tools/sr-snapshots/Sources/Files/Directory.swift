/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Enables operations on real directory in file system.
public struct Directory: DirectoryProtocol {
    private let fileManager = FileManager.default
    public let url: URL

    public init(url: URL) throws {
        self.url = url
        try createDirectoryIfNotExists(url: url)
    }

    public func readFile(at relativePath: String) throws -> Data {
        return try Data(contentsOf: fileURL(at: relativePath))
    }

    public func writeFile(at relativePath: String, data: Data) throws {
        let fileURL = self.fileURL(at: relativePath)
        let folderURL = fileURL.deletingLastPathComponent()
        try createDirectoryIfNotExists(url: folderURL)
        try data.write(to: fileURL)
    }

    public func fileExists(at relativePath: String) -> Bool {
        return fileManager.fileExists(atPath: fileURL(at: relativePath).path)
    }

    public func findAllFiles() throws -> [String] {
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return []
        }
        var paths: [String] = []
        for case let url as URL in enumerator where !isDirectory(url: url) {
            paths.append(relativeFilePath(for: url))
        }
        return paths
    }

    public func copyFile(at relativePath: String, to otherDirectory: DirectoryProtocol, at newRelativePath: String) throws {
        if let otherDirectory = otherDirectory as? Directory, !otherDirectory.fileExists(at: newRelativePath) {
            let thisURL = fileURL(at: relativePath)
            let otherURL = otherDirectory.fileURL(at: newRelativePath)
            let otherFolderURL = otherURL.deletingLastPathComponent()
            try createDirectoryIfNotExists(url: otherFolderURL)
            try fileManager.copyItem(at: thisURL, to: otherURL)
        }
    }

    public func deleteAllFiles() throws {
        try fileManager.removeItem(at: url)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: false)
    }

    public func deleteFile(at relativePath: String) throws {
        try fileManager.removeItem(at: fileURL(at: relativePath))
    }

    // MARK: - Private

    private func createDirectoryIfNotExists(url: URL) throws {
        if !fileManager.fileExists(atPath: url.path()) {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    private func fileURL(at relativePath: String) -> URL {
        return url.appending(path: relativePath, directoryHint: .notDirectory)
    }

    private func relativeFilePath(for fileURL: URL) -> String {
        let dirComponents = url.resolvingSymlinksInPath().pathComponents
        let fileComponents = fileURL.resolvingSymlinksInPath().pathComponents
        let path = fileComponents.dropFirst(dirComponents.count)
        return path.joined(separator: "/")
    }

    private func isDirectory(url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
    }
}

public extension Directory {
    func delete() throws { try fileManager.removeItem(at: url) }
}

public func uniqueTemporaryDirectoryURL() -> URL {
    let osTemporaryDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    let testDirectoryName = "com.datadoghq.sr-snapshots-tests-\(UUID().uuidString)"
    return osTemporaryDirectoryURL.appending(component: testDirectoryName, directoryHint: .isDirectory)
}
