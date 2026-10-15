/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation
import Testing
import DatadogInternal
import TestUtilities

@testable import DatadogSessionReplay

@Suite(.datadogTesting)
struct ResourceAvailabilityStoreTests {
    private let scope = FeatureScopeMock()
    private let dateProvider = DateProviderMock(now: Date(timeIntervalSince1970: 1_000))
    private let applicationID = "application"
    private let identifiers: Set<String> = ["first", "second"]
    private let storageKey = "resource-availability"

    @Test("Persists confirmations scoped to each application")
    func persistsConfirmationsScopedToEachApplication() {
        // Given
        let store = ResourceAvailabilityStore(scope: scope, dateProvider: dateProvider)
        store.insert(identifiers, forApplicationID: applicationID)
        store.insert(["other"], forApplicationID: "other-application")

        // When
        let restored = ResourceAvailabilityStore(scope: scope, dateProvider: dateProvider)

        // Then
        for identifier in identifiers {
            #expect(restored.contains(identifier, forApplicationID: applicationID))
            #expect(!restored.contains(identifier, forApplicationID: "other-application"))
        }
        #expect(restored.contains("other", forApplicationID: "other-application"))
        #expect(!restored.contains("other", forApplicationID: applicationID))
    }

    @Test("Requires every identifier to be confirmed for the application")
    func requiresEveryIdentifierToBeConfirmedForTheApplication() {
        // Given
        let store = ResourceAvailabilityStore(scope: scope, dateProvider: dateProvider)
        store.insert(identifiers, forApplicationID: applicationID)

        // When, Then
        #expect(store.contains(allOf: identifiers, forApplicationID: applicationID))
        #expect(!store.contains(allOf: ["first", "missing"], forApplicationID: applicationID))
        #expect(!store.contains(allOf: identifiers, forApplicationID: "other-application"))
    }

    @Test("Expires all applications 30 days after the first confirmation")
    func expiresAllApplications30DaysAfterTheFirstConfirmation() {
        // Given
        let store = ResourceAvailabilityStore(scope: scope, dateProvider: dateProvider)
        store.insert([], forApplicationID: applicationID)
        dateProvider.now.addTimeInterval(10.days)
        store.insert(identifiers, forApplicationID: applicationID)
        let expiration = dateProvider.now.addingTimeInterval(30.days)
        dateProvider.now = expiration.addingTimeInterval(-1)
        store.insert(["recent"], forApplicationID: "other-application")
        #expect(store.contains("first", forApplicationID: applicationID))
        #expect(store.contains(allOf: identifiers, forApplicationID: applicationID))

        // When
        dateProvider.now = expiration
        let restored = ResourceAvailabilityStore(scope: scope, dateProvider: dateProvider)

        // Then
        #expect(!store.contains("first", forApplicationID: applicationID))
        #expect(!store.contains(allOf: identifiers, forApplicationID: applicationID))
        #expect(!store.contains("recent", forApplicationID: "other-application"))
        #expect(!restored.contains("first", forApplicationID: applicationID))
        #expect(scope.dataStoreMock.storage[storageKey] == nil)
    }

    @Test("Starts a fresh expiration window after the previous value expires")
    func startsAFreshExpirationWindowAfterThePreviousValueExpires() {
        // Given
        let store = ResourceAvailabilityStore(scope: scope, dateProvider: dateProvider)
        store.insert(identifiers, forApplicationID: applicationID)
        dateProvider.now.addTimeInterval(30.days)
        let expiration = dateProvider.now.addingTimeInterval(30.days)

        // When
        store.insert(["new"], forApplicationID: "other-application")
        let restored = ResourceAvailabilityStore(scope: scope, dateProvider: dateProvider)

        // Then
        #expect(!restored.contains("first", forApplicationID: applicationID))
        dateProvider.now = expiration.addingTimeInterval(-1)
        #expect(restored.contains("new", forApplicationID: "other-application"))
        dateProvider.now = expiration
        #expect(!restored.contains("new", forApplicationID: "other-application"))
    }

