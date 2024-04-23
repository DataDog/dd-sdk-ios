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
    private let scope: FeatureScope
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    @ReadWriteLock
    private var knownIdentifiers = Set<String>() {
        didSet {
            if let knownIdentifiers = knownIdentifiers.asData(encoder) {
                scope.dataStore.setValue(
                    knownIdentifiers,
                    forKey: Constants.knownResourcesKey,
                    version: Constants.currentStoreVersion
                )
            }
        }
    }

    init(
        scope: FeatureScope,
        dataStoreResetTime: TimeInterval = TimeInterval(30).days,
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.scope = scope
        self.encoder = encoder
        self.decoder = decoder
        self.scope.dataStore.value(forKey: Constants.storeCreationKey) { [weak self]  result in
            do {
                if let storeCreation = try result.data(expectedVersion: Constants.currentStoreVersion)?.asTimeInterval(),
                   Date().timeIntervalSince1970 - storeCreation < dataStoreResetTime {
                    self?.scope.dataStore.value(forKey: Constants.knownResourcesKey) { result in
                        switch result {
                        case .value(let data, let version) where version == Constants.currentStoreVersion:
                            do {
                                if let knownIdentifiers = try data.asKnownIdentifiers(decoder) {
                                    self?.knownIdentifiers.formUnion(knownIdentifiers)
                                }
                            } catch let error {
                                self?.scope.telemetry.error("Failed to decode known identifiers", error: error)
                            }
                        default:
                            break
                        }
                    }
                } else { // Reset if store was created more than 30 days ago
                    self?.scope.dataStore.setValue(
                        Date().timeIntervalSince1970.asData(),
                        forKey: Constants.storeCreationKey,
                        version: Constants.currentStoreVersion
                    )
                    self?.scope.dataStore.removeValue(forKey: Constants.knownResourcesKey)
                }
            } catch let error {
                self?.scope.telemetry.error("Failed to decode store creation", error: error)
            }
        }
    }

    // MARK: - Writing

    func write(resources: [EnrichedResource]) {
        scope.eventWriteContext { [weak self] _, recordWriter in
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
        static let currentStoreVersion = UInt16(1)
    }
}

extension Data {
    enum SerializationError: Error {
        case invalidData
    }

    func asTimeInterval() throws -> TimeInterval {
        var value: TimeInterval = 0
        guard count >= MemoryLayout.size(ofValue: value) else {
            throw SerializationError.invalidData
        }
        _ = Swift.withUnsafeMutableBytes(of: &value) {
            copyBytes(to: $0)
        }
        return value
    }

    func asKnownIdentifiers(_ decoder: JSONDecoder) throws -> Set<String>? {
        return try decoder.decode(Set<String>.self, from: self)
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
    func asData(_ encoder: JSONEncoder) -> Data? {
        return try? encoder.encode(self) // Never fails
    }
}
#endif
