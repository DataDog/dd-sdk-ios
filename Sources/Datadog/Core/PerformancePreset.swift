/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

internal struct PerformancePreset: Equatable {
    // MARK: - Data persistence

    /// Maximum size of batched logs in single file (in bytes).
    /// If last written file is too big to append next log data, new file is created.
    let maxBatchSize: UInt64
    /// Maximum size of the log files directory.
    /// If this size is exceeded, log files are being deleted (starting from the oldest one) until this limit is met again.
    let maxSizeOfLogsDirectory: UInt64
    /// Maximum age of logs file for file reuse (in seconds).
    /// If last written file is older than this, new file is created to store next log data.
    let maxFileAgeForWrite: TimeInterval
    /// Minimum age of logs file to be picked for upload (in seconds).
    /// It has the arbitrary offset (0.5s) over `maxFileAgeForWrite` to ensure that no upload is started for the file being written.
    let minFileAgeForRead: TimeInterval
    /// Maximum age of logs file to be picked for uload (in seconds).
    /// Files older than this age are considered outdated and get deleted with no upload.
    let maxFileAgeForRead: TimeInterval
    /// Maximum number of logs written to single file.
    /// If number of logs in last written file reaches this limit, new file is created to store next log data.
    let maxLogsPerBatch: Int
    /// Maximum size of serialized log data (in bytes).
    /// If JSON encoded `Log` exceeds this size, it is dropped (not written to file).
    let maxLogSize: UInt64

    // MARK: - Data upload

    /// Initial delay of the first batch upload (in seconds).
    /// It is used as a base value until SDK finds no more log batches - then `defaultLogsUploadDelay` is used as a new base.
    let initialLogsUploadDelay: TimeInterval
    /// Default time interval for logs upload (in seconds).
    /// At runtime, the upload interval ranges from `minLogsUploadDelay` to `maxLogsUploadDelay` depending
    /// on logs delivery success / failure.
    let defaultLogsUploadDelay: TimeInterval
    /// Mininum time interval for logs upload (in seconds).
    /// By default logs are uploaded with `defaultLogsUploadDelay` which might change depending
    /// on logs delivery success / failure.
    let minLogsUploadDelay: TimeInterval
    /// Maximum time interval for logs upload (in seconds).
    /// By default logs are uploaded with `defaultLogsUploadDelay` which might change depending
    /// on logs delivery success / failure.
    let maxLogsUploadDelay: TimeInterval
    /// Change factor of logs upload interval due to upload success.
    let logsUploadDelayDecreaseFactor: Double

    // MARK: - Performance presets

    /// Default performance preset.
    static let `default` = lowRuntimeImpact

    /// Performance preset optimized for low runtime impact.
    /// Minimalizes number of data requests send to the server.
    static let lowRuntimeImpact = PerformancePreset(
        // persistence
        maxBatchSize: 4 * 1_024 * 1_024, // 4MB
        maxSizeOfLogsDirectory: 512 * 1_024 * 1_024, // 512 MB
        maxFileAgeForWrite: 4.75,
        minFileAgeForRead: 4.75 + 0.5, // `maxFileAgeForWrite` + 0.5s margin
        maxFileAgeForRead: 18 * 60 * 60, // 18h
        maxLogsPerBatch: 500,
        maxLogSize: 256 * 1_024, // 256KB

        // upload
        initialLogsUploadDelay: 5, // postpone to not impact app launch time
        defaultLogsUploadDelay: 5,
        minLogsUploadDelay: 1,
        maxLogsUploadDelay: 20,
        logsUploadDelayDecreaseFactor: 0.9
    )

    /// Performance preset optimized for instant data delivery.
    /// Minimalizes the time between receiving data form the user and delivering it to the server.
    static let instantDataDelivery = PerformancePreset(
        // persistence
        maxBatchSize: `default`.maxBatchSize,
        maxSizeOfLogsDirectory: `default`.maxSizeOfLogsDirectory,
        maxFileAgeForWrite: 2.75,
        minFileAgeForRead: 2.75 + 0.5, // `maxFileAgeForWrite` + 0.5s margin
        maxFileAgeForRead: `default`.maxFileAgeForRead,
        maxLogsPerBatch: `default`.maxLogsPerBatch,
        maxLogSize: `default`.maxLogSize,

        // upload
        initialLogsUploadDelay: 0.5, // send quick to have a chance for upload in short-lived extensions
        defaultLogsUploadDelay: 3,
        minLogsUploadDelay: 1,
        maxLogsUploadDelay: 5,
        logsUploadDelayDecreaseFactor: 0.5 // reduce significantly for more uploads in short-lived extensions
    )

    static func best(for bundleType: BundleType) -> PerformancePreset {
        switch bundleType {
        case .iOSApp: return `default`
        case .iOSAppExtension: return instantDataDelivery
        }
    }
}
