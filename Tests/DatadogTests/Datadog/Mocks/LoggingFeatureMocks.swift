/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

@testable import Datadog

/// Collection of mocks for logging feature.
extension LoggingFeature {
    /// Mocks feature instance which performs no writes and no uploads.
    static func mockNoOp(temporaryDirectory: Directory) -> LoggingFeature {
        return LoggingFeature(
            directory: temporaryDirectory,
            appContext: .mockAny(),
            performance: .mockNoOp(),
            httpClient: .mockAny(),
            logsUploadURLProvider: .mockAny(),
            dateProvider: SystemDateProvider(),
            userInfoProvider: .mockAny(),
            networkConnectionInfoProvider: NetworkConnectionInfoProviderMock.mockWith(
                networkConnectionInfo: .mockWith(
                    reachability: .no // so it doesn't meet the upload condition
                )
            ),
            carrierInfoProvider: CarrierInfoProviderMock.mockAny()
        )
    }

    /// Mocks feature instance which performs uploads to given `ServerMock` with performance optimized for fast delivery in unit tests.
    static func mockWorkingFeatureWith(
        server: ServerMock,
        directory: Directory,
        appContext: AppContext = .mockWith(
            mobileDevice: nil // so it doesn't rely on battery status for the upload condition
        ),
        performance: PerformancePreset = .mockUnitTestsPerformancePreset(),
        logsUploadURLProvider: UploadURLProvider = .mockAny(),
        dateProvider: DateProvider = SystemDateProvider(),
        userInfoProvider: UserInfoProvider = .mockAny(),
        networkConnectionInfoProvider: NetworkConnectionInfoProviderType = NetworkConnectionInfoProviderMock.mockWith(
            networkConnectionInfo: .mockWith(
                reachability: .yes, // so it always meets the upload condition
                availableInterfaces: [.wifi],
                supportsIPv4: true,
                supportsIPv6: true,
                isExpensive: true,
                isConstrained: false // so it always meets the upload condition
            )
        ),
        carrierInfoProvider: CarrierInfoProviderType = CarrierInfoProviderMock.mockAny()
    ) -> LoggingFeature {
        return LoggingFeature(
            directory: directory,
            appContext: appContext,
            performance: performance,
            httpClient: HTTPClient(session: server.urlSession),
            logsUploadURLProvider: logsUploadURLProvider,
            dateProvider: dateProvider,
            userInfoProvider: userInfoProvider,
            networkConnectionInfoProvider: networkConnectionInfoProvider,
            carrierInfoProvider: carrierInfoProvider
        )
    }
}
