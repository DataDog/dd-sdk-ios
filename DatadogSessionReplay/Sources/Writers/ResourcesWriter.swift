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

    /// Identifiers scheduled for writing during this feature's lifetime.
    private var scheduledIdentifiers = Set<String>()

    init(scope: FeatureScope) {
        self.scope = scope

        scope.dataStore.removeValue(forKey: Constants.legacyResourcesKey)
        scope.dataStore.removeValue(forKey: Constants.legacyCreationKey)
    }

    // MARK: - Writing

    func write(resources: [EnrichedResource]) {
        scope.eventWriteContext { [weak self] _, recordWriter in
            guard let self = self else {
                return
            }

            for resource in resources {
                guard self.scheduledIdentifiers.insert(resource.identifier).inserted else {
                    continue
                }
                recordWriter.write(value: resource)
            }
        }
    }

    private enum Constants {
        static let legacyResourcesKey = "known-resources"
        static let legacyCreationKey = "store-creation"
    }
}
#endif
