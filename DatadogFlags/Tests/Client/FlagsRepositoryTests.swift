/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal

@testable import DatadogFlags

final class FlagsRepositoryTests: XCTestCase {
    private let featureScope = FeatureScopeMock()

    func testInitAndReset() throws {
        // Given
        let initialState = FlagsData(
            flags: ["test": .mockAny()],
            context: .mockAny(),
            date: .mockAny()
        )
        try featureScope.dataStoreMock.setValue(
            JSONEncoder().encode(initialState),
            forKey: .mockAny()
        )

        // When
        let flagsRepository = FlagsRepository(
            clientName: .mockAny(),
            featureScope: featureScope
        )
        featureScope.dataStore.flush()

        // Then
        XCTAssertEqual(flagsRepository.context, .mockAny())
        XCTAssertEqual(flagsRepository.flagAssignment(for: "test"), .mockAny())

        // When
        flagsRepository.reset()
        featureScope.dataStore.flush()

        // Then
        XCTAssertNil(flagsRepository.context)
        XCTAssertNil(flagsRepository.flagAssignment(for: "test"))
        XCTAssertTrue(featureScope.dataStoreMock.storage.isEmpty)
    }

    func testSetFlagAssignments() throws {
        // Given
        let flagsRepository = FlagsRepository(
            clientName: .mockAny(),
            featureScope: featureScope
        )
        let state = FlagsData(
            flags: ["test": .mockAny()],
            context: .mockAny(),
            date: .mockAny()
        )

        // When
        flagsRepository.setFlagAssignments(
            state.flags,
            for: state.context,
            date: state.date
        )
        featureScope.dataStore.flush()

        // Then
        XCTAssertEqual(flagsRepository.context, .mockAny())
        XCTAssertEqual(flagsRepository.flagAssignment(for: "test"), .mockAny())

        let data = try XCTUnwrap(featureScope.dataStoreMock.storage[.mockAny()]?.data())
        let storedState = try JSONDecoder().decode(FlagsData.self, from: data)

        XCTAssertEqual(storedState, state)
    }
}
