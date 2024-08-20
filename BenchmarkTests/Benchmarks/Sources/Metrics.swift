/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

// The `TASK_VM_INFO_COUNT` and `TASK_VM_INFO_REV1_COUNT` macros are too
// complex for the Swift C importer, so we have to define them ourselves.
let TASK_VM_INFO_COUNT = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
let TASK_VM_INFO_REV1_COUNT = mach_msg_type_number_t(MemoryLayout.offset(of: \task_vm_info_data_t.min_address)! / MemoryLayout<integer_t>.size)

enum MachError: Error {
    case kernelError(kern_return_t)
}

public enum Memory {
    /// Collects single sample of current memory footprint.
    ///
    /// The computation is based on https://developer.apple.com/forums/thread/105088
    /// It leverages recommended `phys_footprint` value, which returns values that are close to Xcode's _Memory Use_
    /// gauge and _Allocations Instrument_.
    ///
    /// - Returns: Current memory footprint in bytes, `throws` if failed to read.
    static func footprint() throws -> Double {
        var info = task_vm_info_data_t()
        var count = TASK_VM_INFO_COUNT
        let kr = withUnsafeMutablePointer(to: &info) { infoPtr in
            infoPtr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), intPtr, &count)
            }
        }
        guard kr == KERN_SUCCESS, count >= TASK_VM_INFO_REV1_COUNT else {
            throw MachError.kernelError(kr)
        }

        return Double(info.phys_footprint)
    }
}
