/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// A type turning succeeding `ViewTreeSnapshots` into sequence of Mobile Session Replay records.
///
/// This is the actual brain of Session Replay. Based on the sequence of snapshots it receives, it computes the sequence
/// of records that will to be send to SR BE. It implements the logic of reducing snapshots into Full or Incremental
/// mutation records.
///
/// More things can come in:
/// - TODO: RUMM-2272 Implement SR Processor
internal protocol ViewTreeSnapshotProcessor {
    /// Accepts next `ViewTreeSnapshot`
    /// - Parameter snapshot: the `ViewTreeSnapshot`
    func process(snapshot: ViewTreeSnapshot)
}
