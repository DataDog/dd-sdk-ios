/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal
@testable import DatadogRUM

final class RUMViewEventsFilterTests: XCTestCase {
    private var telemetry: TelemetryMock! // swiftlint:disable:this implicitly_unwrapped_optional
    private var sut: RUMViewEventsFilter! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUp() {
        telemetry = TelemetryMock()
        sut = RUMViewEventsFilter(telemetry: telemetry)
    }

    override func tearDown() {
        telemetry = nil
        sut = nil
    }

    // MARK: - Base cases

    func testFilterWhenNoEvents() throws {
        let events = [Event]()

        let actual = sut.filter(events: events)
        let expected = [Event]()

        XCTAssertEqual(actual, expected)
    }

    func testFilterWhenNoMetadata() throws {
        let events = [
            try Event(data: "A.1", viewMetadata: nil),
            try Event(data: "A.2", viewMetadata: nil),
            try Event(data: "A.3", viewMetadata: nil),
            try Event(data: "A.4", viewMetadata: nil)
        ]

        let actual = sut.filter(events: events)

        XCTAssertEqual(actual, events)
    }

    func testFilterWhenMixedMissingMetadata() throws {
        let events = [
            try Event(data: "A.1", viewMetadata: nil),
            try Event(data: "A.2", viewMetadata: nil),
            try Event(data: "B.1", viewMetadata: .mock(id: "B", documentVersion: 1)),
            try Event(data: "B.2", viewMetadata: .mock(id: "B", documentVersion: 2)),
            try Event(data: "C.1", viewMetadata: nil),
            try Event(data: "B.3", viewMetadata: .mock(id: "B", documentVersion: 3)),
            try Event(data: "A.3", viewMetadata: nil)
        ]

        let actual = sut.filter(events: events)
        let expected = [
            try Event(data: "A.1", viewMetadata: nil),
            try Event(data: "A.2", viewMetadata: nil),
            try Event(data: "C.1", viewMetadata: nil),
            try Event(data: "B.3", viewMetadata: .mock(id: "B", documentVersion: 3)),
            try Event(data: "A.3", viewMetadata: nil)
        ]

        XCTAssertEqual(actual, expected)
    }

    // MARK: - Common filtering scenarios

    func testFilterWhenSameEvent() throws {
         let events = [
            try Event(data: "A.1", viewMetadata: .mock(id: "A", documentVersion: 1)),
            try Event(data: "A.2", viewMetadata: .mock(id: "A", documentVersion: 2)),
            try Event(data: "A.3", viewMetadata: .mock(id: "A", documentVersion: 3)),
            try Event(data: "A.4", viewMetadata: .mock(id: "A", documentVersion: 4))
         ]

        let actual = sut.filter(events: events)
        let expected = [
            try Event(data: "A.4", viewMetadata: .mock(id: "A", documentVersion: 4))
        ]

        XCTAssertEqual(actual, expected)
    }

    func testFilterWhenMixedEvents() throws {
          let events = [
            try Event(data: "B.1", viewMetadata: .mock(id: "B", documentVersion: 1)),
            try Event(data: "A.5", viewMetadata: .mock(id: "A", documentVersion: 5)),
            try Event(data: "B.2", viewMetadata: .mock(id: "B", documentVersion: 2)),
          ]

        let actual = sut.filter(events: events)
        let expected = [
            try Event(data: "A.5", viewMetadata: .mock(id: "A", documentVersion: 5)),
            try Event(data: "B.2", viewMetadata: .mock(id: "B", documentVersion: 2)),
        ]

        XCTAssertEqual(actual, expected)
    }

    func testFilterWhenSingleEvent() throws {
        let events = [
            try Event(data: "B.3", viewMetadata: .mock(id: "B", documentVersion: 3)),
        ]

        let actual = sut.filter(events: events)
        let expected = [
            try Event(data: "B.3", viewMetadata: .mock(id: "B", documentVersion: 3)),
        ]

        XCTAssertEqual(actual, expected)
    }

    // MARK: - Initial 1ns view filtering

