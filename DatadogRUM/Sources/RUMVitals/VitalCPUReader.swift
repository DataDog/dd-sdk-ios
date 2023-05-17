/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import UIKit.UIApplication
import DatadogInternal

/// A class reading the CPU ticks of the processor.
internal class VitalCPUReader: SamplingBasedVitalReader {
    /// host_cpu_load_info_count is 4 (tested in iOS 14.4)
    private static let host_cpu_load_info_count = MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride
    private var totalInactiveTicks: UInt64 = 0
    private var utilizedTicksWhenResigningActive: UInt64? = nil

    init(notificationCenter: NotificationCenter = .default) {
        notificationCenter.addObserver(self, selector: #selector(appWillResignActive), name: UIApplication.willResignActiveNotification, object: nil)
        notificationCenter.addObserver(self, selector: #selector(appDidBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    func readVitalData() -> Double? {
        if let ticks = readUtilizedTicks() {
            let ongoingInactiveTicks = ticks - (utilizedTicksWhenResigningActive ?? ticks)
            let inactiveTicks = totalInactiveTicks + ongoingInactiveTicks
            return Double(ticks - inactiveTicks)
        }
        return nil
    }

    // TODO: RUMM-1276 appWillResignActive&appDidBecomeActive are called in main thread
    // IF readVitalData() is called from non-main threads, they must be synchronized

    @objc
    private func appWillResignActive() {
        utilizedTicksWhenResigningActive = readUtilizedTicks()
    }
    @objc
    private func appDidBecomeActive() {
        if let previouslyReadTicks = utilizedTicksWhenResigningActive,
           let currentTicks = readUtilizedTicks() {
            utilizedTicksWhenResigningActive = nil
            totalInactiveTicks += currentTicks - previouslyReadTicks
        }
    }

    private func readUtilizedTicks() -> UInt64? {
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
            // in case of error, refer to `kern_return.h` (Objc)
            // as its Swift interface doesn't have integer values
            DD.telemetry.error("CPU Vital cannot be read! Error code: \(result)")
            return nil
        }

        /*
         https://github.com/opensource-apple/xnu/blob/master/osfmk/mach/machine.h#L76
         // machine.h (tested in iOS 14.4)
         #define CPU_STATE_USER          0
         #define CPU_STATE_SYSTEM        1 // always returns 0 (tested in iOS 14.4)
         #define CPU_STATE_IDLE          2
         #define CPU_STATE_NICE          3

         cpu_ticks returns UInt32.
         Double type has enough precision within the range of UInt32;
         therefore even at the worst-case, precision isn't lost during this conversion below.
         */
        let userTicks = cpuLoadInfo.cpu_ticks.0
        return UInt64(userTicks)
    }
}
