/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

@testable import Datadog

private struct DateCorrectorMock: DateCorrector {
    let offset: TimeInterval = 0
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
            deviceInfo: DeviceInfo(),
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

struct FeatureRequestBuilderMock: FeatureRequestBuilder {
    let dataFormat = DataFormat(prefix: "", suffix: "", separator: "\n")

    func request(for events: [Data], with context: DatadogContext) -> URLRequest {
        let builder = URLRequestBuilder(
            url: .mockAny(),
            queryItems: [.ddtags(tags: ["foo:bar"])],
            headers: []
        )

        let data = dataFormat.format(events)
        return builder.uploadRequest(with: data)
    }
}

extension DatadogContext: AnyMockable {
    static func mockAny() -> DatadogContext {
        .init(
            site: .us1,
            clientToken: .mockAny(),
            service: .mockAny(),
            env: .mockAny(),
            version: .mockAny(),
            source: .mockAny(),
            sdkVersion: .mockAny(),
            ciAppOrigin: .mockAny(),
            serverTimeOffset: .zero,
            applicationName: .mockAny(),
            applicationBundleIdentifier: .mockAny(),
            sdkInitDate: .mockRandomInThePast(),
            device: DeviceInfo(),
            userInfo: nil,
            launchTime: nil,
            applicationStateHistory: nil,
            networkConnectionInfo: nil,
            carrierInfo: nil,
            isLowPowerModeEnabled: false
        )
    }
}
