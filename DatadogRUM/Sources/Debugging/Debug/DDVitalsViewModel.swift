/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import DatadogInternal
import Observation
import SwiftUI
import Foundation
import MachO

@available(iOS 15.0, *)
public final class DDVitalsViewModel: ObservableObject {
    @Published var progress: CGFloat = 0 // Value between 0.0 and 1.0
    @Published var hangs: [(CGFloat, CGFloat)] = [] // Range for green highlight (e.g., 0.2...0.3)
    @Published var hitches: [(CGFloat, CGFloat)] = [] // Positions of vertical lines (e.g., [0.6, 0.7, 0.75])

    @Published var cpuValue: Int = 0
    @Published var memoryValue: Int = 0
    @Published var threadsCount: Int = 0

    var hitchesRatio: CGFloat {
        lastHitchValue = hitchesDuration / currentDuration * Double(1.toMilliseconds)
        return lastHitchValue
    } // milliseconds/second
    var hangsRatio: CGFloat { hangsDuration / currentDuration * 1.hours } // seconds/hour

    private var startTimestamp: CGFloat?

    var currentDuration: CGFloat = 0.1

    private var viewMaxDuration = 60.0

    private let rumFeature: RUMFeature?
    let metricsManager: DatadogMetricSubscriber

    private var activeViewScope: RUMViewScope?

    private var lastHitchValue: CGFloat = 0
    private var hitchesDictionary: [String: [CGFloat]] = [:]

    public init(
        core: DatadogCoreProtocol = CoreRegistry.default,
        metricsManager: DatadogMetricSubscriber = DatadogMetricSubscriber(core: CoreRegistry.default)
    ) {
        rumFeature = core.get(feature: RUMFeature.self)
        self.metricsManager = metricsManager
    }

    func updateView() {
        guard let viewScope = rumFeature?.monitor.scopes.activeSession?.viewScopes.first(where: { $0.isActiveView }) else { return }

        if activeViewScope !== viewScope {
            hitchesDictionary[activeViewScope?.viewName ?? ""] = hitchesDictionary[activeViewScope?.viewName ?? "", default: []] + [lastHitchValue]

            viewMaxDuration = 60.0
            hitches = []
            hangs = []
            progress = 0
        }

        activeViewScope = viewScope

        updateTimeline(viewScope: viewScope)
        updateVitals(viewScope: viewScope)
    }

    func updateTimeline(viewScope: RUMViewScope) {
        if let viewHitches = getViewHitches(from: viewScope),
           viewHitches.dataModel.startTimestamp > 0 {
            startTimestamp = viewHitches.dataModel.startTimestamp

            let interval = CACurrentMediaTime() - startTimestamp!
            currentDuration = interval

            progress = interval / viewMaxDuration
            if progress >= 1.0 {
                withAnimation { viewMaxDuration = interval }
            }

            if progress > 500 {
                print("\(startTimestamp)")
            }

            hitches = viewHitches.dataModel.hitches.map {
                let start = Double($0.start) / 1_000_000_000.0
                let duration = Double($0.duration) / 1_000_000_000.0
                // print("\(start / viewDuration) - \(duration)")
                return (start / viewMaxDuration, CGFloat(duration < 1 ? 1 : duration))
            }
        }

        for hang in viewScope.hangs {
            hangs.append((hang.0 / viewMaxDuration, hang.1))
        }
    }

    func updateVitals(viewScope: RUMViewScope) {
        guard let vitalInfoSampler = viewScope.vitalInfoSampler else { return }

        cpuValue = Int(cpuUsage())
        memoryValue = Int((vitalInfoSampler.memory.currentValue ?? 0).MB)
        threadsCount = countThreads()

//        print("Logical CPU cores: \(ProcessInfo.processInfo.processorCount)")
    }

    func getViewHitches(from viewScope: RUMViewScope) -> ViewHitchesModel? { viewScope.viewHitchesReader }

    var hitchesDuration: Double {
        (activeViewScope?.viewHitchesReader?.dataModel.hitchesDuration ?? 0)
    }

    var hangsDuration: Double {
        (activeViewScope?.totalAppHangDuration ?? 0)
    }

    var viewScopeName: String {
        activeViewScope?.viewName ?? "Unknown"
    }
}

