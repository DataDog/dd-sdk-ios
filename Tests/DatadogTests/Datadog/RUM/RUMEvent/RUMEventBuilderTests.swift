/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class RUMEventBuilderTests: XCTestCase {
    func testItBuildsRUMEvent() {
        let builder = RUMEventBuilder(
            userInfoProvider: .mockWith(
                userInfo: UserInfo(id: "id", name: "name", email: "foo@bar.com")
            ),
            networkConnectionInfoProvider: NetworkConnectionInfoProviderMock.mockWith(
                networkConnectionInfo: .mockWith(
                    reachability: .yes,
                    availableInterfaces: [.wifi, .cellular]
                )
            ),
            carrierInfoProvider: CarrierInfoProviderMock.mockWith(
                carrierInfo: .mockWith(carrierName: "AT&T")
            )
        )

        let event = builder.createRUMEvent(
            with: RUMDataModelMock(attribute: "foo"),
            attributes: ["foo": "bar", "fizz": "buzz"]
        )

        XCTAssertEqual(event.model.attribute, "foo")
        XCTAssertEqual(event.userInfo.id, "id")
        XCTAssertEqual(event.userInfo.name, "name")
        XCTAssertEqual(event.userInfo.email, "foo@bar.com")
        XCTAssertEqual(event.mobileCarrierInfo?.carrierName, "AT&T")
        XCTAssertEqual(event.networkConnectionInfo?.reachability, .yes)
        XCTAssertEqual(event.networkConnectionInfo?.availableInterfaces, [.wifi, .cellular])
        XCTAssertEqual((event.attributes as? [String: String])?["foo"], "bar")
        XCTAssertEqual((event.attributes as? [String: String])?["fizz"], "buzz")
    }
}
