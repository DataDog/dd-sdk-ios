/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class DataProcessorTests: XCTestCase {
    private struct EventMock: Encodable, Equatable {
        let value: String
    }

    func testGivenDataProcessorWithEventMapper_whenEventIsModified_itWritesModifiedEvent() {
        let originalEvent = EventMock(value: "original-event")
        let modifiedEvent = EventMock(value: "modified-event")

        let eventMapper = EventMapperMock(mappedEvent: modifiedEvent)
        let writer = FileWriterMock()

        // Given
        let processor = DataProcessor(fileWriter: writer, eventMapper: eventMapper)

        // When
        processor.write(value: originalEvent)

        // Then
        XCTAssertEqual(writer.dataWritten as? EventMock, modifiedEvent)
    }

    func testGivenDataProcessorWithEventMapper_whenEventIsDropped_itDoesNotWriteAnything() {
        let originalEvent = EventMock(value: "original-event")

        let eventMapper = EventMapperMock(mappedEvent: nil)
        let writer = FileWriterMock()

        // Given
        let processor = DataProcessor(fileWriter: writer, eventMapper: eventMapper)

        // When
        processor.write(value: originalEvent)

        // Then
        XCTAssertNil(writer.dataWritten)
    }

    func testGivenDataProcessorWithNoEventMapper_whenProcessingEvent_itWritesOriginalEvent() {
        let originalEvent = EventMock(value: "original-event")
        let writer = FileWriterMock()

        // Given
        let processor = DataProcessor(fileWriter: writer, eventMapper: nil)

        // When
        processor.write(value: originalEvent)

        // Then
        XCTAssertEqual(writer.dataWritten as? EventMock, originalEvent)
    }
}
