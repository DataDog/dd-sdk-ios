/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation
import DatadogInternal

/// Publisher that sets Session Replay context for being utilized by other Features.
internal class SRContextPublisher {
    private weak var core: DatadogCoreProtocol?
    private var recordCounts: [String: Int64] = [:]

    init(core: DatadogCoreProtocol) {
        self.core = core
    }

    /// Notifies other Features if Session Replay is recording.
    func setHasReplay(_ value: Bool) {
        core?.set(context: SessionReplayCoreContext.HasReplay(value: value))
    }

    /// Increments the Session Replay record count for a RUM view.
    func incrementRecordCount(by count: Int64, forViewID viewID: String) {
        guard count > 0 else {
            return
        }

        core?.set(
            context: {
                self.recordCounts[viewID, default: 0] += count
                return SessionReplayCoreContext.RecordsCount(value: self.recordCounts)
            }
        )
    }
}
#endif
