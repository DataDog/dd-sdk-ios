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
        let smallBatchAnyFrequency = PerformancePreset(batchSize: .small, uploadFrequency: .mockRandom())
        XCTAssertEqual(smallBatchAnyFrequency.maxFileAgeForWrite, 2.85, accuracy: 0.01)
        XCTAssertEqual(smallBatchAnyFrequency.minFileAgeForRead, 3.15, accuracy: 0.01)
        XCTAssertEqual(smallBatchAnyFrequency.uploaderWindow, 3.0)
        assertPresetCommonValues(in: smallBatchAnyFrequency)

        let mediumBatchAnyFrequency = PerformancePreset(batchSize: .medium, uploadFrequency: .mockRandom())
        XCTAssertEqual(mediumBatchAnyFrequency.maxFileAgeForWrite, 9.5)
        XCTAssertEqual(mediumBatchAnyFrequency.minFileAgeForRead, 10.5)
        XCTAssertEqual(mediumBatchAnyFrequency.uploaderWindow, 10.0)
        assertPresetCommonValues(in: mediumBatchAnyFrequency)

        let largeBatchAnyFrequency = PerformancePreset(batchSize: .large, uploadFrequency: .mockRandom())
        XCTAssertEqual(largeBatchAnyFrequency.maxFileAgeForWrite, 33.25)
        XCTAssertEqual(largeBatchAnyFrequency.minFileAgeForRead, 36.75)
        XCTAssertEqual(largeBatchAnyFrequency.uploaderWindow, 35)
        assertPresetCommonValues(in: largeBatchAnyFrequency)

        let frequentUploadAnyBatch = PerformancePreset(batchSize: .mockRandom(), uploadFrequency: .frequent)
        XCTAssertEqual(frequentUploadAnyBatch.initialUploadDelay, 2.5)
        XCTAssertEqual(frequentUploadAnyBatch.minUploadDelay, 0.5)
        XCTAssertEqual(frequentUploadAnyBatch.maxUploadDelay, 5.0)
        XCTAssertEqual(frequentUploadAnyBatch.uploadDelayChangeRate, 0.1)
        assertPresetCommonValues(in: frequentUploadAnyBatch)

        let averageUploadAnyBatch = PerformancePreset(batchSize: .mockRandom(), uploadFrequency: .average)
        XCTAssertEqual(averageUploadAnyBatch.initialUploadDelay, 10.0)
        XCTAssertEqual(averageUploadAnyBatch.minUploadDelay, 2.0)
        XCTAssertEqual(averageUploadAnyBatch.maxUploadDelay, 20.0)
        XCTAssertEqual(averageUploadAnyBatch.uploadDelayChangeRate, 0.1)
        assertPresetCommonValues(in: averageUploadAnyBatch)

        let rareUploadAnyBatch = PerformancePreset(batchSize: .mockRandom(), uploadFrequency: .rare)
        XCTAssertEqual(rareUploadAnyBatch.initialUploadDelay, 25.0)
        XCTAssertEqual(rareUploadAnyBatch.minUploadDelay, 5.0)
        XCTAssertEqual(rareUploadAnyBatch.maxUploadDelay, 50.0)
        XCTAssertEqual(rareUploadAnyBatch.uploadDelayChangeRate, 0.1)
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
            .map { PerformancePreset(batchSize: $0.0, uploadFrequency: $0.1) }

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
        let preset = PerformancePreset(batchSize: .mockRandom(), uploadFrequency: .mockRandom())
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
