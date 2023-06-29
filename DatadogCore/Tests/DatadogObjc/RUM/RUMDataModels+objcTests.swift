/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
@testable import DatadogRUM
@testable import DatadogCore
@testable import DatadogObjc

class RUMDataModels_objcTests: XCTestCase {
    func testGivenObjectiveCViewEventWithAnyAttributes_whenReadingAttributes_theirTypeIsNotAltered() throws {
        let expectedContextAttributes: [String: Any] = mockRandomAttributes()
        let expectedUserInfoAttributes: [String: Any] = mockRandomAttributes()

        // Given
        var swiftView: RUMViewEvent = .mockRandom()
        swiftView.context?.contextInfo = castAttributesToSwift(expectedContextAttributes)
        swiftView.usr?.usrInfo = castAttributesToSwift(expectedUserInfoAttributes)

        let objcView = DDRUMViewEvent(swiftModel: swiftView)

        // When
        let receivedContextAttributes = try XCTUnwrap(objcView.context?.contextInfo)
        let receivedUserInfoAttributes = try XCTUnwrap(objcView.usr?.usrInfo)

        // Then
        DDAssertDictionariesEqual(receivedContextAttributes, expectedContextAttributes)
        DDAssertDictionariesEqual(receivedUserInfoAttributes, expectedUserInfoAttributes)
    }

    func testGivenObjectiveCResourceEventWithAnyAttributes_whenReadingAttributes_theirTypeIsNotAltered() throws {
        let expectedContextAttributes: [String: Any] = mockRandomAttributes()
        let expectedUserInfoAttributes: [String: Any] = mockRandomAttributes()

        // Given
        var swiftResource: RUMResourceEvent = .mockRandom()
        swiftResource.context?.contextInfo = castAttributesToSwift(expectedContextAttributes)
        swiftResource.usr?.usrInfo = castAttributesToSwift(expectedUserInfoAttributes)

        let objcResource = DDRUMResourceEvent(swiftModel: swiftResource)

        // When
        let receivedContextAttributes = try XCTUnwrap(objcResource.context?.contextInfo)
        let receivedUserInfoAttributes = try XCTUnwrap(objcResource.usr?.usrInfo)

        // Then
        DDAssertDictionariesEqual(receivedContextAttributes, expectedContextAttributes)
        DDAssertDictionariesEqual(receivedUserInfoAttributes, expectedUserInfoAttributes)
    }

    func testGivenObjectiveCActionEventWithAnyAttributes_whenReadingAttributes_theirTypeIsNotAltered() throws {
        let expectedContextAttributes: [String: Any] = mockRandomAttributes()
        let expectedUserInfoAttributes: [String: Any] = mockRandomAttributes()

        // Given
        var swiftAction: RUMActionEvent = .mockRandom()
        swiftAction.context?.contextInfo = castAttributesToSwift(expectedContextAttributes)
        swiftAction.usr?.usrInfo = castAttributesToSwift(expectedUserInfoAttributes)

        let objcAction = DDRUMActionEvent(swiftModel: swiftAction)

        // When
        let receivedContextAttributes = try XCTUnwrap(objcAction.context?.contextInfo)
        let receivedUserInfoAttributes = try XCTUnwrap(objcAction.usr?.usrInfo)

        // Then
        DDAssertDictionariesEqual(receivedContextAttributes, expectedContextAttributes)
        DDAssertDictionariesEqual(receivedUserInfoAttributes, expectedUserInfoAttributes)
    }

    func testGivenObjectiveCErrorEventWithAnyAttributes_whenReadingAttributes_theirTypeIsNotAltered() throws {
        let expectedContextAttributes: [String: Any] = mockRandomAttributes()
        let expectedUserInfoAttributes: [String: Any] = mockRandomAttributes()

        // Given
        var swiftError: RUMErrorEvent = .mockRandom()
        swiftError.context?.contextInfo = castAttributesToSwift(expectedContextAttributes)
        swiftError.usr?.usrInfo = castAttributesToSwift(expectedUserInfoAttributes)

        let objcError = DDRUMErrorEvent(swiftModel: swiftError)

        // When
        let receivedContextAttributes = try XCTUnwrap(objcError.context?.contextInfo)
        let receivedUserInfoAttributes = try XCTUnwrap(objcError.usr?.usrInfo)

        // Then
        DDAssertDictionariesEqual(receivedContextAttributes, expectedContextAttributes)
        DDAssertDictionariesEqual(receivedUserInfoAttributes, expectedUserInfoAttributes)
    }

    func testGivenObjectiveCLongTaskEventWithAnyAttributes_whenReadingAttributes_theirTypeIsNotAltered() throws {
        let expectedContextAttributes: [String: Any] = mockRandomAttributes()
        let expectedUserInfoAttributes: [String: Any] = mockRandomAttributes()

        // Given
        var swiftLongTask: RUMLongTaskEvent = .mockRandom()
        swiftLongTask.context?.contextInfo = castAttributesToSwift(expectedContextAttributes)
        swiftLongTask.usr?.usrInfo = castAttributesToSwift(expectedUserInfoAttributes)

        let objcLongTask = DDRUMLongTaskEvent(swiftModel: swiftLongTask)

        // When
        let receivedContextAttributes = try XCTUnwrap(objcLongTask.context?.contextInfo)
        let receivedUserInfoAttributes = try XCTUnwrap(objcLongTask.usr?.usrInfo)

        // Then
        DDAssertDictionariesEqual(receivedContextAttributes, expectedContextAttributes)
        DDAssertDictionariesEqual(receivedUserInfoAttributes, expectedUserInfoAttributes)
    }
}