    func testFilterWhenInitialOneNsDuration() throws {
        let events = [
            try Event(data: "A.1", viewMetadata: .mock(id: "A", documentVersion: 1, duration: 1, indexInSession: 0)),
            try Event(data: "B.1", viewMetadata: .mock(id: "B", documentVersion: 1, duration: 100, indexInSession: 1)),
            try Event(data: "C.1", viewMetadata: .mock(id: "C", documentVersion: 1, duration: 1, indexInSession: 2))
        ]

        let actual = sut.filter(events: events)
        let expected = [
            try Event(data: "B.1", viewMetadata: .mock(id: "B", documentVersion: 1, duration: 100, indexInSession: 1)),
            try Event(data: "C.1", viewMetadata: .mock(id: "C", documentVersion: 1, duration: 1, indexInSession: 2))
        ]

        XCTAssertEqual(actual, expected)
    }

    func testFilterWhenMixedInitialOneNsAndRedundant() throws {
        let events = [
            try Event(data: "A.1", viewMetadata: .mock(id: "A", documentVersion: 1, duration: 1, indexInSession: 0)),
            try Event(data: "A.2", viewMetadata: .mock(id: "A", documentVersion: 2, duration: 100, indexInSession: 0)),
            try Event(data: "B.1", viewMetadata: .mock(id: "B", documentVersion: 1, duration: 1, indexInSession: 1)),
            try Event(data: "B.2", viewMetadata: .mock(id: "B", documentVersion: 2, duration: 200, indexInSession: 1))
        ]

        let actual = sut.filter(events: events)
        let expected = [
            try Event(data: "A.2", viewMetadata: .mock(id: "A", documentVersion: 2, duration: 100, indexInSession: 0)),
            try Event(data: "B.2", viewMetadata: .mock(id: "B", documentVersion: 2, duration: 200, indexInSession: 1))
        ]

        XCTAssertEqual(actual, expected)
    }

    func testFilterWhenInitialOneNsDurationWithNilDuration() throws {
        let events = [
            try Event(data: "A.1", viewMetadata: .mock(id: "A", documentVersion: 1, indexInSession: 0)),
            try Event(data: "B.1", viewMetadata: .mock(id: "B", documentVersion: 1, duration: 1, indexInSession: 0)),
            try Event(data: "C.1", viewMetadata: .mock(id: "C", documentVersion: 1, duration: 2, indexInSession: 1))
        ]

        let actual = sut.filter(events: events)
        let expected = [
            try Event(data: "A.1", viewMetadata: .mock(id: "A", documentVersion: 1, indexInSession: 0)),
            try Event(data: "C.1", viewMetadata: .mock(id: "C", documentVersion: 1, duration: 2, indexInSession: 1))
        ]

        XCTAssertEqual(actual, expected)
    }

    func testFilterAlwaysKeepsEventsWithAccessibility() throws {
        // Test that events with accessibility are always kept, even if they would normally be filtered out
        let events = [
            try Event(data: "A.1", viewMetadata: .mock(id: "A", documentVersion: 1, hasAccessibility: false)),
            try Event(data: "A.2", viewMetadata: .mock(id: "A", documentVersion: 2, hasAccessibility: true)), // This should be kept
            try Event(data: "A.3", viewMetadata: .mock(id: "A", documentVersion: 3, hasAccessibility: false)),
            try Event(data: "A.4", viewMetadata: .mock(id: "A", documentVersion: 4, hasAccessibility: false)),
            try Event(data: "B.1", viewMetadata: .mock(id: "B", documentVersion: 1, hasAccessibility: false)),
            try Event(data: "B.2", viewMetadata: .mock(id: "B", documentVersion: 2, hasAccessibility: true)), // This should be kept
            try Event(data: "B.3", viewMetadata: .mock(id: "B", documentVersion: 3, hasAccessibility: false)),
        ]

        let actual = sut.filter(events: events)

        // Verify that accessibility events are kept
        let decoder = JSONDecoder()

        let accessibilityEvents = try actual.filter { event in
            if let metadata = event.metadata {
                let viewMetadata = try decoder.decode(RUMViewEvent.Metadata.self, from: metadata)
                return viewMetadata.hasAccessibility == true
            }
            return false
        }

        // Should have 2 accessibility events (A.2 and B.2)
        XCTAssertEqual(accessibilityEvents.count, 2, "Accessibility events should always be kept")

        // Verify the specific accessibility events are present
        let hasA2 = try actual.contains { event in
            if let metadata = event.metadata {
               let viewMetadata = try decoder.decode(RUMViewEvent.Metadata.self, from: metadata)
                return viewMetadata.id == "A" && viewMetadata.documentVersion == 2 && viewMetadata.hasAccessibility == true
            }
            return false
        }

        let hasB2 = try actual.contains { event in
            if let metadata = event.metadata {
               let viewMetadata = try decoder.decode(RUMViewEvent.Metadata.self, from: metadata)
                return viewMetadata.id == "B" && viewMetadata.documentVersion == 2 && viewMetadata.hasAccessibility == true
            }
            return false
        }

        XCTAssertTrue(hasA2, "Event A.2 with accessibility should be kept")
        XCTAssertTrue(hasB2, "Event B.2 with accessibility should be kept")
    }

