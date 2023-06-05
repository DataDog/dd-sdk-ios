/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// A "link"  between volatile files from`LocalRepo` and persistent files in `RemoteRepo`.
///
/// Pointers are created from "local files" and must contain enough information to determine the
/// location of "remote file".
internal struct Pointer: Equatable, Hashable {
    /// The path to the "local file" this pointer was created for.
    /// This path is relative to the local directory and it includes the file extension.
    let localFilePath: String
    /// The extension of the "local file".
    var localFileExtension: String? { extensionOfFile(at: localFilePath) }
    /// The hash of the "local file's" content.
    let contentHash: String
}

extension Pointer {
    /// Creates pointer from local file using given hashing algorithm.
    init(localFile: FileLocation, hashing: Hashing) throws {
        self.localFilePath = localFile.path
        let fileContent = try localFile.directory.readFile(at: localFile.path)
        self.contentHash = hashing.hash(from: fileContent)
    }
}

private func extensionOfFile(at path: String) -> String? {
    guard let fileName = path.split(separator: "/").last else {
        return nil
    }
    let split = fileName.split(separator: ".").map { String($0) }
    return split.count > 1 ? split.last : nil
}
