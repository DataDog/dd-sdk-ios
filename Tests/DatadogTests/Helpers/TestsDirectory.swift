/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import XCTest
@testable import Datadog

/// Creates `Directory` pointing to unique subfolder in `/var/folders/`.
/// Does not create the subfolder - it must be later created with `.create()`.
/// It returns different `Directory` each time it is called.
func obtainUniqueTemporaryDirectory() -> Directory {
    let subdirectoryName = "com.datadoghq.ios-sdk-tests-\(UUID().uuidString)"
    let osTemporaryDirectoryURL = URL(
        fileURLWithPath: NSTemporaryDirectory(),
        isDirectory: true
    ).appendingPathComponent(subdirectoryName, isDirectory: true)
    print("💡 Obtained temporary directory URL: \(osTemporaryDirectoryURL)")
    return Directory(url: osTemporaryDirectoryURL)
}

/// `Directory` pointing to subfolder in `/var/folders/`.
/// The subfolder does not exist and can be created and deleted by calling `.create()` and `.delete()`.
let temporaryDirectory = obtainUniqueTemporaryDirectory()

/// Extends `Directory` with set of utilities for convenient work with files in tests.
/// Provides handy methods to create / delete files and directories.
extension Directory {
    /// Creates empty directory with given attributes .
    @discardableResult
    func create(attributes: [FileAttributeKey: Any]? = nil, file: StaticString = #file, line: UInt = #line) -> Self {
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: attributes)
            let initialFilesCount = try files().count
            XCTAssert(initialFilesCount == 0, "🔥 `TestsDirectory` is not empty: \(url)", file: file, line: line)
        } catch {
            XCTFail("🔥 Failed to create `TestsDirectory`: \(error)", file: file, line: line)
        }
        return self
    }

    /// Deletes entire directory with its content.
    func delete(file: StaticString = #file, line: UInt = #line) {
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                XCTFail("🔥 Failed to delete `TestsDirectory`: \(error)", file: file, line: line)
            }
        }
    }

    /// Checks if directory exists.
    func exists() -> Bool {
        return FileManager.default.fileExists(atPath: url.path)
    }

    func createMockFiles(count: Int, prefix: String = "file") {
        (0..<count).forEach { index in
            _ = try! createFile(named: "\(prefix)\(index)")
        }
    }
}
