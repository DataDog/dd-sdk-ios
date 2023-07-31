/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
@testable import DatadogCore

/*
 Set of Datadog domain extensions over standard types for writing more readable tests.
 Domain agnostic extensions should be put in `SwiftExtensions.swift`.
*/

extension Date {
    /// Returns name of the logs file created at this date.
    var toFileName: String {
        return fileNameFrom(fileCreationDate: self)
    }
}

extension File {
    func makeReadonly() throws {
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: url.path)
    }

    func makeReadWrite() throws {
        try FileManager.default.setAttributes([.immutable: false], ofItemAtPath: url.path)
    }

    /// Reads the file content and returns events data assuming that file uses TLV format.
    func readTLVEvents() throws -> [Data] {
        let blocks = try DataBlockReader(input: stream()).all()
        return blocks.map { $0.data }
    }
}
