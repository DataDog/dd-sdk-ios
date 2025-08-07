/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// A class reading the current Memory footprint.
internal class VitalMemoryReader: SamplingBasedVitalReader {
    private let TASK_VM_INFO_COUNT = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    private let TASK_VM_INFO_REV1_COUNT = mach_msg_type_number_t((MemoryLayout.offset(of: \task_vm_info_data_t.min_address) ?? 0) / MemoryLayout<integer_t>.size)

    /// The logic to capture the current physical memory usage is based on the https://developer.apple.com/forums/thread/105088 thread.
    /// It collects the recommended `phys_footprint` value.
    ///
    /// - Returns: Current physical memory usage in bytes, `nil` if failed to read.
    func readVitalData() -> Double? {
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

        return Double(info.phys_footprint)
    }
}
