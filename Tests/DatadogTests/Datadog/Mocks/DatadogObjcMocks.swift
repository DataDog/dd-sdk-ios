/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-2020 Datadog, Inc.
*/

@testable import DatadogObjc
@testable import Datadog

/*
A collection of SDK object mocks for Obj-C.
It follows the mocking conventions described in `FoundationMocks.swift`.
 */

extension DDAppContext {
    static func mockAny() -> DDAppContext {
        return DDAppContext(mainBundle: .mockAny())
    }
}

extension DDConfiguration {
    static func mockAny() -> DDConfiguration {
        return mockWith()
    }

    static func mockWith(
        logsUploadURLProvider: UploadURLProvider? = .mockAny()
    ) -> DDConfiguration {
        let mockConfiguration = Datadog.Configuration(clientToken: "mockClientToken", logsEndpoint: .us)
        return DDConfiguration(
            sdkConfiguration: mockConfiguration
        )
    }
}
