/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// A class reading the CPU ticks of the processor.
internal class VitalCPUReader: SamplingBasedVitalReader {
    /// host_cpu_load_info_count is 4 (tested in iOS 14.4)
    private static let host_cpu_load_info_count = MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride
    private var totalActiveTicks: UInt64? = nil
    private var lastReadActiveTicks: UInt64? = nil

    /// Telemetry interface.
    private let telemetry: Telemetry

    init(
        notificationCenter: NotificationCenter,
        telemetry: Telemetry = NOPTelemetry()
    ) {
        self.telemetry = telemetry
        notificationCenter.addObserver(self, selector: #selector(appWillResignActive), name: ApplicationNotifications.willResignActive, object: nil)
        notificationCenter.addObserver(self, selector: #selector(appDidBecomeActive), name: ApplicationNotifications.didBecomeActive, object: nil)
    }

    func readVitalData() -> Double? {
        addActiveTicks()
        if let totalActiveTicks {
            return Double(totalActiveTicks)
        }
        return nil
    }

    private func addActiveTicks() {
        // If lastReadActiveTicks isn't set, we're currently not the active application.
        guard let lastActiveTicks = lastReadActiveTicks else {
            return
        }

        if let ticks = readUtilizedTicks() {
            var activeTicks: UInt64 = totalActiveTicks ?? 0

            if ticks < lastActiveTicks {
                // Ticks overflowed back to 0. The number of elapsed active ticks is the current number of ticks
                // plus the number of ticks since the last read to a UInt32 overflow
                activeTicks &+= ticks + (UInt64(UInt32.max) - lastActiveTicks)
            } else {
                let elapsedTicks = ticks - lastActiveTicks
                activeTicks &+= elapsedTicks
            }

            totalActiveTicks = activeTicks
            lastReadActiveTicks = ticks
        }
    }

    // TODO: RUMM-1276 appWillResignActive&appDidBecomeActive are called in main thread
    // IF readVitalData() is called from non-main threads, they must be synchronized

    @objc
    private func appWillResignActive() {
        // Before resigning active, log the current active ticks
        addActiveTicks()
        lastReadActiveTicks = nil
    }

    @objc
    private func appDidBecomeActive() {
        lastReadActiveTicks = readUtilizedTicks()
    }

    internal func readUtilizedTicks() -> UInt64? {
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
            telemetry.error("CPU Vital cannot be read! Error code: \(result)")
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