    // MARK: - Error handling and telemetry

    func testFilterWhenInvalidMetadata() throws {
        let invalidMetadata = "invalid json".utf8Data
        let events = [
            Event(data: "A.1".utf8Data, metadata: invalidMetadata),
            try Event(data: "B.1", viewMetadata: .mock(id: "B", documentVersion: 1))
        ]

        let actual = sut.filter(events: events)
        let expected = [
            Event(data: "A.1".utf8Data, metadata: invalidMetadata),
            try Event(data: "B.1", viewMetadata: .mock(id: "B", documentVersion: 1))
        ]

        XCTAssertEqual(actual, expected)
        XCTAssertEqual(telemetry.messages.count, 1)
        XCTAssertTrue(telemetry.messages.firstError()?.message.contains("Failed to decode RUM view event metadata") == true)
    }

    func testFilterWhenMixedValidAndInvalidMetadata() throws {
        let invalidMetadata = "invalid json".utf8Data
        let events = [
            try Event(data: "A.1", viewMetadata: .mock(id: "A", documentVersion: 1)),
            Event(data: "B.1".utf8Data, metadata: invalidMetadata),
            try Event(data: "C.1", viewMetadata: .mock(id: "C", documentVersion: 1, duration: 1, indexInSession: 0)),
            Event(data: "D.1".utf8Data, metadata: invalidMetadata)
        ]

        let actual = sut.filter(events: events)
        let expected = [
            try Event(data: "A.1", viewMetadata: .mock(id: "A", documentVersion: 1)),
            Event(data: "B.1".utf8Data, metadata: invalidMetadata),
            Event(data: "D.1".utf8Data, metadata: invalidMetadata)
        ]

        XCTAssertEqual(actual, expected)
        XCTAssertEqual(telemetry.messages.compactMap({ $0.asError }).count, 2)
    }
}

extension Event {
    init(data: String, viewMetadata: RUMViewEvent.Metadata?) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        self.init(data: data.utf8Data, metadata: try encoder.encode(viewMetadata))
    }
}

extension RUMViewEvent.Metadata {
    static func mock(
        id: String = .mockAny(),
        documentVersion: Int64 = .mockAny(),
        duration: Int64? = nil,
        indexInSession: Int? = nil,
        hasAccessibility: Bool? = nil
    ) -> RUMViewEvent.Metadata {
        return RUMViewEvent.Metadata(id: id, documentVersion: documentVersion, hasAccessibility: hasAccessibility, duration: duration, indexInSession: indexInSession)
    }
}

extension Event: CustomDebugStringConvertible {
    public var debugDescription: String {
        let dataString = String(data: data, encoding: .utf8) ?? "<Not a string>"
        let metadataString = metadata.map { String(data: $0, encoding: .utf8) ?? "<Not a string>" }
        return dataString + "." + (metadataString ?? "nil")
    }
}
