/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class CrashContextTests: XCTestCase {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func testGivenContextWithTrackingConsentSet_whenItGetsEncoded_thenTheValueIsPreservedAfterDecoding() throws {
        let randomConsent: TrackingConsent = .mockRandom()

        // Given
        var context: CrashContext = .mockRandom()
        context.lastTrackingConsent = randomConsent

        // When
        let serializedContext = try encoder.encode(context)

        // Then
        let deserializedContext = try decoder.decode(CrashContext.self, from: serializedContext)
        XCTAssertEqual(deserializedContext.lastTrackingConsent, randomConsent)
    }

    func testGivenContextWithLastRUMViewEventSet_whenItGetsEncoded_thenTheValueIsPreservedAfterDecoding() throws {
        let randomRUMViewEvent = RUMEvent(
            model: RUMViewEvent.mockRandom(),
            attributes: mockRandomAttributes(),
            userInfoAttributes: mockRandomAttributes()
        )

        // Given
        var context: CrashContext = .mockRandom()
        context.lastRUMViewEvent = randomRUMViewEvent

        // When
        let serializedContext = try encoder.encode(context)

        // Then
        let deserializedContext = try decoder.decode(CrashContext.self, from: serializedContext)
        try AssertEncodedRepresentationsEqual(
            value1: deserializedContext.lastRUMViewEvent,
            value2: randomRUMViewEvent
        )
    }

    func testGivenContextWithUserInfoSet_whenItGetsEncoded_thenTheValueIsPreservedAfterDecoding() throws {
        let randomUserInfo: UserInfo = .mockRandom()

        // Given
        var context: CrashContext = .mockRandom()
        context.lastUserInfo = randomUserInfo

        // When
        let serializedContext = try encoder.encode(context)

        // Then
        let deserializedContext = try decoder.decode(CrashContext.self, from: serializedContext)
        XCTAssertEqual(deserializedContext.lastUserInfo?.id, randomUserInfo.id)
        XCTAssertEqual(deserializedContext.lastUserInfo?.name, randomUserInfo.name)
        XCTAssertEqual(deserializedContext.lastUserInfo?.email, randomUserInfo.email)
        try AssertEncodedRepresentationsEqual(
            dictionary1: deserializedContext.lastUserInfo!.extraInfo,
            dictionary2: randomUserInfo.extraInfo
        )
    }

    func testGivenContextWithNetworkConnectionInfoSet_whenItGetsEncoded_thenTheValueIsPreservedAfterDecoding() throws {
        let randomNetworkConnectionInfo: NetworkConnectionInfo = .mockRandom()

        // Given
        var context: CrashContext = .mockRandom()
        context.lastNetworkConnectionInfo = randomNetworkConnectionInfo

        // When
        let serializedContext = try encoder.encode(context)

        // Then
        let deserializedContext = try decoder.decode(CrashContext.self, from: serializedContext)
        XCTAssertEqual(deserializedContext.lastNetworkConnectionInfo, randomNetworkConnectionInfo)
    }

    func testGivenContextWithCarrierInfoSet_whenItGetsEncoded_thenTheValueIsPreservedAfterDecoding() throws {
        let randomCarrierInfo: CarrierInfo = .mockRandom()

        // Given
        var context: CrashContext = .mockRandom()
        context.lastCarrierInfo = randomCarrierInfo

        // When
        let serializedContext = try encoder.encode(context)

        // Then
        let deserializedContext = try decoder.decode(CrashContext.self, from: serializedContext)
        XCTAssertEqual(deserializedContext.lastCarrierInfo, randomCarrierInfo)
    }

    // MARK: - Helpers

    /// Asserts that JSON representations of two `[String: Encodable]` dictionaries are equal.
    /// This allows us testing if the information is not lost due to type erasing done in `CrashContext` serialization.
    private func AssertEncodedRepresentationsEqual(
        dictionary1: [String: Encodable],
        dictionary2: [String: Encodable],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        try AssertEncodedRepresentationsEqual(
            value1: dictionary1.mapValues { CodableValue($0) },
            value2: dictionary2.mapValues { CodableValue($0) }
        )
    }
}
