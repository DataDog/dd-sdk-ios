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
            if let knownIdentifiers = try? JSONEncoder().encode(knownIdentifiers) {
                scope?.dataStore.setValue(
                    knownIdentifiers,
                    forKey: Constants.processedResourcesKey
                )
            }
        }
    }

    init(
        core: DatadogCoreProtocol
    ) {
        self.scope = core.scope(for: ResourcesFeature.name)
        self.telemetry = core.telemetry

        self.scope?.dataStore.value(forKey: Constants.processedResourcesKey) { [weak self] result in
            switch result {
            case .value(let data, _):
                if let knownIdentifiers = try? JSONDecoder().decode(Set<String>.self, from: data) {
                    self?.knownIdentifiers.formUnion(knownIdentifiers)
                }
            case .error(let error):
                self?.telemetry.error("Failed to read processed resources from data store: \(error)")
            case .noValue:
                break
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

    private enum Constants {
        static let processedResourcesKey = "processed-resources"
    }
}
#endif
