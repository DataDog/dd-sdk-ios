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
    private weak var core: DatadogCoreProtocol?

    init(
        core: DatadogCoreProtocol
    ) {
        self.core = core
    }

    // MARK: - Writing

    func write(resources: [EnrichedResource]) {
        guard let scope = core?.scope(for: ResourcesFeature.self) else {
            return
        }
        scope.eventWriteContext { _, recordWriter in
            resources.forEach {
                recordWriter.write(value: $0)
            }
        }
    }
}
#endif
