/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal
import OpenTelemetryApi

@testable import DatadogTrace

final class OTelAttributeValueDatadogTests: XCTestCase {
    func testTags_givenMultipleLevelsAttributes() {
        // Given
        let attributes = makeAttributes(level: 3)

        // When
        let tags = attributes.tags

        let expectedTags =
        [
            "key3-0": "true",
            "key3-1": "value1",
            "key3-2": "2",
            "key3-3": "3.0",
            "key3-4.0": "value4",
            "key3-4.1": "value5",
            "key3-5.0": "true",
            "key3-5.1": "false",
            "key3-6.0": "7",
            "key3-6.1": "8",
            "key3-7.0": "7.0",
            "key3-7.1": "8.0",
            "key3-8.key2-0": "true",
            "key3-8.key2-1": "value1",
            "key3-8.key2-2": "2",
            "key3-8.key2-3": "3.0",
            "key3-8.key2-4.0": "value4",
            "key3-8.key2-4.1": "value5",
            "key3-8.key2-5.0": "true",
            "key3-8.key2-5.1": "false",
            "key3-8.key2-6.0": "7",
            "key3-8.key2-6.1": "8",
            "key3-8.key2-7.0": "7.0",
            "key3-8.key2-7.1": "8.0",
            "key3-8.key2-8.key1-0": "true",
            "key3-8.key2-8.key1-1": "value1",
            "key3-8.key2-8.key1-2": "2",
            "key3-8.key2-8.key1-3": "3.0",
            "key3-8.key2-8.key1-4.0": "value4",
            "key3-8.key2-8.key1-4.1": "value5",
            "key3-8.key2-8.key1-5.0": "true",
            "key3-8.key2-8.key1-5.1": "false",
            "key3-8.key2-8.key1-6.0": "7",
            "key3-8.key2-8.key1-6.1": "8",
            "key3-8.key2-8.key1-7.0": "7.0",
            "key3-8.key2-8.key1-7.1": "8.0",
            "key3-8.key2-8.key1-8": "" // when recursion ends, empty string is returned
        ]

        // Then
        DDAssertDictionariesEqual(expectedTags, tags)
    }

    func testTags_givenOneLevelAttributesWithEmptyCollections() {
        // Given
        let attributes: [String: OpenTelemetryApi.AttributeValue] = [
            "key1": .bool(true),
            "key2": .string("value1"),
            "key3": .int(2),
            "key4": .double(3.0),
            "key5": .array(.init(values: [.string("value5"), .string("value6")])),
            "key6": .array(.init(values: [.bool(true), .bool(false)])),
            "key7": .array(.init(values: [.int(7), .int(8)])),
            "key8": .array(.init(values: [.double(8.0), .double(9.0)])),
            "key9": .set(.init(labels: [:])),
            "key10": .array(.init(values: [])),
        ]

        // When
        let tags = attributes.tags

        // Then
        let expectedTags =
        [
            "key1": "true",
            "key2": "value1",
            "key3": "2",
            "key4": "3.0",
            "key5.0": "value5",
            "key5.1": "value6",
            "key6.0": "true",
            "key6.1": "false",
            "key7.0": "7",
            "key7.1": "8",
            "key8.0": "8.0",
            "key8.1": "9.0",
            "key9": "",
            "key10": "",
        ]
        DDAssertDictionariesEqual(expectedTags, tags)
    }

    // MARK: - Helpers

    func makeAttributes(level: UInt) -> [String: OpenTelemetryApi.AttributeValue] {
        guard level > 0 else {
            return [:]
        }

        return [
            "key\(level)-0": .bool(true),
            "key\(level)-1": .string("value1"),
            "key\(level)-2": .int(2),
            "key\(level)-3": .double(3.0),
            "key\(level)-4": .array(.init(values: [.string("value4"), .string("value5")])),
            "key\(level)-5": .array(.init(values: [.bool(true), .bool(false)])),
            "key\(level)-6": .array(.init(values: [.int(7), .int(8)])),
            "key\(level)-7": .array(.init(values: [.double(7.0), .double(8.0)])),
            "key\(level)-8": .set(.init(labels: makeAttributes(level: level - 1)))
        ]
    }
}
