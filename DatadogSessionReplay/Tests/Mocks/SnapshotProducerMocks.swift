/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
@testable import DatadogSessionReplay

// MARK: - `ViewTreeSnapshotProducer` Mocks

internal class ViewTreeSnapshotProducerMock: ViewTreeSnapshotProducer {
    /// Succeding snapshots to return for each `takeSnapshot()`.
    var succeedingSnapshots: [ViewTreeSnapshot]

    init(succeedingSnapshots: [ViewTreeSnapshot]) {
        self.succeedingSnapshots = succeedingSnapshots
    }

    func takeSnapshot(with context: Recorder.Context) throws -> ViewTreeSnapshot? {
        return succeedingSnapshots.isEmpty ? nil : succeedingSnapshots.removeFirst()
    }
}

internal class ViewTreeSnapshotProducerSpy: ViewTreeSnapshotProducer {
    /// Succeeding `context` values passed to `takeSnapshot(with:)`.
    var succeedingContexts: [Recorder.Context] = []

    func takeSnapshot(with context: Recorder.Context) throws -> ViewTreeSnapshot? {
        succeedingContexts.append(context)
        return nil
    }
}

// MARK: - `TouchSnapshotProducer` Mocks

internal class TouchSnapshotProducerMock: TouchSnapshotProducer {
    /// Succeding snapshots to return for each `takeSnapshot()`.
    var succeedingSnapshots: [TouchSnapshot]

    init(succeedingSnapshots: [TouchSnapshot] = []) {
        self.succeedingSnapshots = succeedingSnapshots
    }

    func takeSnapshot(context: Recorder.Context) -> TouchSnapshot? {
        return succeedingSnapshots.isEmpty ? nil : succeedingSnapshots.removeFirst()
    }
}
