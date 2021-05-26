/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

@testable import Datadog

extension InternalMonitoringFeature {
    /// Mocks the feature instance which performs uploads to `URLSession`.
    /// Use `ServerMock` to inspect and assert recorded `URLRequests`.
    static func mockWith(
        logDirectories: FeatureDirectories,
        configuration: FeaturesConfiguration.InternalMonitoring = .mockAny(),
        dependencies: FeaturesCommonDependencies = .mockAny()
    ) -> InternalMonitoringFeature {
        return InternalMonitoringFeature(
            logDirectories: logDirectories,
            configuration: configuration,
            commonDependencies: dependencies
        )
    }

    /// Mocks the feature instance which performs uploads to mocked `DataUploadWorker`.
    /// Use `InternalMonitoringFeature.waitAndReturnLogMatchers()` to inspect and assert recorded `Logs`.
    static func mockByRecordingLogMatchers(
        directories: FeatureDirectories,
        configuration: FeaturesConfiguration.InternalMonitoring = .mockAny(),
        dependencies: FeaturesCommonDependencies = .mockAny()
    ) -> InternalMonitoringFeature {
        // Create full feature:
        let fullFeature = InternalMonitoringFeature(
            logDirectories: directories,
            configuration: configuration,
            commonDependencies: dependencies.replacing(
                dateProvider: SystemDateProvider() // replace date provider in mocked `Feature.Storage`
            )
        )
        fullFeature.deinitialize()
        let uploadWorker = DataUploadWorkerMock()
        let observedStorage = uploadWorker.observe(featureStorage: fullFeature.logsStorage)
        // Replace by mocking the `FeatureUpload` and observing the `FatureStorage`:
        let mockedUpload = FeatureUpload(uploader: uploadWorker)
        return InternalMonitoringFeature(
            storage: observedStorage,
            upload: mockedUpload,
            configuration: configuration,
            commonDependencies: dependencies
        )
    }

    // MARK: - Expecting Logs Data

    static func waitAndReturnLogMatchers(count: UInt, file: StaticString = #file, line: UInt = #line) throws -> [LogMatcher] {
        guard let uploadWorker = InternalMonitoringFeature.instance?.logsUpload.uploader as? DataUploadWorkerMock else {
            preconditionFailure("Retrieving matchers requires that feature is mocked with `.mockByRecordingLogMatchers()`")
        }
        return try uploadWorker.waitAndReturnBatchedData(count: count, file: file, line: line)
            .flatMap { batchData in try LogMatcher.fromArrayOfJSONObjectsData(batchData, file: file, line: line) }
    }
}
