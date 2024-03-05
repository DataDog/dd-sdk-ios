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

    init(core: DatadogCoreProtocol) {
        self.core = core
    }

    /// Notifies other Features if Session Replay is recording.
    func setHasReplay(_ value: Bool) {
        core?.set(baggage: value, forKey: RUMDependency.hasReplay)
    }

    /// Notifies other Features on the state of Session Replay records count.
    func setRecordsCountByViewID(_ value: [String: Int]) {
        core?.set(baggage: value, forKey: RUMDependency.recordsCountByViewID)
    }
}
#endif
