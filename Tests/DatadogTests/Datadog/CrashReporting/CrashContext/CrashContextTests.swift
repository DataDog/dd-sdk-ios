/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
@testable import Datadog

class CrashContextTests: XCTestCase {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func testGivenContextWithTrackingConsentSet_whenItGetsEncoded_thenTheValueIsPreservedAfterDecoding() throws {
        let randomConsent: TrackingConsent = .mockRandom()

        // Given
        let context: CrashContext = .mockWith(trackingConsent: randomConsent)

        // When
        let serializedContext = try encoder.encode(context)

        // Then
        let deserializedContext = try decoder.decode(CrashContext.self, from: serializedContext)
        XCTAssertEqual(deserializedContext.trackingConsent, randomConsent)
    }

    func testGivenContextWithLastRUMViewEventSet_whenItGetsEncoded_thenTheValueIsPreservedAfterDecoding() throws {
        let randomRUMViewEvent = AnyCodable(mockRandomAttributes())

        // Given
        let context: CrashContext = .mockWith(lastRUMViewEvent: randomRUMViewEvent)

        // When
        let serializedContext = try encoder.encode(context)

        // Then
        let deserializedContext = try decoder.decode(CrashContext.self, from: serializedContext)
        DDAssertJSONEqual(
            deserializedContext.lastRUMViewEvent,
            randomRUMViewEvent
        )
    }

    func testGivenContextWithLastRUMSessionStateSet_whenItGetsEncoded_thenTheValueIsPreservedAfterDecoding() throws {
        let randomRUMSessionState = Bool.random() ?
            AnyCodable(mockRandomAttributes()) : nil

        // Given
        let context: CrashContext = .mockWith(lastRUMSessionState: randomRUMSessionState)

        // When
        let serializedContext = try encoder.encode(context)

        // Then
        let deserializedContext = try decoder.decode(CrashContext.self, from: serializedContext)
        DDAssertJSONEqual(
            deserializedContext.lastRUMSessionState,
            randomRUMSessionState
        )
    }

    func testGivenContextWithUserInfoSet_whenItGetsEncoded_thenTheValueIsPreservedAfterDecoding() throws {
        let randomUserInfo: UserInfo = .mockRandom()

        // Given
        let context: CrashContext = .mockWith(userInfo: randomUserInfo)

        // When
        let serializedContext = try encoder.encode(context)

        // Then
        let deserializedContext = try decoder.decode(CrashContext.self, from: serializedContext)
        XCTAssertEqual(deserializedContext.userInfo?.id, randomUserInfo.id)
        XCTAssertEqual(deserializedContext.userInfo?.name, randomUserInfo.name)
        XCTAssertEqual(deserializedContext.userInfo?.email, randomUserInfo.email)

        DDAssertJSONEqual(
            deserializedContext.userInfo!.extraInfo.mapValues { AnyEncodable($0) },
            randomUserInfo.extraInfo.mapValues { AnyEncodable($0) }
        )
    }

    func testGivenContextWithNetworkConnectionInfoSet_whenItGetsEncoded_thenTheValueIsPreservedAfterDecoding() throws {
        let randomNetworkConnectionInfo: NetworkConnectionInfo = .mockRandom()

        // Given
        let context: CrashContext = .mockWith(networkConnectionInfo: randomNetworkConnectionInfo)

        // When
        let serializedContext = try encoder.encode(context)

        // Then
        let deserializedContext = try decoder.decode(CrashContext.self, from: serializedContext)
        XCTAssertEqual(deserializedContext.networkConnectionInfo, randomNetworkConnectionInfo)
    }

    func testGivenContextWithCarrierInfoSet_whenItGetsEncoded_thenTheValueIsPreservedAfterDecoding() throws {
        let randomCarrierInfo: CarrierInfo = .mockRandom()

        // Given
        let context: CrashContext = .mockWith(carrierInfo: randomCarrierInfo)

        // When
        let serializedContext = try encoder.encode(context)

        // Then
        let deserializedContext = try decoder.decode(CrashContext.self, from: serializedContext)
        XCTAssertEqual(deserializedContext.carrierInfo, randomCarrierInfo)
    }

    func testGivenContextWithIsAppInForeground_whenItGetsEncoded_thenTheValueIsPreservedAfterDecoding() throws {
        let randomIsAppInForeground: Bool = .mockRandom()

        // Given
        let context: CrashContext = .mockWith(lastIsAppInForeground: randomIsAppInForeground)

        // When
        let serializedContext = try encoder.encode(context)

        // Then
        let deserializedContext = try decoder.decode(CrashContext.self, from: serializedContext)
        XCTAssertEqual(deserializedContext.lastIsAppInForeground, randomIsAppInForeground)
    }
}
