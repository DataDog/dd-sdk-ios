/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

#if !os(watchOS) && !os(macOS)

/// Collects profile snapshots on a common cadence and writes each collection together.
/// Providers own their window boundaries. Joining the cadence or closing a window between
/// ticks can produce a shorter interval or different intervals within the same collection.
internal final class ProfilingScheduler: @unchecked Sendable {
    enum Constants {
        static let profilingInterval: TimeInterval = 60 // 1 minute profiles
    }

    private struct WeakProvider: Sendable {
        weak var value: (any ProfileSnapshotProvider)?
    }

    private let queue = DispatchQueue(label: "com.datadoghq.profiling-scheduler", qos: .utility)
    private let writer: ProfileWriter
    private let intervalNanoseconds: UInt64?
    private var profilers: [ObjectIdentifier: WeakProvider] = [:]
    private var periodicDeadline: DispatchTime?
    private var timer: DispatchSourceTimer?
    private var pendingCaptures = 0
    private var snapshots: [ProfileSnapshot] = []

    init(writer: ProfileWriter, profilingInterval: TimeInterval = Constants.profilingInterval) {
        self.writer = writer
        let nanoseconds = profilingInterval * 1_000_000_000
        intervalNanoseconds = nanoseconds.isFinite && nanoseconds >= 1 && nanoseconds < Double(Int.max)
            ? UInt64(nanoseconds) : nil
    }

    deinit {
        timer?.cancel()
    }

    func startPeriodic(for profiler: any ProfileSnapshotProvider) {
        let identifier = ObjectIdentifier(profiler)
        let provider = WeakProvider(value: profiler)
        queue.async { [weak self] in
            guard let self, let intervalNanoseconds else {
                return
            }
            profilers[identifier] = provider
            guard timer == nil else {
                return
            }
            let deadline = DispatchTime.now() + .nanoseconds(Int(intervalNanoseconds))
            periodicDeadline = deadline
            let timer = DispatchSource.makeTimerSource(queue: queue)
            // Allow up to one second for coalescing, capped at 10% for shorter intervals.
            let leeway = min(intervalNanoseconds / 10, 1_000_000_000)
            timer.schedule(deadline: deadline, repeating: .nanoseconds(Int(intervalNanoseconds)), leeway: .nanoseconds(Int(leeway)))
            timer.setEventHandler { [weak self] in
                self?.fire()
            }
            self.timer = timer
            timer.resume()
        }
    }

    func stopPeriodic(for profiler: any ProfileSnapshotProvider) {
        let identifier = ObjectIdentifier(profiler)
        queue.async { [weak self] in
            guard let self else {
                return
            }
            profilers.removeValue(forKey: identifier)
            profilers = profilers.filter { $0.value.value != nil }
            if profilers.isEmpty {
                stopTimer()
            }
        }
    }
}

private extension ProfilingScheduler {
    func stopTimer() {
        timer?.cancel()
        timer = nil
        periodicDeadline = nil
    }

    func fire() {
        let now = DispatchTime.now()
        guard let periodicDeadline, periodicDeadline <= now, let intervalNanoseconds else {
            return
        }
        // Skip missed ticks without moving the common phase.
        let elapsed = now.uptimeNanoseconds - periodicDeadline.uptimeNanoseconds
        let deadline = DispatchTime(uptimeNanoseconds: now.uptimeNanoseconds - elapsed % intervalNanoseconds)
        self.periodicDeadline = deadline + .nanoseconds(Int(intervalNanoseconds))

        profilers = profilers.filter { $0.value.value != nil }
        if profilers.isEmpty {
            stopTimer()
            return
        }
        // A slow capture must not accumulate work on profiler queues.
        guard pendingCaptures == 0 else {
            return
        }
        let activeProfilers = profilers.values.compactMap(\.value)
        pendingCaptures = activeProfilers.count
        for profiler in activeProfilers {
            profiler.captureSnapshot(scheduledFor: deadline) { [weak self] snapshot in
                self?.queue.async { [weak self] in
                    self?.didCapture(snapshot)
                }
            }
        }
    }

    func didCapture(_ snapshot: ProfileSnapshot?) {
        if let snapshot {
            snapshots.append(snapshot)
        }
        pendingCaptures -= 1
        if pendingCaptures == 0 {
            let captured = snapshots
            snapshots.removeAll(keepingCapacity: true)
            writer.write(captured, operation: .continuousProfiling)
        }
    }
}

#endif
