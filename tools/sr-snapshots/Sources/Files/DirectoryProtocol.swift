/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Abstracts operations on directory.
public protocol DirectoryProtocol {
    /// Reads content of file at given path.
    /// - Parameter relativePath: relative path to the file
    /// - Returns: the content of file
    func readFile(at relativePath: String) throws -> Data

    /// Writes new content of file at given path.
    /// It will create the file and its parent folder(s) if it does not exist.
    /// - Parameters:
    ///   - relativePath: relative path to the file
    ///   - data: new content of the file
    func writeFile(at relativePath: String, data: Data) throws

    /// Checks if file exists at given path.
    /// - Parameter relativePath: relative path to the file
    /// - Returns: `true` if file exists
    func fileExists(at relativePath: String) -> Bool

    /// Copies content of file at given path to another directory.
    /// It will create parent folder(s) in new directory if it does not exist.
    /// - Parameters:
    ///   - relativePath: relative path to the file in this directory
    ///   - otherDirectory: directory to copy the file to
    ///   - newRelativePath: relative path to the file in target directory
    func copyFile(at relativePath: String, to otherDirectory: DirectoryProtocol, at newRelativePath: String) throws

    /// Recursively searches this directory and finds all files.
    /// - Returns: relative paths to all files stored in this (and child) directories
    func findAllFiles() throws -> [String]

    /// Deletes all files and folders in this directory.
    func deleteAllFiles() throws

    /// Deletes file at given path.
    /// - Parameter relativePath: relative path to the file
    func deleteFile(at relativePath: String) throws
}

// MARK: - Convenience Helpers

public extension DirectoryProtocol {
    /// Returns paths and content of all files in this directory.
    /// - Returns: a dictionary keyed by relative file path and value being the file's content (utf-8 string).
    func readAllFiles() throws -> [String: String] {
        var all: [String: String] = [:]
        for filePath in try findAllFiles() {
            let data = try readFile(at: filePath)
            all[filePath] = try String(data: data, encoding: .utf8).unwrapOrThrow()
        }
        return all
    }

    /// Recursively searches this directory and returns the number of all files.
    /// - Returns: the number of files in this directory
    func numberOfFiles() throws -> Int {
        return try findAllFiles().count
    }

    /// Copies all files from this directory to another directory. Files in target directory will use
    /// the same relative paths.
    /// - Parameter otherDirectory: target directory to copy files to
    func copyAllFiles(to otherDirectory: DirectoryProtocol) throws {
        try otherDirectory.deleteAllFiles()
        for filePath in try findAllFiles() {
            let data = try readFile(at: filePath)
            try otherDirectory.writeFile(at: filePath, data: data)
        }
    }
}
