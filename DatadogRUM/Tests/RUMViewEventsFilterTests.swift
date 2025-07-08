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
            try Event(data: "B.1", viewMetadata: RUMViewEvent.Metadata(id: "B", documentVersion: 1, duration: nil)),
            try Event(data: "B.2", viewMetadata: RUMViewEvent.Metadata(id: "B", documentVersion: 2, duration: nil)),
            try Event(data: "C.1", viewMetadata: nil),
            try Event(data: "B.3", viewMetadata: RUMViewEvent.Metadata(id: "B", documentVersion: 3, duration: nil)),
            try Event(data: "A.3", viewMetadata: nil)
        ]

        let actual = sut.filter(events: events)
        let expected = [
            try Event(data: "A.1", viewMetadata: nil),
            try Event(data: "A.2", viewMetadata: nil),
            try Event(data: "C.1", viewMetadata: nil),
            try Event(data: "B.3", viewMetadata: RUMViewEvent.Metadata(id: "B", documentVersion: 3, duration: nil)),
            try Event(data: "A.3", viewMetadata: nil)
        ]

        XCTAssertEqual(actual, expected)
    }

    // MARK: - Common filtering scenarios

    func testFilterWhenSameEvent() throws {
         let events = [
            try Event(data: "A.1", viewMetadata: RUMViewEvent.Metadata(id: "A", documentVersion: 1, duration: nil)),
            try Event(data: "A.2", viewMetadata: RUMViewEvent.Metadata(id: "A", documentVersion: 2, duration: nil)),
            try Event(data: "A.3", viewMetadata: RUMViewEvent.Metadata(id: "A", documentVersion: 3, duration: nil)),
            try Event(data: "A.4", viewMetadata: RUMViewEvent.Metadata(id: "A", documentVersion: 4, duration: nil))
         ]

        let actual = sut.filter(events: events)
        let expected = [
            try Event(data: "A.4", viewMetadata: RUMViewEvent.Metadata(id: "A", documentVersion: 4, duration: nil))
        ]

        XCTAssertEqual(actual, expected)
    }

    func testFilterWhenMixedEvents() throws {
          let events = [
            try Event(data: "B.1", viewMetadata: RUMViewEvent.Metadata(id: "B", documentVersion: 1, duration: nil)),
            try Event(data: "A.5", viewMetadata: RUMViewEvent.Metadata(id: "A", documentVersion: 5, duration: nil)),
            try Event(data: "B.2", viewMetadata: RUMViewEvent.Metadata(id: "B", documentVersion: 2, duration: nil)),
          ]

        let actual = sut.filter(events: events)
        let expected = [
            try Event(data: "A.5", viewMetadata: RUMViewEvent.Metadata(id: "A", documentVersion: 5, duration: nil)),
            try Event(data: "B.2", viewMetadata: RUMViewEvent.Metadata(id: "B", documentVersion: 2, duration: nil)),
        ]

        XCTAssertEqual(actual, expected)
    }

    func testFilterWhenSingleEvent() throws {
        let events = [
            try Event(data: "B.3", viewMetadata: RUMViewEvent.Metadata(id: "B", documentVersion: 3, duration: nil)),
        ]

        let actual = sut.filter(events: events)
        let expected = [
            try Event(data: "B.3", viewMetadata: RUMViewEvent.Metadata(id: "B", documentVersion: 3, duration: nil)),
        ]

        XCTAssertEqual(actual, expected)
    }

    // MARK: - 1ns duration filtering

    func testFilterWhenOneNsDuration() throws {
        let events = [
            try Event(data: "A.1", viewMetadata: RUMViewEvent.Metadata(id: "A", documentVersion: 1, duration: 1)),
            try Event(data: "B.1", viewMetadata: RUMViewEvent.Metadata(id: "B", documentVersion: 1, duration: 100)),
            try Event(data: "C.1", viewMetadata: RUMViewEvent.Metadata(id: "C", documentVersion: 1, duration: 1))
        ]

        let actual = sut.filter(events: events)
        let expected = [
            try Event(data: "B.1", viewMetadata: RUMViewEvent.Metadata(id: "B", documentVersion: 1, duration: 100))
        ]

        XCTAssertEqual(actual, expected)
    }

    func testFilterWhenMixedOneNsAndRedundant() throws {
        let events = [
            try Event(data: "A.1", viewMetadata: RUMViewEvent.Metadata(id: "A", documentVersion: 1, duration: 1)),
            try Event(data: "A.2", viewMetadata: RUMViewEvent.Metadata(id: "A", documentVersion: 2, duration: 100)),
            try Event(data: "B.1", viewMetadata: RUMViewEvent.Metadata(id: "B", documentVersion: 1, duration: 1)),
            try Event(data: "B.2", viewMetadata: RUMViewEvent.Metadata(id: "B", documentVersion: 2, duration: 200))
        ]

        let actual = sut.filter(events: events)
        let expected = [
            try Event(data: "A.2", viewMetadata: RUMViewEvent.Metadata(id: "A", documentVersion: 2, duration: 100)),
            try Event(data: "B.2", viewMetadata: RUMViewEvent.Metadata(id: "B", documentVersion: 2, duration: 200))
        ]

        XCTAssertEqual(actual, expected)
    }

    func testFilterWhenOneNsDurationWithNilDuration() throws {
        let events = [
            try Event(data: "A.1", viewMetadata: RUMViewEvent.Metadata(id: "A", documentVersion: 1, duration: nil)),
            try Event(data: "B.1", viewMetadata: RUMViewEvent.Metadata(id: "B", documentVersion: 1, duration: 1)),
            try Event(data: "C.1", viewMetadata: RUMViewEvent.Metadata(id: "C", documentVersion: 1, duration: 2))
        ]

        let actual = sut.filter(events: events)
        let expected = [
            try Event(data: "A.1", viewMetadata: RUMViewEvent.Metadata(id: "A", documentVersion: 1, duration: nil)),
            try Event(data: "C.1", viewMetadata: RUMViewEvent.Metadata(id: "C", documentVersion: 1, duration: 2))
        ]

        XCTAssertEqual(actual, expected)
    }

    // MARK: - Error handling and telemetry

    func testFilterWhenInvalidMetadata() throws {
        let invalidMetadata = "invalid json".utf8Data
        let events = [
            Event(data: "A.1".utf8Data, metadata: invalidMetadata),
            try Event(data: "B.1", viewMetadata: RUMViewEvent.Metadata(id: "B", documentVersion: 1, duration: nil))
        ]

        let actual = sut.filter(events: events)
        let expected = [
            Event(data: "A.1".utf8Data, metadata: invalidMetadata),
            try Event(data: "B.1", viewMetadata: RUMViewEvent.Metadata(id: "B", documentVersion: 1, duration: nil))
        ]

        XCTAssertEqual(actual, expected)
        XCTAssertEqual(telemetry.messages.count, 1)
        XCTAssertTrue(telemetry.messages.firstError()?.message.contains("Failed to decode RUM view event metadata") == true)
    }

    func testFilterWhenMixedValidAndInvalidMetadata() throws {
        let invalidMetadata = "invalid json".utf8Data
        let events = [
            try Event(data: "A.1", viewMetadata: RUMViewEvent.Metadata(id: "A", documentVersion: 1, duration: nil)),
            Event(data: "B.1".utf8Data, metadata: invalidMetadata),
            try Event(data: "C.1", viewMetadata: RUMViewEvent.Metadata(id: "C", documentVersion: 1, duration: 1)),
            Event(data: "D.1".utf8Data, metadata: invalidMetadata)
        ]

        let actual = sut.filter(events: events)
        let expected = [
            try Event(data: "A.1", viewMetadata: RUMViewEvent.Metadata(id: "A", documentVersion: 1, duration: nil)),
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

extension Event: CustomDebugStringConvertible {
    public var debugDescription: String {
        let dataString = String(data: data, encoding: .utf8) ?? "<Not a string>"
        let metadataString = metadata.map { String(data: $0, encoding: .utf8) ?? "<Not a string>" }
        return dataString + "." + (metadataString ?? "nil")
    }
}
