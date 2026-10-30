/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
@testable import DatadogCrashReporting
import KSCrashRecording

final class KSCrashPluginTests: XCTestCase {
    // MARK: - Configuration Tests

    func testConfiguration() throws {
        // When
        let config: KSCrashConfiguration = try .datadog(bundle: .mockWith(bundleIdentifier: "com.example.app"))

        // Then
        let caches = try XCTUnwrap(FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first)
        #if os(macOS)
        XCTAssertEqual(config.installPath, caches.appendingPathComponent("com.example.app/com.datadoghq.crash-reporting/v2").path)
        #else
        XCTAssertEqual(config.installPath, caches.appendingPathComponent("com.datadoghq.crash-reporting/v2").path)
        #endif
        XCTAssertEqual(config.reportStoreConfiguration.maxReportCount, 1)
        XCTAssertEqual(config.reportStoreConfiguration.reportCleanupPolicy, .never)
    }

    #if os(macOS)
    func testOnMacOS_givenExecutableWithoutBundleIdentifier_whenConfiguring_thenInstallPathIsInTheExecutableSubdirectory() throws {
        // When
        let config: KSCrashConfiguration = try .datadog(
            bundle: .mockWith(bundleIdentifier: nil, executableURL: URL(fileURLWithPath: "/usr/local/bin/helper"))
        )

        // Then
        let caches = try XCTUnwrap(FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first)
        XCTAssertEqual(config.installPath, caches.appendingPathComponent("helper-ddece4a4663236ed/com.datadoghq.crash-reporting/v2").path)
    }

    func testOnMacOS_givenTwoApps_whenConfiguring_thenInstallPathsAreDifferent() throws {
        // When
        let config1: KSCrashConfiguration = try .datadog(bundle: .mockWith(bundleIdentifier: "com.example.app1"))
        let config2: KSCrashConfiguration = try .datadog(bundle: .mockWith(bundleIdentifier: "com.example.app2"))

        // Then
        XCTAssertNotEqual(config1.installPath, config2.installPath)
    }
    #endif

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
