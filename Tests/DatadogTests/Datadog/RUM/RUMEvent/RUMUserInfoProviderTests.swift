/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
@testable import Datadog

class RUMUserInfoProviderTests: XCTestCase {
    private let userInfoProvider = UserInfoProvider()
    private lazy var rumUserInfoProvider = RUMUserInfoProvider(userInfoProvider: userInfoProvider)

    func testWhenUserInfoIsNotAvailable_itReturnsNil() {
        userInfoProvider.value = .mockEmpty()
        XCTAssertNil(rumUserInfoProvider.current)
    }

    func testWhenUserInfoIsAvailable_itReturnsRUMUserInfo() {
        userInfoProvider.value = UserInfo(id: "abc-123", name: nil, email: nil, extraInfo: [:])
        DDAssertReflectionEqual(rumUserInfoProvider.current, RUMUser(email: nil, id: "abc-123", name: nil, usrInfo: [:]))

        userInfoProvider.value = UserInfo(id: "abc-123", name: "Foo", email: nil, extraInfo: [:])
        DDAssertReflectionEqual(rumUserInfoProvider.current, RUMUser(email: nil, id: "abc-123", name: "Foo", usrInfo: [:]))

        userInfoProvider.value = UserInfo(id: "abc-123", name: "Foo", email: "foo@bar.com", extraInfo: [:])
        DDAssertReflectionEqual(rumUserInfoProvider.current, RUMUser(email: "foo@bar.com", id: "abc-123", name: "Foo", usrInfo: [:]))

        userInfoProvider.value = UserInfo(id: "abc-123", name: "Foo", email: "foo@bar.com", extraInfo: [:])
        DDAssertReflectionEqual(rumUserInfoProvider.current, RUMUser(email: "foo@bar.com", id: "abc-123", name: "Foo", usrInfo: [:]))

        let extraInfo: [String: Encodable] = mockRandomAttributes()
        userInfoProvider.value = UserInfo(id: "abc-123", name: "Foo", email: "foo@bar.com", extraInfo: extraInfo)
        DDAssertReflectionEqual(rumUserInfoProvider.current, RUMUser(email: "foo@bar.com", id: "abc-123", name: "Foo", usrInfo: extraInfo))
    }
}
