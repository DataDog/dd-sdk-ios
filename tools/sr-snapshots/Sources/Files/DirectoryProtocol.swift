/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Abstract operations on files directory.
public protocol DirectoryProtocol {
    func readFile(at relativePath: String) throws -> Data
    func writeFile(at relativePath: String, data: Data) throws
    func fileExists(at relativePath: String) -> Bool
    func copyFile(at relativePath: String, to otherDirectory: DirectoryProtocol, at newRelativePath: String) throws
    func findAllFiles() throws -> [String]
    func deleteAllFiles() throws
    func deleteFile(at relativePath: String) throws
}

// MARK: - Convenience Helpers

public extension DirectoryProtocol {
    func readAllFiles() throws -> [String: String] {
        var all: [String: String] = [:]
        for filePath in try findAllFiles() {
            let data = try readFile(at: filePath)
            all[filePath] = try String(data: data, encoding: .utf8).unwrapOrThrow()
        }
        return all
    }

    func numberOfFiles() throws -> Int {
        return try findAllFiles().count
    }

    func copyAllFiles(to otherDirectory: DirectoryProtocol) throws {
        try otherDirectory.deleteAllFiles()
        for filePath in try findAllFiles() {
            let data = try readFile(at: filePath)
            try otherDirectory.writeFile(at: filePath, data: data)
        }
    }
}
