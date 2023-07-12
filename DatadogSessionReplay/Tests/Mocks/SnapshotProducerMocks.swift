/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
@testable import DatadogSessionReplay

// MARK: - `ViewTreeSnapshotProducer` Mocks

internal class ViewTreeSnapshotProducerMock: ViewTreeSnapshotProducer {
    enum TakeSnapshotResult {
        case snapshot(ViewTreeSnapshot)
        case error(Error)
    }

    /// Succeding results for each `takeSnapshot()`.
    var succeedingResults: [TakeSnapshotResult]

    convenience init(succeedingSnapshots: [ViewTreeSnapshot]) {
        self.init(succeedingResults: succeedingSnapshots.map { .snapshot($0) })
    }

    convenience init(succeedingErrors: [Error]) {
        self.init(succeedingResults: succeedingErrors.map { .error($0) })
    }

    init(succeedingResults: [TakeSnapshotResult]) {
        self.succeedingResults = succeedingResults
    }

    func takeSnapshot(with context: Recorder.Context) throws -> ViewTreeSnapshot? {
        guard let result = succeedingResults.isEmpty ? nil : succeedingResults.removeFirst() else {
            return nil
        }
        switch result {
        case .snapshot(let snapshot): return snapshot
        case .error(let error): throw error
        }
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
