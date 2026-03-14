/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogInternal
import TestUtilities
@testable import DatadogCore

class FeatureDataStoreTests: XCTestCase {
    private var store: FeatureDataStore! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUp() {
        temporaryCoreDirectory.create()
        store = FeatureDataStore(
            feature: "feature",
            directory: temporaryCoreDirectory,
            telemetry: TelemetryMock()
        )
    }

    override func tearDown() {
        temporaryCoreDirectory.delete()
    }

    // MARK: - Basic Usage

    func testSetAndGetValue() async {
        // When
        store.setValue("value".utf8Data, forKey: "key")
        store.flush()
        let result = await store.value(forKey: "key")

        // Then
        DDAssertReflectionEqual(result, .value("value".utf8Data, dataStoreDefaultKeyVersion))
        XCTAssertEqual(result.data(), "value".utf8Data)
    }

    func testGetNoValue() async {
        // When
        let result = await store.value(forKey: "missing-key")

        DDAssertReflectionEqual(result, .noValue)
    }

    func testUpdateValue() async {
        // When
        store.setValue("value1".utf8Data, forKey: "key")
        store.setValue("value2".utf8Data, forKey: "key")
        store.flush()

        // Then
        let result = await store.value(forKey: "key")
        XCTAssertEqual(result.data(), "value2".utf8Data)
    }

    func testRemoveValue() async {
        // When
        store.setValue("value".utf8Data, forKey: "key")
        store.removeValue(forKey: "key")
        store.flush()

        // Then
        let result = await store.value(forKey: "key")
        DDAssertReflectionEqual(result, .noValue)
    }

    // MARK: - Version Validation

    func testSetValueWithCustomVersion() async {
        // When
        store.setValue("value".utf8Data, forKey: "key", version: 42)
        store.flush()

        // Then
        let result = await store.value(forKey: "key")
        DDAssertReflectionEqual(result, .value("value".utf8Data, 42))
        XCTAssertEqual(result.data(expectedVersion: 42), "value".utf8Data, "It must return data in expected version")
        XCTAssertNil(result.data(expectedVersion: 41), "It must return no data in wrong version")
        XCTAssertNil(result.data(), "It must return no data in default version")
    }

    func testUpdateValueWithDifferentVersion() async {
        // When
        store.setValue("value v1".utf8Data, forKey: "key", version: 1)
        store.setValue("value v2".utf8Data, forKey: "key", version: 2)
        store.flush()

        // Then
        let result = await store.value(forKey: "key")
        DDAssertReflectionEqual(result, .value("value v2".utf8Data, 2))
        XCTAssertEqual(result.data(expectedVersion: 2), "value v2".utf8Data, "It must return data in expected version")
        XCTAssertNil(result.data(expectedVersion: 1), "It must return no data in wrong version")
    }

    // MARK: - Persistence

    func testWhenValueIsSet_thenDirectoryIsLazilyCreated() {
        // Given
        XCTAssertNil(directory(for: store), "The directory must not be created by default")

        // When
        store.setValue("value".utf8Data, forKey: "key")
        store.flush()

        // Then
        XCTAssertNotNil(directory(for: store), "The directory must be created after a value is set")
    }

    func testGivenNoDirectory_whenValueIsRetrieved_thenDirectoryIsNotCreated() async {
        // Given
        XCTAssertNil(directory(for: store), "The directory must not be created by default")

        // When
        _ = await store.value(forKey: "key")

        // Then
        XCTAssertNil(directory(for: store), "The directory must not be created after a value is retrieved")
    }

    func testGivenNoDirectory_whenValueIsRemovedd_thenDirectoryIsNotCreated() {
        // Given
        XCTAssertNil(directory(for: store), "The directory must not be created by default")

        // When
        store.removeValue(forKey: "key")
        store.flush()

        // Then
        XCTAssertNil(directory(for: store), "The directory must not be created after a value is removed")
    }

    func testEachFeatureHasIndependentStore() async {
        let storeA = FeatureDataStore(
            feature: "featureA",
            directory: temporaryCoreDirectory,
            telemetry: TelemetryMock()
        )
        let storeB = FeatureDataStore(
            feature: "featureB",
            directory: temporaryCoreDirectory,
            telemetry: TelemetryMock()
        )

        // When
        storeA.setValue("value A".utf8Data, forKey: "key")
        storeB.setValue("value B".utf8Data, forKey: "key")
        storeA.flush()
        storeB.flush()

        let resultA = await storeA.value(forKey: "key")
        let resultB = await storeB.value(forKey: "key")

        // Then
        DDAssertReflectionEqual(resultA.data(), "value A".utf8Data)
        DDAssertReflectionEqual(resultB.data(), "value B".utf8Data)
    }

    func testDataIsPersistedBetweenDataStoreInstances() async {
        // Given
        store.setValue("value".utf8Data, forKey: "key")
        store.flush()

        // When
        let nextStoreInstance = FeatureDataStore(
            feature: "feature",
            directory: temporaryCoreDirectory,
            telemetry: TelemetryMock()
        )
        let result = await nextStoreInstance.value(forKey: "key")

        // Then
        DDAssertReflectionEqual(result.data(), "value".utf8Data)
    }

    // MARK: - Error Handling

    func testWhenSettingTooLargeValue_itSendsTelemetry() throws {
        let telemetry = TelemetryMock()

        // Given
        let store = FeatureDataStore(
            feature: "feature",
            directory: temporaryCoreDirectory,
            telemetry: telemetry
        )

        // When
        let limit = maxTLVDataLength
        store.setValue(.mock(ofSize: limit + 1), forKey: "key")
        store.flush()

        // Then
        let error = try XCTUnwrap(telemetry.messages.firstError())
        XCTAssertTrue(error.message.hasPrefix("[Data Store] Error on setting `key` value for `feature`"))
        XCTAssertTrue(error.message.contains("failedToEncodeData(DataBlock with \(limit + 1) bytes exceeds limit of \(limit) bytes)"))
    }

    func testWhenGettingMalformedValue_itSendsTelemetry() async throws {
        let telemetry = TelemetryMock()

        // Given
        let store = FeatureDataStore(
            feature: "feature",
            directory: temporaryCoreDirectory,
            telemetry: telemetry
        )
        store.setValue("foo".utf8Data, forKey: "key")
        store.flush()

        // When (malform the file, then read value)
        let file = try XCTUnwrap(directory(for: store)?.files().first(where: { $0.name == "key" }))
        try file.write(data: .mockRandom(ofSize: 10))
        let result = await store.value(forKey: "key")

        // Then
        guard case .error = result else {
            XCTFail("Expected error, received \(String(describing: result))")
            return
        }
        let error = try XCTUnwrap(telemetry.messages.firstError())
        XCTAssertTrue(error.message.hasPrefix("[Data Store] Error on getting `key` value for `feature`"))
    }

    // MARK: - Helpers

    /// Returns the underlying FS directory for given store or `nil` if it doesn't exist.
    private func directory(for store: FeatureDataStore) -> Directory? {
        try? temporaryCoreDirectory.coreDirectory.subdirectory(path: store.directoryPath)
    }
}
