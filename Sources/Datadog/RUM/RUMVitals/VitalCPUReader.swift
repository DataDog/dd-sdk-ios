/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// A class reading the CPU ticks (_1 second = 600 ticks_) since the start of the process.
internal class VitalCPUReader: VitalReader {
    /// host_cpu_load_info_count is 4 (tested in iOS 14.4)
    private static let host_cpu_load_info_count = MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride

    func readVitalData() -> Double? {
        // it must be set to host_cpu_load_info_count_size >= host_cpu_load_info_count
        // implementation: https://github.com/opensource-apple/xnu/blob/master/osfmk/kern/host.c#L425
        var host_cpu_load_info_count_size = mach_msg_type_number_t(Self.host_cpu_load_info_count)
        var cpuLoadInfo = host_cpu_load_info()
        let result = withUnsafeMutablePointer(to: &cpuLoadInfo) { cpuLoadInfoPtr in
            cpuLoadInfoPtr.withMemoryRebound(
                to: integer_t.self,
                capacity: Self.host_cpu_load_info_count
            ) { integerPtr in
                host_statistics(
                    mach_host_self(),
                    HOST_CPU_LOAD_INFO,
                    integerPtr,
                    &host_cpu_load_info_count_size
                )
            }
        }
        if result != KERN_SUCCESS {
            return nil
        }

        /*
         https://github.com/opensource-apple/xnu/blob/master/osfmk/mach/machine.h#L76
         // machine.h (tested in iOS 14.4)
         #define CPU_STATE_USER          0
         #define CPU_STATE_SYSTEM        1
         #define CPU_STATE_IDLE          2
         #define CPU_STATE_NICE          3
         */
        let userTicks = cpuLoadInfo.cpu_ticks.0
        // systemTicks is always 0 (tested in iOS 14.4)
        let systemTicks = cpuLoadInfo.cpu_ticks.1

        /*
         cpu_ticks returns UInt32.
         Double type has enough precision within the range of UInt32;
         therefore even at the worst-case, precision isn't lost during this conversion below.
         */
        return Double(userTicks + systemTicks)
    }
}
