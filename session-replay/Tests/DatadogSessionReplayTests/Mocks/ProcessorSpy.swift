/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
@testable import DatadogSessionReplay

/// Spies the interaction with `Processing`.
internal class ProcessorSpy: Processing {
    /// An array of snapshots recorded in `process(viewTreeSnapshot:touchSnapshot:)`
    private(set) var processedSnapshots: [(viewTreeSnapshot: ViewTreeSnapshot, touchSnapshot: TouchSnapshot?)] = []

    func process(viewTreeSnapshot: ViewTreeSnapshot, touchSnapshot: TouchSnapshot?) {
        processedSnapshots.append((viewTreeSnapshot, touchSnapshot))
    }
}
