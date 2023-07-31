/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal
@testable import DatadogCore

class PerformancePresetTests: XCTestCase {
    func testIOSAppPresets() {
        let smallBatchAnyFrequency = PerformancePreset(batchSize: .small, uploadFrequency: .mockRandom(), bundleType: .iOSApp)
        XCTAssertEqual(smallBatchAnyFrequency.maxFileAgeForWrite, 4.75)
        XCTAssertEqual(smallBatchAnyFrequency.minFileAgeForRead, 5.25)
        XCTAssertEqual(smallBatchAnyFrequency.uploaderWindow, 5)
        assertPresetCommonValues(in: smallBatchAnyFrequency)

        let mediumBatchAnyFrequency = PerformancePreset(batchSize: .medium, uploadFrequency: .mockRandom(), bundleType: .iOSApp)
        XCTAssertEqual(mediumBatchAnyFrequency.maxFileAgeForWrite, 14.25)
        XCTAssertEqual(mediumBatchAnyFrequency.minFileAgeForRead, 15.75)
        XCTAssertEqual(mediumBatchAnyFrequency.uploaderWindow, 15)
        assertPresetCommonValues(in: mediumBatchAnyFrequency)

        let largeBatchAnyFrequency = PerformancePreset(batchSize: .large, uploadFrequency: .mockRandom(), bundleType: .iOSApp)
        XCTAssertEqual(largeBatchAnyFrequency.maxFileAgeForWrite, 57.0)
        XCTAssertEqual(largeBatchAnyFrequency.minFileAgeForRead, 63.0)
        XCTAssertEqual(largeBatchAnyFrequency.uploaderWindow, 60)
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
        XCTAssertEqual(smallBatchAnyFrequency.uploaderWindow, 1)
        assertPresetCommonValues(in: smallBatchAnyFrequency)

        let mediumBatchAnyFrequency = PerformancePreset(batchSize: .medium, uploadFrequency: .mockRandom(), bundleType: .iOSAppExtension)
        XCTAssertEqual(mediumBatchAnyFrequency.maxFileAgeForWrite, 2.85, accuracy: 0.01)
        XCTAssertEqual(mediumBatchAnyFrequency.minFileAgeForRead, 3.15, accuracy: 0.01)
        XCTAssertEqual(mediumBatchAnyFrequency.uploaderWindow, 3)
        assertPresetCommonValues(in: mediumBatchAnyFrequency)

        let largeBatchAnyFrequency = PerformancePreset(batchSize: .large, uploadFrequency: .mockRandom(), bundleType: .iOSAppExtension)
        XCTAssertEqual(largeBatchAnyFrequency.maxFileAgeForWrite, 11.4, accuracy: 0.01)
        XCTAssertEqual(largeBatchAnyFrequency.minFileAgeForRead, 12.6, accuracy: 0.01)
        XCTAssertEqual(largeBatchAnyFrequency.uploaderWindow, 12)
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

    func testPresetsUpdate() {
        // Given
        let maxFileSizeOverride: UInt64 = .mockRandom()
        let maxObjectSizeOverride: UInt64 = .mockRandom()
        let meanFileAgeOverride: TimeInterval = .mockRandom(min: 1, max: 100)
        let uploadDelayOverride: (initial: TimeInterval, range: Range<TimeInterval>, changeRate: Double) = (
            initial: .mockRandom(),
            range: (TimeInterval.mockRandom(min: 1, max: 10)..<TimeInterval.mockRandom(min: 11, max: 100)),
            changeRate: .mockRandom()
        )

        // When
        let preset = PerformancePreset(batchSize: .mockRandom(), uploadFrequency: .mockRandom(), bundleType: .mockRandom())
        let updatedPreset = preset.updated(
            with: PerformancePresetOverride(
                maxFileSize: maxFileSizeOverride,
                maxObjectSize: maxObjectSizeOverride,
                meanFileAge: meanFileAgeOverride,
                uploadDelay: uploadDelayOverride
            )
        )

        // Then
        XCTAssertEqual(updatedPreset.maxFileSize, maxFileSizeOverride)
        XCTAssertEqual(updatedPreset.maxObjectSize, maxObjectSizeOverride)
        XCTAssertEqual(updatedPreset.maxFileAgeForWrite, meanFileAgeOverride * 0.95, accuracy: 0.01)
        XCTAssertEqual(updatedPreset.minFileAgeForRead, meanFileAgeOverride * 1.05, accuracy: 0.01)
        XCTAssertEqual(updatedPreset.uploaderWindow, meanFileAgeOverride, accuracy: 0.01)
        XCTAssertEqual(updatedPreset.initialUploadDelay, uploadDelayOverride.initial)
        XCTAssertEqual(updatedPreset.minUploadDelay, uploadDelayOverride.range.lowerBound)
        XCTAssertEqual(updatedPreset.maxUploadDelay, uploadDelayOverride.range.upperBound)
        XCTAssertEqual(updatedPreset.uploadDelayChangeRate, uploadDelayOverride.changeRate)
    }
}
