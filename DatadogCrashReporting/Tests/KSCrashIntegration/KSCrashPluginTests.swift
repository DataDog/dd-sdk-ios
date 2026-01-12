/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogCrashReporting
import KSCrashRecording

class KSCrashPluginTests: XCTestCase {
    // MARK: - Configuration Tests

    func testConfiguration() throws {
        // When
        let config: KSCrashConfiguration = try .datadog()

        // Then
        XCTAssertTrue(config.installPath?.contains("/Library/Caches/com.datadoghq.crash-reporting/v2") ?? false)
        XCTAssertEqual(config.reportStoreConfiguration.maxReportCount, 1)
        XCTAssertEqual(config.reportStoreConfiguration.reportCleanupPolicy, .never)
    }
}