    @Test(
        "Recovers from unreadable or incompatible stored values",
        arguments: [
            DataStoreValueResult.error(ErrorMock()),
            .value(Data("broken".utf8), 1),
            .value(Data(#"{"identifiers":{"application":["first"]},"expirationDate":0}"#.utf8), 2)
        ]
    )
    func recoversFromUnreadableOrIncompatibleStoredValues(storedValue: DataStoreValueResult) {
        // Given
        scope.dataStoreMock.storage[storageKey] = storedValue
        let store = ResourceAvailabilityStore(scope: scope, dateProvider: dateProvider)
        #expect(!store.contains("first", forApplicationID: applicationID))

        // When
        store.insert(identifiers, forApplicationID: applicationID)
        let restored = ResourceAvailabilityStore(scope: scope, dateProvider: dateProvider)

        // Then
        for identifier in identifiers {
            #expect(restored.contains(identifier, forApplicationID: applicationID))
        }
    }

    @Test(
        "Preserves confirmations received while loading",
        arguments: [
            (age: 29.days, keepsStoredIdentifiers: true, remainingLifetime: 1.days),
            (age: 30.days, keepsStoredIdentifiers: false, remainingLifetime: 30.days)
        ]
    )
    func preservesConfirmationsReceivedWhileLoading(
        age: TimeInterval,
        keepsStoredIdentifiers: Bool,
        remainingLifetime: TimeInterval
    ) throws {
        // Given
        let persisted = ResourceAvailabilityStore(scope: scope, dateProvider: dateProvider)
        persisted.insert(identifiers, forApplicationID: applicationID)
        let storedData = try #require(scope.dataStoreMock.storage[storageKey]?.data())
        dateProvider.now.addTimeInterval(age)
        let expiration = dateProvider.now.addingTimeInterval(remainingLifetime)
        let dataStore = DataStoreAsyncMock(storage: scope.dataStoreMock.storage)
        let asyncScope = FeatureScopeMock(dataStore: dataStore)
        let releaseLoad = DispatchSemaphore(value: 0)
        defer { releaseLoad.signal() }
        dataStore.value(forKey: "hold-loading") { _ in releaseLoad.wait() }
        let store = ResourceAvailabilityStore(scope: asyncScope, dateProvider: dateProvider)

        // When
        store.insert(["new"], forApplicationID: applicationID)
        #expect(store.contains("new", forApplicationID: applicationID))
        #expect(dataStore.storage[storageKey]?.data() == storedData)
        releaseLoad.signal()
        dataStore.flush()
        let restored = ResourceAvailabilityStore(scope: asyncScope, dateProvider: dateProvider)
        dataStore.flush()

        // Then
        for identifier in identifiers {
            #expect(restored.contains(identifier, forApplicationID: applicationID) == keepsStoredIdentifiers)
        }
        dateProvider.now = expiration.addingTimeInterval(-1)
        #expect(restored.contains("new", forApplicationID: applicationID))
        dateProvider.now = expiration
        #expect(!store.contains("new", forApplicationID: applicationID))
        #expect(!restored.contains("new", forApplicationID: applicationID))
    }

    @Test("Preserves concurrent confirmations in memory and persistent storage")
    func preservesConcurrentConfirmationsInMemoryAndPersistentStorage() {
        // Given
        let identifiers = (0..<50).map(String.init)
        let dataStore = DataStoreAsyncMock()
        let scope = FeatureScopeMock(dataStore: dataStore)
        let store = ResourceAvailabilityStore(scope: scope, dateProvider: dateProvider)
        dataStore.flush()

        // When
        DispatchQueue.concurrentPerform(iterations: identifiers.count) { index in
            store.insert([identifiers[index]], forApplicationID: applicationID)
        }
        let restored = ResourceAvailabilityStore(scope: scope, dateProvider: dateProvider)
        dataStore.flush()

        // Then
        for identifier in identifiers {
            #expect(store.contains(identifier, forApplicationID: applicationID))
            #expect(restored.contains(identifier, forApplicationID: applicationID))
        }
    }
}
#endif