@available(iOS 15.0, *)
extension DDVitalsViewModel {

    func levelFor(cpu: Int) -> WarningLevel {

        switch cpu {
        case ..<50:
            return .low
        case ..<90:
            return .medium
        default:
            return .high
        }
    }

    func levelFor(memory: Int) -> WarningLevel {

        switch memory {
        case ..<300:
            return .low
        case ..<500:
            return .medium
        default:
            return .high
        }
    }

    func levelFor(threads: Int) -> WarningLevel {

        switch threads {
        case ..<ProcessInfo.processInfo.processorCount:
            return .low
        case ..<(ProcessInfo.processInfo.processorCount * 2):
            return .medium
        default:
            return .high
        }
    }
}

@available(iOS 15.0, *)
private extension DDVitalsViewModel {

    func cpuUsage() -> Double {
        var kr: kern_return_t
        var task_info_count: mach_msg_type_number_t

        task_info_count = mach_msg_type_number_t(TASK_INFO_MAX)
        var tinfo = [integer_t](repeating: 0, count: Int(task_info_count))

        kr = task_info(mach_task_self_, task_flavor_t(TASK_BASIC_INFO), &tinfo, &task_info_count)
        if kr != KERN_SUCCESS {
            return -1
        }

        var thread_list: thread_act_array_t? = UnsafeMutablePointer(mutating: [thread_act_t]())
        var thread_count: mach_msg_type_number_t = 0
        defer {
            if let thread_list = thread_list {
                vm_deallocate(mach_task_self_, vm_address_t(UnsafePointer(thread_list).pointee), vm_size_t(thread_count))
            }
        }

        kr = task_threads(mach_task_self_, &thread_list, &thread_count)

        if kr != KERN_SUCCESS {
            return -1
        }

        var tot_cpu: Double = 0

        if let thread_list = thread_list {

            for j in 0 ..< Int(thread_count) {
                var thread_info_count = mach_msg_type_number_t(THREAD_INFO_MAX)
                var thinfo = [integer_t](repeating: 0, count: Int(thread_info_count))
                kr = thread_info(thread_list[j], thread_flavor_t(THREAD_BASIC_INFO),
                                 &thinfo, &thread_info_count)
                if kr != KERN_SUCCESS {
                    return -1
                }

                let threadBasicInfo = convertThreadInfoToThreadBasicInfo(thinfo)

                if threadBasicInfo.flags != TH_FLAGS_IDLE {
                    tot_cpu += (Double(threadBasicInfo.cpu_usage) / Double(TH_USAGE_SCALE)) * 100.0
                }
            } // for each thread
        }

        return tot_cpu
    }

    fileprivate func convertThreadInfoToThreadBasicInfo(_ threadInfo: [integer_t]) -> thread_basic_info {
        var result = thread_basic_info()

        result.user_time = time_value_t(seconds: threadInfo[0], microseconds: threadInfo[1])
        result.system_time = time_value_t(seconds: threadInfo[2], microseconds: threadInfo[3])
        result.cpu_usage = threadInfo[4]
        result.policy = threadInfo[5]
        result.run_state = threadInfo[6]
        result.flags = threadInfo[7]
        result.suspend_count = threadInfo[8]
        result.sleep_time = threadInfo[9]

        return result
    }

//    func cpuUsage() -> Double? {
//
//        var kr: kern_return_t
//        var task_info_count = mach_msg_type_number_t(MemoryLayout<task_info_data_t>.size / MemoryLayout<natural_t>.size)
//        var tinfo = task_info_data_t()
//
//        kr = task_info(mach_task_self_, task_flavor_t(TASK_BASIC_INFO), &tinfo, &task_info_count)
//        guard kr == KERN_SUCCESS else { return -1 }
//
//        let taskInfo = unsafeBitCast(tinfo, to: task_basic_info.self)
//        return Double(taskInfo.cpu_usage) / Double(TH_USAGE_SCALE) * 100.0
//    }

    func countThreads() -> Int {
        var count: mach_msg_type_number_t = 0
        var threads: thread_act_array_t?
        let kerr = task_threads(mach_task_self_, &threads, &count)
        guard kerr == KERN_SUCCESS else {
            return -1
        }
        return Int(count)
    }
}

private extension Double {
    var MB: Self { self / 1_000_000 }
}
