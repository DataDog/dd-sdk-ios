/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation

/// Produces `TouchSnapshots` that describe touch interactions.
internal protocol TouchSnapshotProducer {
    /// Produces the snapshot of (touch) interactions that happened since last call to `takeSnapshot()`.
    ///
    /// - Parameter context: context of the recorder used for sharing common data
    /// - Returns: the snapshot or `nil` if no new touch information is available
    func takeSnapshot(context: Recorder.Context) -> TouchSnapshot?
}
#endif
