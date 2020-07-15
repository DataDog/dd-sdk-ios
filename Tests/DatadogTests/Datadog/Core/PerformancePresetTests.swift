/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class PerformancePresetTests: XCTestCase {
    func testDefaultPreset() {
        XCTAssertEqual(PerformancePreset.default, .lowRuntimeImpact)
    }

    func testBestPresetsForEnvironment() {
        XCTAssertEqual(PerformancePreset.best(for: .iOSApp), PerformancePreset.lowRuntimeImpact)
        XCTAssertEqual(PerformancePreset.best(for: .iOSAppExtension), PerformancePreset.instantDataDelivery)
    }

    func testPresetsConsistency() {
        let presets: [PerformancePreset] = [.lowRuntimeImpact, .instantDataDelivery]

        presets.forEach { preset in
            XCTAssertLessThan(
                preset.maxFileSize,
                preset.maxDirectorySize,
                "Size of individual file must not exceed the directory size limit."
            )
            XCTAssertLessThan(
                preset.maxFileAgeForWrite,
                preset.minFileAgeForRead,
                "File should not be considered for upload (read) while it is eligible for writes."
            )
            XCTAssertGreaterThan(
                preset.maxFileAgeForRead,
                preset.minFileAgeForRead,
                "File read boundaries must be consistent."
            )
            XCTAssertGreaterThan(
                preset.maxUploadDelay,
                preset.minUploadDelay,
                "Upload delay boundaries must be consistent."
            )
            XCTAssertGreaterThan(
                preset.maxUploadDelay,
                preset.minUploadDelay,
                "Upload delay boundaries must be consistent."
            )
            XCTAssertLessThanOrEqual(
                preset.uploadDelayDecreaseFactor,
                1,
                "Upload delay should not be increased towards infinity."
            )
            XCTAssertGreaterThan(
                preset.uploadDelayDecreaseFactor,
                0,
                "Upload delay must never result with 0."
            )
        }
    }
}
