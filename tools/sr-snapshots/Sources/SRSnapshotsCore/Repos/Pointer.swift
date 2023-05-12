/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// A "link"  between volatile files from`LocalRepo` and persistent files in `RemoteRepo`.
internal struct Pointer: Equatable, Hashable {
    /// The path to the local file this pointer was creted for.
    /// This path is relative to the local files directory and it includes the file extension.
    let localFilePath: String
    var localFileExtension: String? { extensionOfFile(at: localFilePath) }
    /// The hash of file's content that this pointer was created for.
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
