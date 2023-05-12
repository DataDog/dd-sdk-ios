/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Files

/// A location of a file.
///
/// It doesn't know if the file exists or not - this can be checked with `exists()` call.
internal struct FileLocation {
    /// A directory that holds this file under.
    let directory: DirectoryProtocol
    /// Relative path to the file within `directory`.
    let path: String

    func exists() -> Bool {
        directory.fileExists(at: path)
    }

    func copy(to otherLocation: FileLocation) throws {
        try directory.copyFile(at: path, to: otherLocation.directory, at: otherLocation.path)
    }
}
