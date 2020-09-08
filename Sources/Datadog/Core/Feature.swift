/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Container with dependencies common to all features (Logging, Tracing and RUM).
internal struct FeaturesCommonDependencies {
    let performance: PerformancePreset
    let httpClient: HTTPClient
    let mobileDevice: MobileDevice
    let dateProvider: DateProvider
    let userInfoProvider: UserInfoProvider
    let networkConnectionInfoProvider: NetworkConnectionInfoProviderType
    let carrierInfoProvider: CarrierInfoProviderType
}

internal struct FeatureStorage {
    /// Writes data to files.
    let writer: FileWriterType
    /// Reads data from files.
    let reader: FileReaderType

    init(
        featureName: String,
        dataFormat: DataFormat,
        directory: Directory,
        commonDependencies: FeaturesCommonDependencies
    ) {
        let readWriteQueue = DispatchQueue(
            label: "com.datadoghq.ios-sdk-\(featureName)-read-write",
            target: .global(qos: .utility)
        )
        let orchestrator = FilesOrchestrator(
            directory: directory,
            performance: commonDependencies.performance,
            dateProvider: commonDependencies.dateProvider
        )

        self.init(
            writer: FileWriter(dataFormat: dataFormat, orchestrator: orchestrator, queue: readWriteQueue),
            reader: FileReader(dataFormat: dataFormat, orchestrator: orchestrator, queue: readWriteQueue)
        )
    }

    init(writer: FileWriterType, reader: FileReaderType) {
        self.writer = writer
        self.reader = reader
    }
}

internal struct FeatureUpload {
    /// Uploads data to server.
    let uploader: DataUploadWorkerType

    init(
        featureName: String,
        storage: FeatureStorage,
        uploadHTTPHeaders: HTTPHeaders,
        uploadURLProvider: UploadURLProvider,
        commonDependencies: FeaturesCommonDependencies
    ) {
        let uploadQueue = DispatchQueue(
            label: "com.datadoghq.ios-sdk-\(featureName)-upload",
            target: .global(qos: .utility)
        )

        let uploadConditions = DataUploadConditions(
            batteryStatus: BatteryStatusProvider(mobileDevice: commonDependencies.mobileDevice),
            networkConnectionInfo: commonDependencies.networkConnectionInfoProvider
        )

        let dataUploader = DataUploader(
            urlProvider: uploadURLProvider,
            httpClient: commonDependencies.httpClient,
            httpHeaders: uploadHTTPHeaders
        )

        self.init(
            uploader: DataUploadWorker(
                queue: uploadQueue,
                fileReader: storage.reader,
                dataUploader: dataUploader,
                uploadConditions: uploadConditions,
                delay: DataUploadDelay(performance: commonDependencies.performance),
                featureName: featureName
            )
        )
    }

    init(uploader: DataUploadWorkerType) {
        self.uploader = uploader
    }
}
