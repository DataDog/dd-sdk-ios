/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation
import DatadogInternal

/// A type writing Session Replay records to `DatadogCore`.
internal protocol ResourcesWriting {
    /// Writes next records to SDK core.
    func write(resources: [EnrichedResource])
}

internal class ResourcesWriter: ResourcesWriting {
    /// An instance of SDK core the SR feature is registered to.
    private let scope: FeatureScope?
    private let telemetry: Telemetry

    @ReadWriteLock
    private var knownIdentifiers = Set<String>() {
        didSet {
            if let knownIdentifiers = knownIdentifiers.asData() {
                scope?.dataStore.setValue(
                    knownIdentifiers,
                    forKey: Constants.knownResourcesKey
                )
            }
        }
    }

    init(
        core: DatadogCoreProtocol,
        dataStoreResetTime: TimeInterval = TimeInterval(30).days
    ) {
        self.scope = core.scope(for: ResourcesFeature.self)
        self.telemetry = core.telemetry

        self.scope?.dataStore.value(forKey: Constants.storeCreationKey) { result in
            if let storeCreation = result.data()?.asTimeInterval(), Date().timeIntervalSince1970 - storeCreation < dataStoreResetTime {
                self.scope?.dataStore.value(forKey: Constants.knownResourcesKey) { [weak self] result in
                    switch result {
                    case .value(let data, _):
                        if let knownIdentifiers = data.asKnownIdentifiers() {
                            self?.knownIdentifiers.formUnion(knownIdentifiers)
                        }
                    case .error(let error):
                        self?.telemetry.error("Failed to read processed resources from data store: \(error)")
                    case .noValue:
                        break
                    }
                }
            } else { // Reset if store was created more than 30 days ago
                self.scope?.dataStore.setValue(
                    Date().timeIntervalSince1970.asData(),
                    forKey: Constants.storeCreationKey
                )
                self.scope?.dataStore.removeValue(forKey: Constants.knownResourcesKey)
            }
        }
    }

    // MARK: - Writing

    func write(resources: [EnrichedResource]) {
        scope?.eventWriteContext { [weak self] _, recordWriter in
            let unknownResources = resources.filter { self?.knownIdentifiers.contains($0.identifier) == false }
            for resource in unknownResources {
                recordWriter.write(value: resource)
            }
            self?.knownIdentifiers.formUnion(Set(unknownResources.map { $0.identifier }))
        }
    }

    enum Constants {
        static let knownResourcesKey = "known-resources"
        static let storeCreationKey = "store-creation"
    }
}

extension Data {
    func asTimeInterval() -> TimeInterval? {
        var value: TimeInterval = 0
        guard count >= MemoryLayout.size(ofValue: value) else {
            return nil
        }
        _ = Swift.withUnsafeMutableBytes(of: &value) {
            copyBytes(to: $0)
        }
        return value
    }

    func asKnownIdentifiers() -> Set<String>? {
        return try? JSONDecoder().decode(Set<String>.self, from: self)
    }
}

extension TimeInterval {
    func asData() -> Data {
        return Swift.withUnsafeBytes(of: self) {
            Data($0)
        }
    }
}

extension Set<String> {
    func asData() -> Data? {
        return try? JSONEncoder().encode(self)
    }
}
#endif
