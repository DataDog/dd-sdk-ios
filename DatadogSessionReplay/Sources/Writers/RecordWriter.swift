/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation
import DatadogInternal

/// A type writing Session Replay records to `DatadogCore`.
internal protocol RecordWriting {
    /// Writes next records to SDK core.
    func write(nextRecord: EnrichedRecord)
}

internal class RecordWriter: RecordWriting {
    /// An instance of SDK core the SR feature is registered to.
    private weak var core: DatadogCoreProtocol?

    init(core: DatadogCoreProtocol) {
        self.core = core
    }

    // MARK: - Writing

    func write(nextRecord: EnrichedRecord) {
        core?.scope(for: SessionReplayFeature.name)?.eventWriteContext { _, recordWriter in
            recordWriter.write(value: nextRecord)
        }
    }
}
#endif
