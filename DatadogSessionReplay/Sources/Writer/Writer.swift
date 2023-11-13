/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation
import DatadogInternal

/// A type writing Session Replay records to `DatadogCore`.
internal protocol Writing {
    /// Connects writer to SDK core.
    func startWriting(to core: DatadogCoreProtocol)

    /// Writes next records to SDK core.
    func write(nextRecord: EnrichedRecord)

    /// Writes resource to SDK core.
    func write(resource: EncodableResource)
}

internal class Writer: Writing {
    /// An instance of SDK core the SR feature is registered to.
    private weak var core: DatadogCoreProtocol?

    /// The `viewID`  of last group of records written to core. If that ID changes, we request the core
    /// to write new events to separate batch, so we receive them separately in `RequestBuilder`.
    ///
    /// This is to fulfill the SR payload requirement that each view needs to be send in separate segment.
    private var lastViewID: String?

    // MARK: - Writing

    func startWriting(to core: DatadogCoreProtocol) {
        self.core = core
    }

    func write(nextRecord: EnrichedRecord) {
        let forceNewBatch = lastViewID != nextRecord.viewID
        lastViewID = nextRecord.viewID

        guard let scope = core?.scope(for: SessionReplayFeature.name) else {
            return
        }

        scope.eventWriteContext(bypassConsent: false, forceNewBatch: forceNewBatch) { _, writer in
            writer.write(value: nextRecord)
        }
    }

    func write(resource: EncodableResource) {
        guard let scope = core?.scope(for: ResourcesFeature.name) else {
            return
        }

        scope.eventWriteContext(bypassConsent: false, forceNewBatch: false) { _, writer in
            writer.write(value: resource)
        }
    }
}
#endif
