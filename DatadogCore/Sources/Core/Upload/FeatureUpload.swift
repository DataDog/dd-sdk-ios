/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal struct FeatureUpload {
    /// Uploads data to server.
    let uploader: DataUploadWorkerType

    init(
        featureName: String,
        contextProvider: DatadogContextProvider,
        fileReader: Reader,
        requestBuilder: FeatureRequestBuilder,
        httpClient: HTTPClient,
        performance: PerformancePreset,
        backgroundTasksEnabled: Bool,
        isRunFromExtension: Bool,
        telemetry: Telemetry,
        batchBlockedMetricAggregator: BatchBlockedMetricAggregator? = nil
    ) {
        let uploadQueue = DispatchQueue(
            label: "com.datadoghq.ios-sdk-\(featureName)-upload",
            autoreleaseFrequency: .workItem,
            target: .global(qos: .utility)
        )

        let dataUploader = DataUploader(
            httpClient: httpClient,
            requestBuilder: requestBuilder,
            featureName: featureName
        )

        #if canImport(UIKit)
        let backgroundTaskCoordinator: BackgroundTaskCoordinator?
        switch (backgroundTasksEnabled, isRunFromExtension) {
        case (true, false):
            #if os(watchOS)
            backgroundTaskCoordinator = ExtensionBackgroundTaskCoordinator()
            #else
            backgroundTaskCoordinator = AppBackgroundTaskCoordinator()
            #endif
        case (true, true):
            backgroundTaskCoordinator = ExtensionBackgroundTaskCoordinator()
        case (false, _):
            backgroundTaskCoordinator = nil
        }
        #else
        let backgroundTaskCoordinator: BackgroundTaskCoordinator? = nil
        #endif

        self.init(
            uploader: DataUploadWorker(
                queue: uploadQueue,
                fileReader: fileReader,
                dataUploader: dataUploader,
                contextProvider: contextProvider,
                uploadConditions: DataUploadConditions(),
                delay: DataUploadDelay(performance: performance),
                featureName: featureName,
                telemetry: telemetry,
                maxBatchesPerUpload: performance.maxBatchesPerUpload,
                backgroundTaskCoordinator: backgroundTaskCoordinator,
                batchBlockedMetricAggregator: batchBlockedMetricAggregator
            )
        )
    }

    init(uploader: DataUploadWorkerType) {
        self.uploader = uploader
    }

    /// Flushes all authorised data and tears down the upload stack.
    /// - It completes all pending asynchronous work in upload worker and cancels its next schedules.
    /// - It flushes all data stored in authorized files by performing their arbitrary upload (without retrying).
    ///
    /// This method is executed synchronously. After return, the upload feature has no more
    /// pending asynchronous operations and all its authorized data should be considered uploaded.
    internal func flushAndTearDown() {
        uploader.cancelSynchronously()
        uploader.flushSynchronously()
    }
}
