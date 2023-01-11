/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

@testable import Datadog

extension PerformancePreset {
    static let benchmarksPreset = PerformancePreset(batchSize: .small, uploadFrequency: .frequent, bundleType: .iOSApp)
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
    public static func mockAny() -> DatadogContext {
        .init(
            site: .us1,
            clientToken: .mockAny(),
            service: .mockAny(),
            env: .mockAny(),
            version: .mockAny(),
            variant: nil,
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
            applicationStateHistory: .active(since: Date()),
            networkConnectionInfo: .unknown,
            carrierInfo: nil,
            isLowPowerModeEnabled: false
        )
    }
}
