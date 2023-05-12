/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// An in-memory version of directory.
public class InMemoryDirectory: DirectoryProtocol {
    private var files: [String: String]

    public init(_ files: [String: String]) {
        self.files = files
    }

    public func readFile(at path: String) throws -> Data {
        try (files[path]?.data(using: .utf8)).unwrapOrThrow()
    }

    public func writeFile(at path: String, data: Data) throws {
        files[path] = try String(data: data, encoding: .utf8).unwrapOrThrow()
    }

    public func fileExists(at relativePath: String) -> Bool {
        return files[relativePath] != nil
    }

    public func copyFile(at relativePath: String, to otherDirectory: DirectoryProtocol, at newRelativePath: String) throws {
        try otherDirectory.writeFile(
            at: newRelativePath,
            data: try readFile(at: relativePath)
        )
    }

    public func findAllFiles() -> [String] {
        files.keys.map { $0 }
    }

    public func deleteAllFiles() throws {
        files = [:]
    }

    public func deleteFile(at relativePath: String) throws {
        files[relativePath] = nil
    }
}

extension Optional {
    struct UnwrappingException: Error {}

    public func unwrapOrThrow() throws -> Wrapped {
        switch self {
        case .some(let value): return value
        case .none: throw UnwrappingException()
        }
    }
}
