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
            batteryStatusProvider: BatteryStatusProvider(),
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

extension FeaturesConfiguration.Common {
    static func mockAny() -> Self {
        return .init(
            site: .us1,
            clientToken: .mockAny(),
            applicationName: .mockAny(),
            applicationVersion: .mockAny(),
            applicationBundleIdentifier: .mockAny(),
            serviceName: .mockAny(),
            environment: .mockAny(),
            performance: .init(batchSize: .medium, uploadFrequency: .average, bundleType: .iOSApp),
            source: .mockAny(),
            origin: nil,
            sdkVersion: .mockAny(),
            proxyConfiguration: nil,
            encryption: nil
        )
    }
}

struct FeatureRequestBuilderMock: FeatureRequestBuilder {
    let dataFormat = DataFormat(prefix: "", suffix: "", separator: "\n")

    func request(for payloads: [Data], with context: DatadogV1Context) -> URLRequest {
        let builder = URLRequestBuilder(
            url: .mockAny(),
            queryItems: [.ddtags(tags: ["foo:bar"])],
            headers: []
        )

        let data = dataFormat.format(payloads)
        return builder.uploadRequest(with: data)
    }
}

extension DatadogV1Context: AnyMockable {
    static func mockAny() -> DatadogV1Context {
        return mockWith()
    }

    static func mockWith(
        configuration: CoreConfiguration = .mockAny(),
        dependencies: CoreDependencies = .mockAny()
    ) -> DatadogV1Context {
        return DatadogV1Context(
            configuration: configuration,
            dependencies: dependencies
        )
    }
}
