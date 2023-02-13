/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
@testable import Datadog

class PerformancePresetTests: XCTestCase {
    func testIOSAppPresets() {
        let smallBatchAnyFrequency = PerformancePreset(batchSize: .small, uploadFrequency: .mockRandom(), bundleType: .iOSApp)
        XCTAssertEqual(smallBatchAnyFrequency.maxFileAgeForWrite, 4.75)
        XCTAssertEqual(smallBatchAnyFrequency.minFileAgeForRead, 5.25)
        assertPresetCommonValues(in: smallBatchAnyFrequency)

        let mediumBatchAnyFrequency = PerformancePreset(batchSize: .medium, uploadFrequency: .mockRandom(), bundleType: .iOSApp)
        XCTAssertEqual(mediumBatchAnyFrequency.maxFileAgeForWrite, 14.25)
        XCTAssertEqual(mediumBatchAnyFrequency.minFileAgeForRead, 15.75)
        assertPresetCommonValues(in: mediumBatchAnyFrequency)

        let largeBatchAnyFrequency = PerformancePreset(batchSize: .large, uploadFrequency: .mockRandom(), bundleType: .iOSApp)
        XCTAssertEqual(largeBatchAnyFrequency.maxFileAgeForWrite, 57.0)
        XCTAssertEqual(largeBatchAnyFrequency.minFileAgeForRead, 63.0)
        assertPresetCommonValues(in: largeBatchAnyFrequency)

        let frequentUploadAnyBatch = PerformancePreset(batchSize: .mockRandom(), uploadFrequency: .frequent, bundleType: .iOSApp)
        XCTAssertEqual(frequentUploadAnyBatch.initialUploadDelay, 5.0)
        XCTAssertEqual(frequentUploadAnyBatch.minUploadDelay, 1.0)
        XCTAssertEqual(frequentUploadAnyBatch.maxUploadDelay, 10.0)
        XCTAssertEqual(frequentUploadAnyBatch.uploadDelayChangeRate, 0.1)
        assertPresetCommonValues(in: frequentUploadAnyBatch)

        let averageUploadAnyBatch = PerformancePreset(batchSize: .mockRandom(), uploadFrequency: .average, bundleType: .iOSApp)
        XCTAssertEqual(averageUploadAnyBatch.initialUploadDelay, 25.0)
        XCTAssertEqual(averageUploadAnyBatch.minUploadDelay, 5.0)
        XCTAssertEqual(averageUploadAnyBatch.maxUploadDelay, 50.0)
        XCTAssertEqual(averageUploadAnyBatch.uploadDelayChangeRate, 0.1)
        assertPresetCommonValues(in: averageUploadAnyBatch)

        let rareUploadAnyBatch = PerformancePreset(batchSize: .mockRandom(), uploadFrequency: .rare, bundleType: .iOSApp)
        XCTAssertEqual(rareUploadAnyBatch.initialUploadDelay, 50.0)
        XCTAssertEqual(rareUploadAnyBatch.minUploadDelay, 10.0)
        XCTAssertEqual(rareUploadAnyBatch.maxUploadDelay, 100.0)
        XCTAssertEqual(rareUploadAnyBatch.uploadDelayChangeRate, 0.1)
        assertPresetCommonValues(in: rareUploadAnyBatch)
    }

