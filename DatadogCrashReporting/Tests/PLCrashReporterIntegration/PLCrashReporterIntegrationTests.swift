/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogCrashReporting
import CrashReporter

class PLCrashReporterIntegrationTests: XCTestCase {
    func testGivenPLCrashReporter_whenInitializingWithDDConfig_itSetsCustomPath() throws {
        // Given
        let configuration = try PLCrashReporterConfig.ddConfiguration()

        // When
        let reporter = PLCrashReporter(configuration: configuration)

        // Then
        let reporterPath = reporter?.crashReportPath()
        let expected = "/Library/Caches/com.datadoghq.crash-reporting/v1/"
        XCTAssertTrue(reporterPath?.contains(expected) ?? false)
    }
}
