/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class RUMEventBuilderTests: XCTestCase {
    func testItBuildsRUMEvent() {
        let builder = RUMEventBuilder(userInfoProvider: UserInfoProvider.mockAny())
        let event = builder.createRUMEvent(
            with: RUMDataModelMock(attribute: "foo"),
            attributes: ["foo": "bar", "fizz": "buzz"]
        )

        XCTAssertEqual(event.model.attribute, "foo")
        XCTAssertEqual((event.attributes as? [String: String])?["foo"], "bar")
        XCTAssertEqual((event.attributes as? [String: String])?["fizz"], "buzz")
    }
}
