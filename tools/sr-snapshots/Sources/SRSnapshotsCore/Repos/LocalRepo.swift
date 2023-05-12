/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Files
import Foundation

/// Abstracts the local repository.
///
/// Local repository manages two types of files:
/// - "pointer files" that reference "remote files" from `RemoteRepo`;
/// - "local files" that are violatile (git-ignored) copies of "remote files".
///
/// "Pointer files" and "local files" are stored in distinct folders.
/// The structure of pointers folder mirrors the tree structure of files folder.
internal struct LocalRepo {
    /// Directory with "local files".
    let localFilesDirectory: DirectoryProtocol
    /// Directory with "pointer files".
    let pointersDirectory: DirectoryProtocol
    /// An interface for computing pointer's hash.
    let pointersHashing: Hashing

    private struct PointerFileContent: Codable {
        let hash: String
    }

    private let jsonEncoder = JSONEncoder()
    private let jsonDecoder = JSONDecoder()

    /// Creates pointers from "local files".
    func createPointers() throws -> [Pointer] {
        return try localFilesDirectory.findAllFiles()
            .map { path in
                let localFile = FileLocation(directory: localFilesDirectory, path: path)
                return try Pointer(localFile: localFile, hashing: pointersHashing)
            }
    }

    /// Reads pointers from "pointer files".
    func readPointers() throws -> [Pointer] {
        return try pointersDirectory.findAllFiles()
            .map { path in
                let data = try pointersDirectory.readFile(at: path)
                let content = try jsonDecoder.decode(PointerFileContent.self, from: data)
                let localFilePath = String(path.dropLast(".json".count))
                return Pointer(localFilePath: localFilePath, contentHash: content.hash)
            }
    }

    /// Writes new "pointer files" with deleting existing ones.
    func write(pointers: [Pointer]) throws {
        try pointersDirectory.deleteAllFiles()
        try pointers.forEach { pointer in
            let content = PointerFileContent(hash: pointer.contentHash)
            let data = try jsonEncoder.encode(content)
            try pointersDirectory.writeFile(at: pointer.localFilePath + ".json", data: data)
        }
    }

    /// Obtains the location of "local file" for given pointer. 
    func localFileLocation(for pointer: Pointer) -> FileLocation {
        return FileLocation(directory: localFilesDirectory, path: pointer.localFilePath)
    }

    func deleteLocalFiles() throws {
        try localFilesDirectory.deleteAllFiles()
    }
}

extension LocalRepo {
    init(filesDirectoryURL: URL, pointersDirectoryURL: URL) throws {
        self.init(
            localFilesDirectory: try Directory(url: filesDirectoryURL),
            pointersDirectory: try Directory(url: pointersDirectoryURL),
            pointersHashing: SHA256Hashing()
        )
    }
}
