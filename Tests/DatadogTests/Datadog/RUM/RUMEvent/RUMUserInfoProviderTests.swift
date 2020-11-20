/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

extension RUMDataUSR: EquatableInTests {}

class RUMUserInfoProviderTests: XCTestCase {
    private let userInfoProvider = UserInfoProvider()
    private lazy var rumUserInfoProvider = RUMUserInfoProvider(userInfoProvider: userInfoProvider)

    func testWhenUserInfoIsNotAvailable_itReturnsNil() {
        userInfoProvider.value = .mockEmpty()
        XCTAssertNil(rumUserInfoProvider.current)
    }

    func testWhenUserInfoIsAvailable_itReturnsRUMUserInfo() {
        userInfoProvider.value = UserInfo(id: "abc-123", name: nil, email: nil, extraInfo: [:])
        XCTAssertEqual(rumUserInfoProvider.current, RUMDataUSR(id: "abc-123", name: nil, email: nil))

        userInfoProvider.value = UserInfo(id: "abc-123", name: "Foo", email: nil, extraInfo: [:])
        XCTAssertEqual(rumUserInfoProvider.current, RUMDataUSR(id: "abc-123", name: "Foo", email: nil))

        userInfoProvider.value = UserInfo(id: "abc-123", name: "Foo", email: "foo@bar.com", extraInfo: [:])
        XCTAssertEqual(rumUserInfoProvider.current, RUMDataUSR(id: "abc-123", name: "Foo", email: "foo@bar.com"))

        userInfoProvider.value = UserInfo(id: "abc-123", name: "Foo", email: "foo@bar.com", extraInfo: [:])
        XCTAssertEqual(rumUserInfoProvider.current, RUMDataUSR(id: "abc-123", name: "Foo", email: "foo@bar.com"))
    }
}
