/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

internal protocol StoragePerformancePreset {
    /// Maximum size of a single file (in bytes).
    /// Each feature (logging, tracing, ...) serializes its objects data to that file for later upload.
    /// If last written file is too big to append next data, new file is created.
    var maxFileSize: UInt64 { get }
    /// Maximum size of data directory (in bytes).
    /// Each feature uses separate directory.
    /// If this size is exceeded, the oldest files are deleted until this limit is met again.
    var maxDirectorySize: UInt64 { get }
    /// Maximum age qualifying given file for reuse (in seconds).
    /// If recently used file is younger than this, it is reused - otherwise: new file is created.
    var maxFileAgeForWrite: TimeInterval { get }
    /// Minimum age qualifying given file for upload (in seconds).
    /// If the file is older than this, it is uploaded (and then deleted if upload succeeded).
    /// It has an arbitrary offset  (~0.5s) over `maxFileAgeForWrite` to ensure that no upload can start for the file being currently written.
    var minFileAgeForRead: TimeInterval { get }
    /// Maximum age qualifying given file for upload (in seconds).
    /// Files older than this are considered obsolete and get deleted without uploading.
    var maxFileAgeForRead: TimeInterval { get }
    /// Maximum number of serialized objects written to a single file.
    /// If number of objects in recently used file reaches this limit, new file is created for new data.
    var maxObjectsInFile: Int { get }
    /// Maximum size of serialized object data (in bytes).
    /// If serialized object data exceeds this limit, it is skipped (not written to file and not uploaded).
    var maxObjectSize: UInt64 { get }
}

internal struct PerformancePreset: Equatable, StoragePerformancePreset, UploadPerformancePreset {
    // MARK: - StoragePerformancePreset

    let maxFileSize: UInt64
    let maxDirectorySize: UInt64
    let maxFileAgeForWrite: TimeInterval
    let minFileAgeForRead: TimeInterval
    let maxFileAgeForRead: TimeInterval
    let maxObjectsInFile: Int
    let maxObjectSize: UInt64

    // MARK: - UploadPerformancePreset

    let initialUploadDelay: TimeInterval
    let minUploadDelay: TimeInterval
    let maxUploadDelay: TimeInterval
    let uploadDelayChangeRate: Double
}

internal extension PerformancePreset {
    init(
        batchSize: Datadog.Configuration.BatchSize,
        uploadFrequency: Datadog.Configuration.UploadFrequency,
        bundleType: BundleType
    ) {
        let meanFileAgeInSeconds: TimeInterval = {
            switch (bundleType, batchSize) {
            case (.iOSApp, .small): return 5
            case (.iOSApp, .medium): return 15
            case (.iOSApp, .large): return 60
            case (.iOSAppExtension, .small): return 1
            case (.iOSAppExtension, .medium): return 3
            case (.iOSAppExtension, .large): return 12
            }
        }()

        let minUploadDelayInSeconds: TimeInterval = {
            switch (bundleType, uploadFrequency) {
            case (.iOSApp, .frequent): return 1
            case (.iOSApp, .average): return 5
            case (.iOSApp, .rare): return 10
            case (.iOSAppExtension, .frequent): return 0.5
            case (.iOSAppExtension, .average): return 1
            case (.iOSAppExtension, .rare): return 5
            }
        }()

        let uploadDelayFactors: (initial: Double, default: Double, min: Double, max: Double, changeRate: Double) = {
            switch bundleType {
            case .iOSApp:
                return (
                    initial: 5,
                    default: 5,
                    min: 1,
                    max: 10,
                    changeRate: 0.1
                )
            case .iOSAppExtension:
                return (
                    initial: 0.5, // ensures the the first upload is checked quickly after starting the short-lived app extension
                    default: 3,
                    min: 1,
                    max: 5,
                    changeRate: 0.5 // if batches are found, reduces interval significantly for more uploads in short-lived app extension
                )
            }
        }()

        self.init(
            meanFileAge: meanFileAgeInSeconds,
            minUploadDelay: minUploadDelayInSeconds,
            uploadDelayFactors: uploadDelayFactors
        )
    }

    init(
        meanFileAge: TimeInterval,
        minUploadDelay: TimeInterval,
        uploadDelayFactors: (initial: Double, default: Double, min: Double, max: Double, changeRate: Double)
    ) {
        self.maxFileSize = 4 * 1_024 * 1_024 // 4MB
        self.maxDirectorySize = 512 * 1_024 * 1_024 // 512 MB
        self.maxFileAgeForWrite = meanFileAge * 0.95 // 5% below the mean age
        self.minFileAgeForRead = meanFileAge * 1.05 //  5% above the mean age
        self.maxFileAgeForRead = 18 * 60 * 60 // 18h
        self.maxObjectsInFile = 500
        self.maxObjectSize = 512 * 1_024 // 512KB
        self.initialUploadDelay = minUploadDelay * uploadDelayFactors.initial
        self.minUploadDelay = minUploadDelay * uploadDelayFactors.min
        self.maxUploadDelay = minUploadDelay * uploadDelayFactors.max
        self.uploadDelayChangeRate = uploadDelayFactors.changeRate
    }
}
