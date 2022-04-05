/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

@testable import Datadog

private struct DateCorrectorMock: DateCorrectorType {
    var currentCorrection: DateCorrection {
        return DateCorrection(serverTimeOffset: 0)
    }
}

extension PerformancePreset {
    static let benchmarksPreset = PerformancePreset(batchSize: .small, uploadFrequency: .frequent, bundleType: .iOSApp)
}

extension FeaturesCommonDependencies {
    static func mockAny() -> Self {
        return .init(
            consentProvider: ConsentProvider(initialConsent: .granted),
            performance: .benchmarksPreset,
            httpClient: HTTPClient(),
            mobileDevice: MobileDevice(),
            sdkInitDate: Date(),
            dateProvider: SystemDateProvider(),
            dateCorrector: DateCorrectorMock(),
            userInfoProvider: UserInfoProvider(),
            networkConnectionInfoProvider: NetworkConnectionInfoProvider(),
            carrierInfoProvider: CarrierInfoProvider(),
            launchTimeProvider: LaunchTimeProvider(),
            appStateListener: AppStateListener(dateProvider: SystemDateProvider()),
            encryption: nil
        )
    }
}
