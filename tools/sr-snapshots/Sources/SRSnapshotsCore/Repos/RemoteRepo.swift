/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Files
import Git
import Foundation

/// Abstracts the remote repository.
///
/// Snapshots repository stores the actual snapshot files in git. We call them "remote files".
/// Remote files are referenced by pointers from `LocalRepo`.
internal struct RemoteRepo {
    /// Git client operating in this repository.
    let git: GitClient
    /// Directory with "remote files".
    let remoteFilesDirectory: DirectoryProtocol

    func remoteFileLocation(for pointer: Pointer) -> FileLocation {
        let fileExtension = pointer.localFileExtension.map { "." + $0 } ?? ""
        let fileName = pointer.contentHash
        let folderName = pointer.contentHash.prefix(1)
        let path = "/" + folderName + "/" + fileName + fileExtension
        return FileLocation(directory: remoteFilesDirectory, path: path)
    }

    func pull() throws { try git.pull() }
    func commit(message: String) throws { try git.commit(message: message) }
    func push() throws { try git.push() }
}
