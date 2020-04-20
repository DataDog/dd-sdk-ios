/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

@testable import Datadog

/// Collection of mocks for logging feature.
extension LoggingFeature {
    /// Mocks feature instance which performs no writes and no uploads.
    static func mockNoOp() -> LoggingFeature {
        return LoggingFeature(
            directory: temporaryDirectory,
            appContext: .mockAny(),
            performance: .mockNoOp(),
            httpClient: .mockAny(),
            logsUploadURLProvider: .mockAny(),
            dateProvider: SystemDateProvider(),
            userInfoProvider: .mockAny(),
            networkConnectionInfoProvider: NetworkConnectionInfoProviderMock.mockAny(),
            carrierInfoProvider: CarrierInfoProviderMock.mockAny()
        )
    }

    /// Mocks feature instance which performs uploads to given `ServerMock` with performance optimized for fast delivery in unit tests.
    static func mockWorkingFeatureWith(
        directory: Directory = temporaryDirectory,
        server: ServerMock? = nil,
        appContext: AppContext = .mockAny(),
        performance: PerformancePreset = .mockUnitTestsPerformancePreset(),
        logsUploadURLProvider: UploadURLProvider = .mockAny(),
        dateProvider: DateProvider = SystemDateProvider(),
        userInfoProvider: UserInfoProvider = .mockAny(),
        networkConnectionInfoProvider: NetworkConnectionInfoProviderType = NetworkConnectionInfoProviderMock.mockAny(),
        carrierInfoProvider: CarrierInfoProviderType = CarrierInfoProviderMock.mockAny()
    ) -> LoggingFeature {
        let httpClient: HTTPClient

        if let server = server {
            httpClient = HTTPClient(session: server.urlSession)
        } else {
            httpClient = .mockAny()
        }

        return LoggingFeature(
            directory: directory,
            appContext: appContext,
            performance: performance,
            httpClient: httpClient,
            logsUploadURLProvider: logsUploadURLProvider,
            dateProvider: dateProvider,
            userInfoProvider: userInfoProvider,
            networkConnectionInfoProvider: networkConnectionInfoProvider,
            carrierInfoProvider: carrierInfoProvider
        )
    }
}
