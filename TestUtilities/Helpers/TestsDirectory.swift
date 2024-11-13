/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import XCTest

/// Creates `Directory` pointing to unique subfolder in `/var/folders/`.
/// Does not create the subfolder - it must be later created with `.create()`.
/// It returns different `Directory` each time it is called.
public func obtainUniqueTemporaryDirectory(uuid: UUID = UUID()) -> URL {
    let subdirectoryName = "com.datadoghq.ios-sdk-tests-\(uuid.uuidString)"
    let osTemporaryDirectoryURL = URL(
        fileURLWithPath: NSTemporaryDirectory(),
        isDirectory: true
    ).appendingPathComponent(subdirectoryName, isDirectory: true)
    print("💡 Obtained temporary directory URL: \(osTemporaryDirectoryURL)")
    return osTemporaryDirectoryURL
}

/// `Directory` pointing to subfolder in `/var/folders/`.
/// The subfolder does not exist and can be created and deleted by calling `.create()` and `.delete()`.
public let temporaryDirectory = obtainUniqueTemporaryDirectory()

/// Creates empty directory with given attributes .
public func CreateTemporaryDirectory(attributes: [FileAttributeKey: Any]? = nil, file: StaticString = #file, line: UInt = #line) {
    do {
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true, attributes: attributes)
        let files = try FileManager.default
            .contentsOfDirectory(at: temporaryDirectory, includingPropertiesForKeys: [.isRegularFileKey, .canonicalPathKey])
        XCTAssert(files.count == 0, "🔥 `temporaryDirectory` is not empty: \(temporaryDirectory)", file: file, line: line)
    } catch {
        XCTFail("🔥 `CreateTemporaryDirectory()` failed: \(error)", file: file, line: line)
    }
}


/// Deletes entire directory with its content.
public func DeleteTemporaryDirectory(file: StaticString = #file, line: UInt = #line) {
    if FileManager.default.fileExists(atPath: temporaryDirectory.path) {
        do {
            try FileManager.default.removeItem(at: temporaryDirectory)
        } catch {
            XCTFail("🔥 `DeleteTemporaryDirectory()` failed: \(error)", file: file, line: line)
        }
    }
}
