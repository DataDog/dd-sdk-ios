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
    private let TASK_VM_INFO_COUNT = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    private let TASK_VM_INFO_REV1_COUNT = mach_msg_type_number_t((MemoryLayout.offset(of: \task_vm_info_data_t.min_address) ?? 0) / MemoryLayout<integer_t>.size)

    func readMemory() -> TimeseriesMemoryValues? {
        var info = task_vm_info_data_t()
        var count = TASK_VM_INFO_COUNT
        let kernelReturn = withUnsafeMutablePointer(to: &info) { infoPtr in
            infoPtr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), intPtr, &count)
            }
        }

        guard kernelReturn == KERN_SUCCESS, count >= TASK_VM_INFO_REV1_COUNT else {
            return nil
        }

        return TimeseriesMemoryValues(footprint: Double(info.phys_footprint), nonResident: Double(info.compressed))
    }
}
