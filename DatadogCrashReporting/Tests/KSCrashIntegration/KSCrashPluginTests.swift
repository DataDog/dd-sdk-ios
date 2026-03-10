/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogCrashReporting
import KSCrashRecording

final class KSCrashPluginTests: XCTestCase {
    // MARK: - Configuration Tests

    func testConfiguration() throws {
        // When
        let config: KSCrashConfiguration = try .datadog()

        // Then
        XCTAssertTrue(config.installPath?.contains("/Library/Caches/com.datadoghq.crash-reporting/v2") ?? false)
        XCTAssertEqual(config.reportStoreConfiguration.maxReportCount, 1)
        XCTAssertEqual(config.reportStoreConfiguration.reportCleanupPolicy, .never)
    }

    func testCStringFromContextAppendsTrailingNullTerminator() {
        // Given
        let context = Data("{\"context\":\"value\"}".utf8)

        // When
        let cString = cStringBytesFrom(context: context)

        // Then
        XCTAssertEqual(cString.dropLast(), context[...])
        XCTAssertEqual(cString.last, 0)
    }

    func testCStringFromContextPreservesExplicitTrailingNullCharacter() {
        // Given
        let context = Data([123, 125, 0])

        // When
        let cString = cStringBytesFrom(context: context)

        // Then
        XCTAssertEqual(cString, Data([123, 125, 0, 0]))
    }

    /// Rebuilds the exact C-string bytes (`utf8` payload + trailing `\0`) used by `inject(context:)`.
    private func cStringBytesFrom(context: Data) -> Data {
        let contextString = String(decoding: context, as: UTF8.self)
        return Data(contextString.utf8CString.map(UInt8.init(bitPattern:)))
    }
}
