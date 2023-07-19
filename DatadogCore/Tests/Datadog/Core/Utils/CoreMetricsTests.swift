/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogCore

class CoreMetricsTests: XCTestCase {
    func testBatchRemovalReasonFormatting() {
        typealias RemovalReason = BatchDeletedMetric.RemovalReason

        XCTAssertEqual(RemovalReason.intakeCode(responseCode: 202).asString, "intake-code-202")
        XCTAssertEqual(RemovalReason.obsolete.asString, "obsolete")
        XCTAssertEqual(RemovalReason.purged.asString, "purged")
        XCTAssertEqual(RemovalReason.invalid.asString, "invalid")
        XCTAssertEqual(RemovalReason.flushed.asString, "flushed")
    }

    func testOnlyCertainBatchRemovalReasonsAreIncludedInMetric() {
        typealias RemovalReason = BatchDeletedMetric.RemovalReason

        XCTAssertTrue(RemovalReason.intakeCode(responseCode: 202).includeInMetric)
        XCTAssertTrue(RemovalReason.obsolete.includeInMetric)
        XCTAssertTrue(RemovalReason.purged.includeInMetric)
        XCTAssertTrue(RemovalReason.invalid.includeInMetric)
        XCTAssertFalse(RemovalReason.flushed.includeInMetric)
    }
}
