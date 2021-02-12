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
        func createRandomAttributes() -> [String: Encodable] {
            struct Foo: Encodable {
                let bar: String = .mockRandom()
                let bizz = Bizz()

                struct Bizz: Encodable {
                    let buzz: String = .mockRandom()
                }
            }

            return [
                "string-attribute": String.mockRandom(),
                "int-attribute": Int.mockRandom(),
                "uint64-attribute": UInt64.mockRandom(),
                "double-attribute": Double.mockRandom(),
                "bool-attribute": Bool.random(),
                "int-array-attribute": [Int].mockRandom(),
                "dictionary-attribute": [String: Int].mockRandom(),
                "url-attribute": URL.mockRandom(),
                "encodable-struct-attribute": Foo(),
                "custom-encodable-attribute": JSONStringEncodableValue(Foo(), encodedUsing: encoder)
            ]
        }

        let randomRUMViewEvent = RUMEvent(
            model: RUMViewEvent.mockRandom(),
            attributes: createRandomAttributes(),
            userInfoAttributes: createRandomAttributes()
        )

        // Given
        var context: CrashContext = .mockRandom()
        context.lastRUMViewEvent = randomRUMViewEvent

        // When
        let serializedContext = try encoder.encode(context)

        // Then
        let deserializedContext = try decoder.decode(CrashContext.self, from: serializedContext)
        try AssertEncodedRepresentationsEqual(deserializedContext.lastRUMViewEvent, randomRUMViewEvent)
    }

    // MARK: - Helpers

    /// Asserts that JSON representations of two `Encodable` values are equal.
    /// This allows us testing if the information is not lost due to type erasing done in `CrashContext` serialization.
    private func AssertEncodedRepresentationsEqual<V: Encodable>(
        _ value1: V,
        _ value2: V,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let prettyEncoder = JSONEncoder()
        prettyEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let encodedValue1 = try prettyEncoder.encode(value1)
        let encodedValue2 = try prettyEncoder.encode(value2)

        XCTAssertEqual(encodedValue1.utf8String, encodedValue2.utf8String, file: file, line: line)
    }
}
