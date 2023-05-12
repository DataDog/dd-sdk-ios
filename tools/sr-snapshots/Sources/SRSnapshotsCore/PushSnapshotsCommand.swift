/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

internal func pushSnapshots(from localRepo: LocalRepo, to remoteRepo: RemoteRepo) throws {
    try remoteRepo.pull()

    // Create pointers from all local files
    let allPointers = try localRepo.createPointers()

    // Determine new files to push to remote repo:
    let newLocalFilesWithPointers: [(FileLocation, Pointer)] = allPointers
        // 1. Filter out files that exist in remote repo
        .filter { pointer in !remoteRepo.remoteFileLocation(for: pointer).exists() }
        // 2. Map each pointer into "local file" location
        .map { pointer in (localRepo.localFileLocation(for: pointer), pointer) }

    for (localFile, pointer) in newLocalFilesWithPointers {
        // Copy each new "local file" to "remote file" location determined by pointer
        let remoteFile = remoteRepo.remoteFileLocation(for: pointer)
        try localFile.copy(to: remoteFile)
    }
    // Write all pointers for all new "local files"
    try localRepo.write(pointers: allPointers)

    let newFilesCount = newLocalFilesWithPointers.count

    print("⬆️   Pushing \(newFilesCount) file(s)")

    if newFilesCount > 0 {
        let filesList = newLocalFilesWithPointers
            .map { "- " + $0.1.localFilePath + " (hash: \($0.1.contentHash.prefix(7)))" }
            .joined(separator: "\n")

        try remoteRepo.commit(
            message: """
            Add \(newFilesCount) file(s)

            Files added:
            \(filesList)
            """
        )
        try remoteRepo.push()
    }
}
