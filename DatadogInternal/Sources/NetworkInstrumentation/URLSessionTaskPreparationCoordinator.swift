/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Coordinates one preparation per task across concurrent/reentrant resumes and early callbacks.
///
/// The feature customizes requests outside this coordinator, then enqueues the interception start
/// before calling finishPreparation. Until then, resumes and callbacks are buffered per task.
/// This lock protects bookkeeping only; request customization, handlers and native resumes must
/// never be invoked by the lock holder.
///
/// At each unlocked boundary, a tracked task is either in preparations (preparing/ready) or terminalTasks.
/// A terminal callback during preparation sets observedTerminal and keeps the record until finish,
/// so the pending resumes and callbacks are not lost. Finishing then replaces it with a terminal marker.
/// The separate weak terminal set remembers completed identities without retaining preparation state.
/// Both collections use object identity, since taskIdentifier can repeat across URLSession instances.
internal final class URLSessionTaskPreparationCoordinator {
    private let lock = NSLock()
    private let preparations = NSMapTable<URLSessionTask, TaskPreparation>(
        keyOptions: [.weakMemory, .objectPointerPersonality],
        valueOptions: .strongMemory
    )
    private let terminalTasks = NSHashTable<URLSessionTask>(options: [.weakMemory, .objectPointerPersonality])

    private final class TaskPreparation {
        enum Phase { case preparing, ready }
        var phase: Phase
        let trackingMode: TrackingMode
        var continuations: [URLSessionTaskSwizzler.ResumeContinuation] = []
        var events: [Event] = []
        var bufferedBodySize = 0
        var discardedBody = false
        var observedTerminal = false

        init(phase: Phase, trackingMode: TrackingMode = .automatic) {
            self.phase = phase
            self.trackingMode = trackingMode
        }
    }

    enum ResumeAction { case prepare, forward, deferred }

    enum Event {
        case metrics(URLSessionTaskMetrics)
        case data(Data)
        case discardResponseBody
        case completion(Error?, Date, CFTimeInterval)
        case state(Int, Date, CFTimeInterval)

        var isTerminal: Bool {
            switch self {
            case .completion: return true
            case let .state(state, _, _): return state == URLSessionTask.State.completed.rawValue
            case .metrics, .data, .discardResponseBody: return false
            }
        }
    }

    private let maxBufferedBodySize: Int

    init(maxBufferedBodySize: Int) {
        self.maxBufferedBodySize = maxBufferedBodySize
    }

    /// Reuses a task's existing lifecycle before the caller evaluates mutable request/delegate properties.
    func existingResumeAction(
        for task: URLSessionTask,
        continuation: @escaping URLSessionTaskSwizzler.ResumeContinuation
    ) -> ResumeAction? {
        lock.lock()
        defer { lock.unlock() }
        if let preparation = preparations.object(forKey: task) {
            return resumeAction(for: preparation, continuation: continuation)
        }
        return terminalTasks.contains(task) ? .forward : nil
    }

    /// Called only while holding `lock`; never invokes customer or native code.
    private func resumeAction(
        for preparation: TaskPreparation,
        continuation: @escaping URLSessionTaskSwizzler.ResumeContinuation
    ) -> ResumeAction {
        switch preparation.phase {
        case .preparing:
            preparation.continuations.append(continuation)
            return .deferred
        case .ready:
            return .forward
        }
    }

    func forwardUnlessPreparing(_ task: URLSessionTask, continuation: @escaping URLSessionTaskSwizzler.ResumeContinuation) {
        if let action = existingResumeAction(for: task, continuation: continuation), case .deferred = action {
            return
        }
        continuation()
    }

    /// Atomically claims the first preparation after eligibility checks; a concurrent caller may have won meanwhile.
    func beginPreparation(
        for task: URLSessionTask,
        continuation: @escaping URLSessionTaskSwizzler.ResumeContinuation,
        trackingMode: TrackingMode,
        isCompleted: Bool
    ) -> ResumeAction {
        lock.lock()
        defer { lock.unlock() }
        if let preparation = preparations.object(forKey: task) {
            return resumeAction(for: preparation, continuation: continuation)
        }
        if terminalTasks.contains(task) || isCompleted {
            terminalTasks.add(task)
            return .forward
        }
        let preparation = TaskPreparation(phase: .preparing, trackingMode: trackingMode)
        preparations.setObject(preparation, forKey: task)
        preparation.continuations.append(continuation)
        return .prepare
    }

    /// Call after the interception start has been submitted to the feature's serial queue.
    /// `enqueue` must only submit work to that same queue: it runs under `lock` to preserve event order.
    /// Saved resume continuations run after unlocking, potentially on a different thread from their caller.
    func finishPreparation(for task: URLSessionTask, enqueue: (Event, URLSessionTask) -> Void) {
        lock.lock()
        guard let preparation = preparations.object(forKey: task), preparation.phase == .preparing else {
            lock.unlock()
            return
        }
        // Start is already enqueued. Keep callback enqueue order inside the coordinator lock.
        let events = preparation.events
        events.forEach { enqueue($0, task) }
        let continuations = preparation.continuations
        preparation.events.removeAll()
        preparation.continuations.removeAll()
        if preparation.observedTerminal {
            terminalTasks.add(task)
            preparations.removeObject(forKey: task)
        } else {
            preparation.phase = .ready
        }
        lock.unlock()
        // Clearing the buffers/removing the record can release customer-owned Data/Error payloads.
        // Their deinitializers may call resume() again, so keep them alive until after unlocking.
        withExtendedLifetime((preparation, events)) {}
        continuations.forEach { $0() }
    }

    /// Buffers callbacks during preparation, otherwise submits them in lock-acquisition order.
    /// As in finishPreparation, `enqueue` must only submit work and must not reenter this coordinator.
    func route(_ event: Event, for task: URLSessionTask, enqueue: (Event, URLSessionTask) -> Void) {
        lock.lock()
        let preparation = preparations.object(forKey: task)
        defer {
            lock.unlock()
            // Removing terminal preparation state must not run payload deinitializers under the lock.
            withExtendedLifetime(preparation) {}
        }
        if let preparation, preparation.phase == .preparing {
            preparation.observedTerminal = preparation.observedTerminal || event.isTerminal
            if case let .data(data) = event, preparation.trackingMode == .registeredDelegate {
                guard !preparation.discardedBody else {
                    return
                }
                if data.count > maxBufferedBodySize - preparation.bufferedBodySize {
                    preparation.discardedBody = true
                    preparation.events.append(.discardResponseBody)
                    return
                }
                preparation.bufferedBodySize += data.count
            }
            preparation.events.append(event)
            return
        }
        if event.isTerminal {
            // State interception precedes the native setter, so task.state alone is insufficient.
            terminalTasks.add(task)
            preparations.removeObject(forKey: task)
        }
        enqueue(event, task)
    }
}
