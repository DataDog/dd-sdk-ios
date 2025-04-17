/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation
@testable import DatadogSessionReplay

/// Spies the interaction with `Processing`.
public class SnapshotProcessorSpy: SnapshotProcessing {
    /// An array of snapshots recorded in `process(viewTreeSnapshot:touchSnapshot:)`
    public private(set) var processedSnapshots: [(viewTreeSnapshot: ViewTreeSnapshot, touchSnapshot: TouchSnapshot?)] = []

    public init() {}

    public func process(viewTreeSnapshot: ViewTreeSnapshot, touchSnapshot: TouchSnapshot?) {
        processedSnapshots.append((viewTreeSnapshot, touchSnapshot))
    }
}
#endif
