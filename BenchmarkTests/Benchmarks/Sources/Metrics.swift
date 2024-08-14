/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import QuartzCore

// The `TASK_VM_INFO_COUNT` and `TASK_VM_INFO_REV1_COUNT` macros are too
// complex for the Swift C importer, so we have to define them ourselves.
let TASK_VM_INFO_COUNT = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
let TASK_VM_INFO_REV1_COUNT = mach_msg_type_number_t(MemoryLayout.offset(of: \task_vm_info_data_t.min_address)! / MemoryLayout<integer_t>.size)

enum MachError: Error {
    case task_info(return: kern_return_t)
    case task_threads(return: kern_return_t)
    case thread_info(return: kern_return_t)
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
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }

        guard kr == KERN_SUCCESS, count >= TASK_VM_INFO_REV1_COUNT else {
            throw MachError.task_info(return: kr)
        }

        return Double(info.phys_footprint)
    }
}

public enum CPU {
    /// Collect single sample of current cpu usage.
    ///
    /// The computation is based on https://gist.github.com/hisui/10004131#file-cpu-usage-cpp
    /// It reads the `cpu_usage` from all thread to compute the application usage percentage.
    ///
    /// - Returns: The cpu usage of all threads.
    static func usage() throws -> Double {
        var threads_list: thread_act_array_t?
        var threads_count = mach_msg_type_number_t()
        let kr = withUnsafeMutablePointer(to: &threads_list) {
            $0.withMemoryRebound(to: thread_act_array_t?.self, capacity: 1) {
                task_threads(mach_task_self_, $0, &threads_count)
            }
        }

        guard kr == KERN_SUCCESS, let threads_list = threads_list else {
            throw MachError.task_threads(return: kr)
        }

        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: threads_list), vm_size_t(Int(threads_count) * MemoryLayout<thread_t>.stride))
        }

        return try (0..<threads_count).reduce(0) { result, index in
            var basic_info = thread_basic_info()
            var basic_info_count = mach_msg_type_number_t(THREAD_INFO_MAX)
            let kr = withUnsafeMutablePointer(to: &basic_info) {
                $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                    thread_info(threads_list[Int(index)], thread_flavor_t(THREAD_BASIC_INFO), $0, &basic_info_count)
                }
            }

            guard kr == KERN_SUCCESS else {
                throw MachError.thread_info(return: kr)
            }

            guard basic_info.flags != TH_FLAGS_IDLE else {
                return result
            }

            return result + Double(basic_info.cpu_usage) / Double(TH_USAGE_SCALE)
        }
    }
}

/// FPS aggregator to measure the minimal frame rate.
internal final class FPS {
    private class CADisplayLinker {
        weak var fps: FPS?

        init() { }

        @objc func tick(link: CADisplayLink) {
            guard let fps else {
                return
            }

            pthread_mutex_lock(&fps.mutex)
            let rate = 1 / (link.targetTimestamp - link.timestamp)
            fps.min = fps.min.map { Swift.min($0, rate) } ?? rate
            pthread_mutex_unlock(&fps.mutex)
        }
    }

    private var displayLink: CADisplayLink
    private var mutex = pthread_mutex_t()
    private var min: Double?
    
    /// The minimum FPS value that was measured.
    /// Call `reset` to reset the measure window.
    var minimumRate: Double? {
        pthread_mutex_lock(&mutex)
        defer { pthread_mutex_unlock(&mutex) }
        return min
    }

    /// Resets the minimum frame rate to `nil`.
    func reset() {
        pthread_mutex_lock(&mutex)
        min = nil
        pthread_mutex_unlock(&mutex)
    }

    required init() {
        let linker = CADisplayLinker()
        displayLink = CADisplayLink(target: linker, selector: #selector(CADisplayLinker.tick(link:)))

        linker.fps = self
        pthread_mutex_init(&mutex, nil)
        displayLink.add(to: RunLoop.main, forMode: .common)
    }

    deinit {
        displayLink.invalidate()
        pthread_mutex_destroy(&mutex)
    }
}
