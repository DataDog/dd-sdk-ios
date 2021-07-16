/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// A class reading the Virtual Memory resident_size, that is the part of the virtual memory which is currently in RAM.
internal class VitalMemoryReader: SamplingBasedVitalReader {
    static let task_vm_info_count = MemoryLayout<task_vm_info>.size / MemoryLayout<natural_t>.size

    func readVitalData() -> Double? {
        var vmInfo = task_vm_info()
        var vmInfoSize = mach_msg_type_size_t(VitalMemoryReader.task_vm_info_count)

        let kern: kern_return_t = withUnsafeMutablePointer(to: &vmInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(
                    mach_task_self_,
                    task_flavor_t(TASK_VM_INFO),
                    $0,
                    &vmInfoSize
                )
            }
        }

        if kern == KERN_SUCCESS {
            return Double(vmInfo.resident_size)
        } else {
            return nil
        }
    }
}
