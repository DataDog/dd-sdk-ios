/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

@testable import Datadog

private struct DateCorrectionMock: DateCorrectionType {
    func toServerDate(deviceDate: Date) -> Date {
        return deviceDate
    }
}

extension FeaturesCommonDependencies {
    static func mockAny() -> Self {
        return .init(
            performance: .default,
            httpClient: HTTPClient(),
            mobileDevice: .current,
            dateProvider: SystemDateProvider(),
            dateCorrection: DateCorrectionMock(),
            userInfoProvider: UserInfoProvider(),
            networkConnectionInfoProvider: NetworkConnectionInfoProvider(),
            carrierInfoProvider: CarrierInfoProvider(),
            launchTimeProvider: LaunchTimeProvider()
        )
    }
}
