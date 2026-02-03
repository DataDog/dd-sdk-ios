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

public enum MachError: Error {
    case task_info(return: kern_return_t)
    case task_threads(return: kern_return_t)
    case thread_info(return: kern_return_t)
}

/// Aggregate metric values and compute `min`, `max`, `sum`, `avg`, and `count`.
public class MetricAggregator<T> where T: Numeric {
    public struct Aggregation {
        public let min: T
        public let max: T
        public let sum: T
        public let count: Int
        public let avg: Double
    }

    private var mutex = pthread_mutex_t()
    private var _aggregation: Aggregation?

    public var aggregation: Aggregation? {
        pthread_mutex_lock(&mutex)
        defer { pthread_mutex_unlock(&mutex) }
        return _aggregation
    }

    /// Resets the minimum frame rate to `nil`.
    public func reset() {
        pthread_mutex_lock(&mutex)
        _aggregation = nil
        pthread_mutex_unlock(&mutex)
    }

    deinit {
        pthread_mutex_destroy(&mutex)
    }
}

extension MetricAggregator where T: BinaryInteger {
    /// Records a `BinaryInteger` value.
    ///
    /// - Parameter value: The value to record.
    public func record(value: T) {
        pthread_mutex_lock(&mutex)
        _aggregation = _aggregation.map {
            let sum = $0.sum + value
            let count = $0.count + 1
            return Aggregation(
                min: Swift.min($0.min, value),
                max: Swift.max($0.max, value),
                sum: sum,
                count: count,
                avg: Double(sum) / Double(count)
            )
        } ?? Aggregation(min: value, max: value, sum: value, count: 1, avg: Double(value))
        pthread_mutex_unlock(&mutex)
    }
}

extension MetricAggregator where T: BinaryFloatingPoint {
    /// Records a `BinaryFloatingPoint` value.
    ///
    /// - Parameter value: The value to record.
    internal func record(value: T) {
        pthread_mutex_lock(&mutex)
        _aggregation = _aggregation.map {
            let sum = $0.sum + value
            let count = $0.count + 1
            return Aggregation(
                min: Swift.min($0.min, value),
                max: Swift.max($0.max, value),
                sum: sum,
                count: count,
                avg: Double(sum) / Double(count)
            )
        } ?? Aggregation(min: value, max: value, sum: value, count: 1, avg: Double(value))
        pthread_mutex_unlock(&mutex)
    }
}

/// Collect Memory footprint metric.
///
/// Based on a timer, the `Memory` aggregator will periodically record the memory footprint.
public final class Memory: MetricAggregator<Double> {
    /// Dispatch source object for monitoring timer events.
    private let timer: DispatchSourceTimer

    /// Create a `Memory` aggregator to periodically record the memory footprint on the
    /// provided queue.
    ///
    /// By default, the timer is scheduled with 100 ms interval with 10 ms leeway.
    ///
    /// - Parameters:
    ///   - queue: The queue on which to execute the timer handler.
    ///   - interval: The timer interval, default to 100 ms.
    ///   - leeway: The timer leeway, default to 10 ms.
    public required init(
        queue: DispatchQueue,
        every interval: DispatchTimeInterval = .milliseconds(100),
        leeway: DispatchTimeInterval = .milliseconds(10)
    ) {
        timer = DispatchSource.makeTimerSource(queue: queue)
        super.init()

        timer.setEventHandler { [weak self] in
            guard let self, let footprint = try? self.footprint() else {
                return
            }

            self.record(value: footprint)
        }

        timer.schedule(deadline: .now(), repeating: interval, leeway: leeway)
        timer.activate()
    }

    deinit {
        timer.cancel()
    }

    /// Collects single sample of current memory footprint.
    ///
    /// The computation is based on https://developer.apple.com/forums/thread/105088
    /// It leverages recommended `phys_footprint` value, which returns values that are close to Xcode's _Memory Use_
    /// gauge and _Allocations Instrument_.
    ///
    /// - Returns: Current memory footprint in bytes, `throws` if failed to read.
    private func footprint() throws -> Double {
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

/// Collect CPU usage metric.
///
/// Based on a timer, the `CPU` aggregator will periodically record the CPU usage.
public final class CPU: MetricAggregator<Double> {
    /// Dispatch source object for monitoring timer events.
    private let timer: DispatchSourceTimer

    /// Create a `CPU` aggregator to periodically record the CPU usage on the
    /// provided queue.
    ///
    /// By default, the timer is scheduled with 100 ms interval with 10 ms leeway.
    ///
    /// - Parameters:
    ///   - queue: The queue on which to execute the timer handler.
    ///   - interval: The timer interval, default to 100 ms.
    ///   - leeway: The timer leeway, default to 10 ms.
    public required init(
        queue: DispatchQueue,
        every interval: DispatchTimeInterval = .milliseconds(100),
        leeway: DispatchTimeInterval = .milliseconds(10)
    ) {
        self.timer = DispatchSource.makeTimerSource(queue: queue)
        super.init()

        timer.setEventHandler { [weak self] in
            guard let self, let usage = try? self.usage() else {
                return
            }

            self.record(value: usage)
        }

        timer.schedule(deadline: .now(), repeating: interval, leeway: leeway)
        timer.activate()
    }

    deinit {
        timer.cancel()
    }

    /// Collect single sample of current cpu usage.
    ///
    /// The computation is based on https://gist.github.com/hisui/10004131#file-cpu-usage-cpp
    /// It reads the `cpu_usage` from all thread to compute the application usage percentage.
    ///
    /// - Returns: The cpu usage of all threads.
    private func usage() throws -> Double {
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

/// Collect Frame rate metric based on ``CADisplayLinker`` timer.
public final class FPS: MetricAggregator<Int> {
    private class CADisplayLinker {
        weak var fps: FPS?

        init() { }

        @objc
        func tick(link: CADisplayLink) {
            guard let fps else {
                return
            }

            let rate = 1 / (link.targetTimestamp - link.timestamp)
            fps.record(value: lround(rate))
        }
    }

    private var displayLink: CADisplayLink

    override public init() {
        let linker = CADisplayLinker()
        displayLink = CADisplayLink(target: linker, selector: #selector(CADisplayLinker.tick(link:)))
        super.init()

        linker.fps = self
        displayLink.add(to: RunLoop.main, forMode: .common)
    }

    deinit {
        displayLink.invalidate()
    }
}
