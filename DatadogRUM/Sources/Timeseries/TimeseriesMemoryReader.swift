/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Memory values sampled for a memory timeseries data point, in bytes.
internal struct TimeseriesMemoryValues {
    /// Memory charged to the process (`phys_footprint`), including pages the system has compressed.
    let footprint: Double
    /// Portion of `footprint` that the system has compressed.
    let nonResident: Double
}

/// Reads the memory values reported in memory timeseries events.
internal protocol TimeseriesMemoryReader {
    /// - Returns: Current memory values, `nil` if failed to read.
    func readMemory() -> TimeseriesMemoryValues?
}

/// Reads `phys_footprint` and `compressed` from `task_info(TASK_VM_INFO)` in a single call.
internal final class TaskVMInfoMemoryReader: TimeseriesMemoryReader {
    func readMemory() -> TimeseriesMemoryValues? {
        return VitalMemoryReader.readTaskVMInfo().map {
            TimeseriesMemoryValues(footprint: Double($0.phys_footprint), nonResident: Double($0.compressed))
        }
    }
}
