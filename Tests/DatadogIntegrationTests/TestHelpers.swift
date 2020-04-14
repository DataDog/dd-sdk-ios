//
//  TestHelpers.swift
//  IntegrationTests
//
//  Created by Mert Buran on 15/04/2020.
//  Copyright © 2020 Datadog. All rights reserved.
//

import Foundation

func clearPersistedLogs() throws {
    let logFilesSubdirectory = "com.datadoghq.logs/v1"
    let cachesDirectoryURL = FileManager.default.urls(
        for: .cachesDirectory,
        in: .userDomainMask
    ).first
    let subdirectoryURL = cachesDirectoryURL?.appendingPathComponent(
        logFilesSubdirectory,
        isDirectory: true
    )
    if let dirToRemove = subdirectoryURL {
        try FileManager.default.removeItem(at: dirToRemove)
    }
}
