/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogInternal
import TestUtilities
@testable import DatadogCore

final class UserDefaultsDataStoreTests: XCTestCase {
    private var store: UserDefaultsDataStore! // swiftlint:disable:this implicitly_unwrapped_optional
    private var userDefaults: UserDefaults! // swiftlint:disable:this implicitly_unwrapped_optional
    private let suiteName = "com.datadoghq.datastore.test-suite"

    override func setUp() {
        super.setUp()
        userDefaults = UserDefaults(suiteName: suiteName)
        store = UserDefaultsDataStore(userDefaults: userDefaults)
    }

    override func tearDown() {
        userDefaults.removePersistentDomain(forName: suiteName)
        userDefaults = nil
        store = nil
        super.tearDown()
    }

    // MARK: - Basic Usage

    func testSetAndGetValue() {
        var result: DataStoreValueResult?

        // When
        store.setValue("value".utf8Data, forKey: "key")
        store.value(forKey: "key") { result = $0 }

        // Then
        XCTAssertEqual(result?.data(), "value".utf8Data)
    }

    func testGetNoValue() {
        var result: DataStoreValueResult?

        // When
        store.value(forKey: "missing-key") { result = $0 }

        // Then
        DDAssertReflectionEqual(result, .noValue)
    }

    func testUpdateValue() {
        var result: DataStoreValueResult?

        // When
        store.setValue("value1".utf8Data, forKey: "key")
        store.setValue("value2".utf8Data, forKey: "key")

        // Then
        store.value(forKey: "key") { result = $0 }
        XCTAssertEqual(result?.data(), "value2".utf8Data)
    }

    func testRemoveValue() {
        var result: DataStoreValueResult?

        // When
        store.setValue("value".utf8Data, forKey: "key")
        store.removeValue(forKey: "key")

        // Then
        store.value(forKey: "key") { result = $0 }
        DDAssertReflectionEqual(result, .noValue)
    }

    func testClearAllData() {
        var result1: DataStoreValueResult?
        var result2: DataStoreValueResult?

        // Given
        store.setValue("value1".utf8Data, forKey: "key1")
        store.setValue("value2".utf8Data, forKey: "key2")

        // When
        store.clearAllData()

        // Then
        store.value(forKey: "key1") { result1 = $0 }
        store.value(forKey: "key2") { result2 = $0 }

        DDAssertReflectionEqual(result1, .noValue)
        DDAssertReflectionEqual(result2, .noValue)
    }

    // MARK: - Version Validation

    func testSetValueWithCustomVersion() {
        var result: DataStoreValueResult?

        // When
        store.setValue("value".utf8Data, forKey: "key", version: 42)

        // Then
        store.value(forKey: "key") { result = $0 }

        XCTAssertEqual(result?.data(expectedVersion: 42), "value".utf8Data)
        XCTAssertNil(result?.data(expectedVersion: 41))
        XCTAssertNil(result?.data())
    }

    func testUpdateValueWithDifferentVersion() {
        var result: DataStoreValueResult?

        // When
        store.setValue("value v1".utf8Data, forKey: "key", version: 1)
        store.setValue("value v2".utf8Data, forKey: "key", version: 2)

        // Then
        store.value(forKey: "key") { result = $0 }

        XCTAssertEqual(result?.data(expectedVersion: 2), "value v2".utf8Data)
        XCTAssertNil(result?.data(expectedVersion: 1))
    }

    // MARK: - Suite Isolation

    func testEachSuiteHasIndependentStore() {
        let suiteNameA = "com.datadoghq.test-suite-A"
        let suiteNameB = "com.datadoghq.test-suite-B"

        let storeA = UserDefaultsDataStore(userDefaults: UserDefaults(suiteName: suiteNameA) ?? .standard)
        let storeB = UserDefaultsDataStore(userDefaults: UserDefaults(suiteName: suiteNameB) ?? .standard)

        defer {
            UserDefaults(suiteName: suiteNameA)?.removePersistentDomain(forName: suiteNameA)
            UserDefaults(suiteName: suiteNameB)?.removePersistentDomain(forName: suiteNameB)
        }

        var results: [DataStoreValueResult] = []

        // When
        storeA.setValue("value A".utf8Data, forKey: "key")
        storeB.setValue("value B".utf8Data, forKey: "key")
        storeA.value(forKey: "key") { results.append($0) }
        storeB.value(forKey: "key") { results.append($0) }

        // Then
        XCTAssertEqual(results[0].data(), "value A".utf8Data)
        XCTAssertEqual(results[1].data(), "value B".utf8Data)
    }

    func testDataIsPersistedBetweenDataStoreInstances() {
        // Given
        store.setValue("value".utf8Data, forKey: "key")

        // When
        var result: DataStoreValueResult?
        let nextStoreInstance = UserDefaultsDataStore(userDefaults: UserDefaults(suiteName: suiteName) ?? .standard)
        nextStoreInstance.value(forKey: "key") { result = $0 }

        // Then
        XCTAssertEqual(result?.data(), "value".utf8Data)
    }

    // MARK: - Edge Cases

    func testStoringLargeData() {
        var result: DataStoreValueResult?
        let largeData = Data(repeating: 0xFF, count: 1_024 * 100) // 100KB

        // When
        store.setValue(largeData, forKey: "large-key")
        store.value(forKey: "large-key") { result = $0 }

        // Then
        XCTAssertEqual(result?.data(), largeData)
    }

    func testStoringEmptyData() {
        var result: DataStoreValueResult?

        // When
        store.setValue(Data(), forKey: "empty-data-key")
        store.value(forKey: "empty-data-key") { result = $0 }

        // Then
        XCTAssertEqual(result?.data(), Data())
    }
}
