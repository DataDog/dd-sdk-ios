/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal protocol StoragePerformancePreset {
    /// Maximum size of a single file (in bytes).
    /// Each feature (logging, tracing, ...) serializes its objects data to that file for later upload.
    /// If last written file is too big to append next data, new file is created.
    var maxFileSize: UInt32 { get }
    /// Maximum size of data directory (in bytes).
    /// Each feature uses separate directory.
    /// If this size is exceeded, the oldest files are deleted until this limit is met again.
    var maxDirectorySize: UInt32 { get }
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
    var maxObjectSize: UInt32 { get }
}

internal extension StoragePerformancePreset {
    /// The uploader window duration determines when a file is considered "ready for upload" by the uploader after the last write.
    ///
    /// This value is crucial for computing batching and upload metrics within the SDK (see RUMM-3459). The uploader window is derived from the
    /// original `batchSize` value, which is either configured by the user or set as an internal override. The `batchSize` represents the age of
    /// "batch maturity" for uploads and is specified in seconds.
    ///
    /// The uploader window is calculated as the average of two key parameters: `minFileAgeForRead` and `maxFileAgeForWrite`. Batches younger
    /// than `maxFileAgeForWrite` are considered "writable" (available for the writer), while batches older than `minFileAgeForRead` are
    /// meant to be "readable" (available for the uploader). To ensure that the writer and uploader don't access the same batch simultaneously,
    /// a safe-guard window (10% of `batchSize`) is implemented within which the batch is neither writable nor readable.
    var uploaderWindow: TimeInterval { (minFileAgeForRead + maxFileAgeForWrite) * 0.5 }
}

internal struct PerformancePreset: Equatable, StoragePerformancePreset, UploadPerformancePreset {
    // MARK: - StoragePerformancePreset

    let maxFileSize: UInt32
    let maxDirectorySize: UInt32
    let maxFileAgeForWrite: TimeInterval
    let minFileAgeForRead: TimeInterval
    let maxFileAgeForRead: TimeInterval
    let maxObjectsInFile: Int
    let maxObjectSize: UInt32

    // MARK: - UploadPerformancePreset

    let initialUploadDelay: TimeInterval
    let minUploadDelay: TimeInterval
    let maxUploadDelay: TimeInterval
    let uploadDelayChangeRate: Double
    let maxBatchesPerUpload: Int
    let constrainedNetworkAccessEnabled: Bool
}

internal extension PerformancePreset {
    init(
        batchSize: Datadog.Configuration.BatchSize,
        uploadFrequency: Datadog.Configuration.UploadFrequency,
        bundleType: BundleType,
        batchProcessingLevel: Datadog.Configuration.BatchProcessingLevel,
        constrainedNetworkAccessEnabled: Bool = true
    ) {
        let meanFileAgeInSeconds: TimeInterval = {
            switch (bundleType, batchSize) {
            case (.iOSApp, .small): return 3
            case (.iOSApp, .medium): return 10
            case (.iOSApp, .large): return 35
            case (.iOSAppExtension, _): return 1
            }
        }()

        let minUploadDelayInSeconds: TimeInterval = {
            switch (bundleType, uploadFrequency) {
            case (.iOSApp, .frequent): return 0.5
            case (.iOSApp, .average): return 2
            case (.iOSApp, .rare): return 5
            case (.iOSAppExtension, _): return 0.5
            }
        }()

        let uploadDelayFactors: (initial: Double, min: Double, max: Double, changeRate: Double) = {
            switch bundleType {
            case .iOSApp:
                return (
                    initial: 5,
                    min: 1,
                    max: 10,
                    changeRate: 0.1
                )
            case .iOSAppExtension:
                return (
                    initial: 0.5, // ensures the the first upload is checked quickly after starting the short-lived app extension
                    min: 1,
                    max: 5,
                    changeRate: 0.5 // if batches are found, reduces interval significantly for more uploads in short-lived app extension
                )
            }
        }()

        self.init(
            meanFileAge: meanFileAgeInSeconds,
            minUploadDelay: minUploadDelayInSeconds,
            uploadDelayFactors: uploadDelayFactors,
            maxBatchesPerUpload: batchProcessingLevel.maxBatchesPerUpload,
            constrainedNetworkAccessEnabled: constrainedNetworkAccessEnabled
        )
    }

    init(
        meanFileAge: TimeInterval,
        minUploadDelay: TimeInterval,
        uploadDelayFactors: (initial: Double, min: Double, max: Double, changeRate: Double),
        maxBatchesPerUpload: Int,
        constrainedNetworkAccessEnabled: Bool
    ) {
        self.maxFileSize = 4.MB.asUInt32()
        self.maxDirectorySize = 512.MB.asUInt32()
        self.maxFileAgeForWrite = meanFileAge * 0.95 // 5% below the mean age
        self.minFileAgeForRead = meanFileAge * 1.05 //  5% above the mean age
        self.maxFileAgeForRead = 18.hours
        self.maxObjectsInFile = 500
        self.maxObjectSize = 512.KB.asUInt32()
        self.initialUploadDelay = minUploadDelay * uploadDelayFactors.initial
        self.minUploadDelay = minUploadDelay * uploadDelayFactors.min
        self.maxUploadDelay = minUploadDelay * uploadDelayFactors.max
        self.uploadDelayChangeRate = uploadDelayFactors.changeRate
        self.maxBatchesPerUpload = maxBatchesPerUpload
        self.constrainedNetworkAccessEnabled = constrainedNetworkAccessEnabled
    }

    func updated(with override: PerformancePresetOverride) -> PerformancePreset {
        return PerformancePreset(
            maxFileSize: override.maxFileSize ?? maxFileSize,
            maxDirectorySize: maxDirectorySize,
            maxFileAgeForWrite: override.maxFileAgeForWrite ?? maxFileAgeForWrite,
            minFileAgeForRead: override.minFileAgeForRead ?? minFileAgeForRead,
            maxFileAgeForRead: override.maxFileAgeForRead ?? maxFileAgeForRead,
            maxObjectsInFile: maxObjectsInFile,
            maxObjectSize: override.maxObjectSize ?? maxObjectSize,
            initialUploadDelay: override.initialUploadDelay ?? initialUploadDelay,
            minUploadDelay: override.minUploadDelay ?? minUploadDelay,
            maxUploadDelay: override.maxUploadDelay ?? maxUploadDelay,
            uploadDelayChangeRate: override.uploadDelayChangeRate ?? uploadDelayChangeRate,
            maxBatchesPerUpload: maxBatchesPerUpload,
            constrainedNetworkAccessEnabled: override.constrainedNetworkAccessEnabled ?? constrainedNetworkAccessEnabled
        )
    }
}