    func testIOSAppExtensionPresets() {
        let smallBatchAnyFrequency = PerformancePreset(batchSize: .small, uploadFrequency: .mockRandom(), bundleType: .iOSAppExtension)
        XCTAssertEqual(smallBatchAnyFrequency.maxFileAgeForWrite, 0.95)
        XCTAssertEqual(smallBatchAnyFrequency.minFileAgeForRead, 1.05)
        assertPresetCommonValues(in: smallBatchAnyFrequency)

        let mediumBatchAnyFrequency = PerformancePreset(batchSize: .medium, uploadFrequency: .mockRandom(), bundleType: .iOSAppExtension)
        XCTAssertEqual(mediumBatchAnyFrequency.maxFileAgeForWrite, 2.85, accuracy: 0.01)
        XCTAssertEqual(mediumBatchAnyFrequency.minFileAgeForRead, 3.15, accuracy: 0.01)
        assertPresetCommonValues(in: mediumBatchAnyFrequency)

        let largeBatchAnyFrequency = PerformancePreset(batchSize: .large, uploadFrequency: .mockRandom(), bundleType: .iOSAppExtension)
        XCTAssertEqual(largeBatchAnyFrequency.maxFileAgeForWrite, 11.4, accuracy: 0.01)
        XCTAssertEqual(largeBatchAnyFrequency.minFileAgeForRead, 12.6, accuracy: 0.01)
        assertPresetCommonValues(in: largeBatchAnyFrequency)

        let frequentUploadAnyBatch = PerformancePreset(batchSize: .mockRandom(), uploadFrequency: .frequent, bundleType: .iOSAppExtension)
        XCTAssertEqual(frequentUploadAnyBatch.initialUploadDelay, 0.25)
        XCTAssertEqual(frequentUploadAnyBatch.minUploadDelay, 0.5)
        XCTAssertEqual(frequentUploadAnyBatch.maxUploadDelay, 2.5)
        XCTAssertEqual(frequentUploadAnyBatch.uploadDelayChangeRate, 0.5)
        assertPresetCommonValues(in: frequentUploadAnyBatch)

        let averageUploadAnyBatch = PerformancePreset(batchSize: .mockRandom(), uploadFrequency: .average, bundleType: .iOSAppExtension)
        XCTAssertEqual(averageUploadAnyBatch.initialUploadDelay, 0.5)
        XCTAssertEqual(averageUploadAnyBatch.minUploadDelay, 1.0)
        XCTAssertEqual(averageUploadAnyBatch.maxUploadDelay, 5.0)
        XCTAssertEqual(averageUploadAnyBatch.uploadDelayChangeRate, 0.5)
        assertPresetCommonValues(in: averageUploadAnyBatch)

        let rareUploadAnyBatch = PerformancePreset(batchSize: .mockRandom(), uploadFrequency: .rare, bundleType: .iOSAppExtension)
        XCTAssertEqual(rareUploadAnyBatch.initialUploadDelay, 2.5)
        XCTAssertEqual(rareUploadAnyBatch.minUploadDelay, 5.0)
        XCTAssertEqual(rareUploadAnyBatch.maxUploadDelay, 25.0)
        XCTAssertEqual(rareUploadAnyBatch.uploadDelayChangeRate, 0.5)
        assertPresetCommonValues(in: rareUploadAnyBatch)
    }

    private func assertPresetCommonValues(in preset: PerformancePreset) {
        XCTAssertEqual(preset.maxFileSize, 4 * 1_024 * 1_024) // 4MB
        XCTAssertEqual(preset.maxDirectorySize, 512 * 1_024 * 1_024) // 512 MB
        XCTAssertEqual(preset.maxFileAgeForRead, 18 * 60 * 60) // 18h
        XCTAssertEqual(preset.maxObjectsInFile, 500)
        XCTAssertEqual(preset.maxObjectSize, 512 * 1_024) // 512KB
    }

    func testPresetsConsistency() {
        let allPossiblePresets: [PerformancePreset] = BatchSize.allCases
            .combined(with: UploadFrequency.allCases)
            .combined(with: BundleType.allCases)
            .map { PerformancePreset(batchSize: $0.0, uploadFrequency: $0.1, bundleType: $1) }

        allPossiblePresets.forEach { preset in
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
                preset.uploadDelayChangeRate,
                1,
                "Upload delay should not change by more than 100% at once."
            )
            XCTAssertGreaterThan(
                preset.uploadDelayChangeRate,
                0,
                "Upload delay must change at non-zero rate."
            )
        }
    }
}
