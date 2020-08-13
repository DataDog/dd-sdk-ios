/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

@testable import Datadog

extension FeaturesCommonDependencies {
    static func mockAny() -> FeaturesCommonDependencies {
        let anyURL = URL(string: "https://foo.com")!
        return FeaturesCommonDependencies(
            configuration: .init(
                applicationName: "",
                applicationVersion: "",
                applicationBundleIdentifier: "",
                serviceName: "",
                environment: "",
                logsUploadURLWithClientToken: anyURL,
                tracesUploadURLWithClientToken: anyURL,
                rumUploadURLWithClientToken: anyURL
            ),
            performance: .default,
            httpClient: HTTPClient(),
            mobileDevice: .current,
            dateProvider: SystemDateProvider(),
            userInfoProvider: UserInfoProvider(),
            networkConnectionInfoProvider: NetworkConnectionInfoProvider(),
            carrierInfoProvider: CarrierInfoProvider()
        )
    }
}
