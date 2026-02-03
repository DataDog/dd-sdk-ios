/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal

@_spi(Internal)
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
            flagAssignmentsFetcher: FlagAssignmentsFetcherMock(),
            dateProvider: DateProviderMock(),
            featureScope: featureScope
        )
        featureScope.dataStore.flush()

        // Then
        XCTAssertEqual(flagsRepository.clientName, .mockAny())
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

    func testSetEvaluationContext() throws {
        // Given
        let evaluationContext = FlagsEvaluationContext.mockAny()
        let flags = ["test": FlagAssignment.mockAny()]
        let dateProvider = DateProviderMock(now: .mockAny())
        let flagsRepository = FlagsRepository(
            clientName: .mockAny(),
            flagAssignmentsFetcher: FlagAssignmentsFetcherMock { _, completion in
                completion(.success(flags))
            },
            dateProvider: dateProvider,
            featureScope: featureScope
        )
        let completed = expectation(description: "completed")

        // When
        var capturedResult: Result<Void, FlagsError>?
        flagsRepository.setEvaluationContext(evaluationContext) { result in
            capturedResult = result
            completed.fulfill()
        }

        // Then
        waitForExpectations(timeout: 0)

        XCTAssertNotNil(capturedResult)
        XCTAssertNoThrow(try capturedResult?.get())

        XCTAssertEqual(flagsRepository.context, .mockAny())
        XCTAssertEqual(flagsRepository.flagAssignment(for: "test"), .mockAny())

        let data = try XCTUnwrap(featureScope.dataStoreMock.storage[.mockAny()]?.data())
        let storedState = try JSONDecoder().decode(FlagsData.self, from: data)

        XCTAssertEqual(
            storedState,
            FlagsData(
                flags: flags,
                context: evaluationContext,
                date: dateProvider.now
            )
        )
    }

    func testSetEvaluationContextError() throws {
        // Given
        let flagsRepository = FlagsRepository(
            clientName: .mockAny(),
            flagAssignmentsFetcher: FlagAssignmentsFetcherMock { _, completion in
                completion(.failure(.invalidResponse))
            },
            dateProvider: DateProviderMock(),
            featureScope: featureScope
        )
        let completed = expectation(description: "completed")

        // When
        var capturedResult: Result<Void, FlagsError>?
        flagsRepository.setEvaluationContext(.mockAny()) { result in
            capturedResult = result
            completed.fulfill()
        }

        // Then
        waitForExpectations(timeout: 0)

        XCTAssertNotNil(capturedResult)
        XCTAssertThrowsError(try capturedResult?.get())
        XCTAssertNil(flagsRepository.context)
        XCTAssertNil(flagsRepository.flagAssignment(for: "test"))
    }
}
