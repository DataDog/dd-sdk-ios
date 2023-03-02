/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import Datadog

/// A type writing Session Replay records to `DatadogCore`.
internal protocol Writing {
    /// Connects writer to the `FeatureScope` managed by `DatadogCore`.
    func startWriting(to featureScope: FeatureScope)

    /// Writes next records to `DatadogCore`.
    func write(nextRecord: EnrichedRecord)
}

internal class Writer: Writing {
    /// The `FeatureScope` created for Session Replay and managed by `DatadogCore`.
    ///
    /// The thread-safety of this property is guaranteed by convention:
    /// - it is set right after registration of Session Replay Feature in `DatadogCore`,
    /// - it is then frequently accessed from `Processor` thread only after SR is started.
    ///
    /// Because SR is started after SF Feature gets registered, no other thread-safety measures are required.
    private var scope: FeatureScope?

    /// The `viewID`  of last group of records written to core. If that ID changes, we request the core
    /// to write new events to separate batch, so we receive them separately in `RequestBuilder`.
    ///
    /// This is to fulfill the SR payload requirement that each view needs to be send in separate segment.
    private var lastViewID: String?

    // MARK: - Writing

    func startWriting(to featureScope: FeatureScope) {
        scope = featureScope
    }

    func write(nextRecord: EnrichedRecord) {
        let forceNewBatch = lastViewID != nextRecord.viewID
        lastViewID = nextRecord.viewID

        scope?.eventWriteContext(bypassConsent: false, forceNewBatch: forceNewBatch) { _, writer in
            writer.write(value: nextRecord)
        }
    }
}
