/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation
import DatadogInternal

/// Stores identifiers of resources confirmed to be available in the backend for each RUM application.
internal final class ResourceAvailabilityStore: @unchecked Sendable {
    private struct Value: Codable, Equatable {
        var identifiers: [String: Set<String>] = [:]
        let expirationDate: Date
    }

    private struct State {
        var value: Value?
        var isLoaded = false
        var pendingInvalidations: [String: Set<String>] = [:]
    }

    private let scope: FeatureScope
    private let dateProvider: DateProvider

    @ReadWriteLock
    private var state = State()

    init(
        scope: FeatureScope,
        dateProvider: DateProvider = SystemDateProvider()
    ) {
        self.scope = scope
        self.dateProvider = dateProvider

        // Legacy identifiers record local writes without confirming backend availability.
        scope.dataStore.removeValue(forKey: Constants.legacyResourcesKey)
        scope.dataStore.removeValue(forKey: Constants.legacyCreationKey)

        scope.dataStore.value(forKey: Constants.storageKey) { [weak self] result in
            self?.load(result)
        }
    }

    /// Returns whether the resource has an unexpired confirmation for this application.
    func contains(_ identifier: String, forApplicationID applicationID: String) -> Bool {
        guard let value = state.value, value.expirationDate > dateProvider.now else {
            return false
        }
        return value.identifiers[applicationID]?.contains(identifier) ?? false
    }

    /// Returns whether all resources have unexpired confirmations for this application.
    func contains(allOf identifiers: some Sequence<String>, forApplicationID applicationID: String) -> Bool {
        let confirmedIdentifiers: Set<String>
        if let value = state.value, value.expirationDate > dateProvider.now {
            confirmedIdentifiers = value.identifiers[applicationID] ?? []
        } else {
            confirmedIdentifiers = []
        }
        return identifiers.allSatisfy { confirmedIdentifiers.contains($0) }
    }

    /// Records identifiers from a validated reconciliation response.
    func insert(_ identifiers: Set<String>, forApplicationID applicationID: String) {
        guard !identifiers.isEmpty else {
            return
        }

        _state.mutate { state in
            let now = dateProvider.now
            var value: Value
            if let current = state.value, current.expirationDate > now {
                value = current
            } else {
                value = Value(expirationDate: now.addingTimeInterval(Constants.maxAge))
            }
            value.identifiers[applicationID, default: []].formUnion(identifiers)
            state.value = value

            // Wait for the initial read so a new confirmation cannot overwrite entries still being loaded.
            if state.isLoaded {
                save(value)
            }
        }
    }

    /// Removes previous confirmations for these resources in the application.
    func invalidate(_ identifiers: Set<String>, forApplicationID applicationID: String) {
        guard !identifiers.isEmpty else {
            return
        }

        _state.mutate { state in
            state.value?.identifiers[applicationID]?.subtract(identifiers)

            if state.isLoaded {
                save(state.value)
            } else {
                // Prevent the initial read from restoring invalidated confirmations.
                state.pendingInvalidations[applicationID, default: []].formUnion(identifiers)
            }
        }
    }

    private func load(_ result: DataStoreValueResult) {
        let stored: Value?
        do {
            stored = try result.data(expectedVersion: Constants.storeVersion).map {
                try JSONDecoder().decode(Value.self, from: $0)
            }
        } catch {
            scope.telemetry.error("Failed to decode confirmed resource identifiers", error: error)
            stored = nil
        }

        _state.mutate { state in
            let now = dateProvider.now
            var value: Value?
            if let stored, stored.expirationDate > now {
                value = stored
            }
            for (applicationID, identifiers) in state.pendingInvalidations {
                value?.identifiers[applicationID]?.subtract(identifiers)
            }
            if let pending = state.value, pending.expirationDate > now {
                if var loaded = value {
                    for (applicationID, identifiers) in pending.identifiers {
                        loaded.identifiers[applicationID, default: []].formUnion(identifiers)
                    }
                    value = Value(
                        identifiers: loaded.identifiers,
                        expirationDate: min(loaded.expirationDate, pending.expirationDate)
                    )
                } else {
                    value = pending
                }
            }
            state.value = value
            state.pendingInvalidations.removeAll()
            state.isLoaded = true
            if value != stored {
                save(value)
            }
        }
    }

    private func save(_ value: Value?) {
        guard let value else {
            scope.dataStore.removeValue(forKey: Constants.storageKey)
            return
        }

        do {
            let data = try JSONEncoder().encode(value)
            scope.dataStore.setValue(data, forKey: Constants.storageKey, version: Constants.storeVersion)
        } catch {
            scope.telemetry.error("Failed to encode confirmed resource identifiers", error: error)
        }
    }

    private enum Constants {
        static let storageKey = "resource-availability"
        static let storeVersion: DataStoreKeyVersion = 1
        static let maxAge: TimeInterval = 30.days

        static let legacyResourcesKey = "known-resources"
        static let legacyCreationKey = "store-creation"
    }
}
#endif
