/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
@testable import Datadog

/*
A collection of mocks for Logs objects.
It follows the mocking conventions described in `FoundationMocks.swift`.
 */

extension Log {
    static func mockWith(
        date: Date = .mockAny(),
        status: Log.Status = .mockAny(),
        message: String = .mockAny(),
        serviceName: String = .mockAny(),
        loggerName: String = .mockAny(),
        loggerVersion: String = .mockAny(),
        threadName: String = .mockAny(),
        applicationVersion: String = .mockAny(),
        userInfo: UserInfo = .mockAny(),
        networkConnectionInfo: NetworkConnectionInfo = .mockAny(),
        mobileCarrierInfo: CarrierInfo? = .mockAny(),
        attributes: [String: EncodableValue]? = nil,
        tags: [String]? = nil
    ) -> Log {
        return Log(
            date: date,
            status: status,
            message: message,
            serviceName: serviceName,
            loggerName: loggerName,
            loggerVersion: loggerVersion,
            threadName: threadName,
            applicationVersion: applicationVersion,
            userInfo: userInfo,
            networkConnectionInfo: networkConnectionInfo,
            mobileCarrierInfo: mobileCarrierInfo,
            attributes: attributes,
            tags: tags
        )
    }

    static func mockRandom() -> Log {
        return mockWith(
            date: .mockRandomInThePast(),
            status: .mockRandom(),
            message: .mockRandom(length: 20),
            serviceName: .mockRandom(),
            loggerName: .mockRandom(),
            loggerVersion: .mockRandom(),
            threadName: .mockRandom(),
            applicationVersion: .mockRandom(),
            userInfo: .mockRandom(),
            networkConnectionInfo: .mockRandom(),
            mobileCarrierInfo: .mockRandom()
        )
    }
}

extension Log.Status {
    static func mockAny() -> Log.Status {
        return .info
    }

    static func mockRandom() -> Log.Status {
        let statuses: [Log.Status] = [.debug, .info, .notice, .warn, .error, .critical]
        return statuses.randomElement()!
    }
}

extension EncodableValue {
    static func mockAny() -> EncodableValue {
        return EncodableValue(String.mockAny())
    }
}

extension LogBuilder {
    static func mockAny() -> LogBuilder {
        return mockWith()
    }

    static func mockWith(
        date: Date = .mockAny(),
        appContext: AppContext = .mockAny(),
        serviceName: String = .mockAny(),
        loggerName: String = .mockAny(),
        userInfoProvider: UserInfoProvider = .mockAny(),
        networkConnectionInfoProvider: NetworkConnectionInfoProviderType = NetworkConnectionInfoProviderMock.mockAny(),
        carrierInfoProvider: CarrierInfoProviderType = CarrierInfoProviderMock.mockAny()
    ) -> LogBuilder {
        return LogBuilder(
            appContext: appContext,
            serviceName: serviceName,
            loggerName: loggerName,
            dateProvider: RelativeDateProvider(using: date),
            userInfoProvider: userInfoProvider,
            networkConnectionInfoProvider: networkConnectionInfoProvider,
            carrierInfoProvider: carrierInfoProvider
        )
    }
}
