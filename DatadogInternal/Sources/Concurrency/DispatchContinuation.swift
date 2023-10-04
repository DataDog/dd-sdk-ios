/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// ``DispatchContinuation`` can be applied to objects that manage async operations to
/// notify a continuation block when all current asynchronous operations have finished executing.
///
/// If the complying object manages multiple queues, the ``DispatchContinuationSequence``
/// can be used to chain and/or groupe continuation.
public protocol DispatchContinuation {
    /// Schedules the submission of a block to execute when all current asynchronous tasks
    /// have finished executing.
    ///
    /// This function schedules a notification block to be invoked when
    /// all asynchronous operations associated with the instance have completed. If the
    /// complying instance has no operations (no asynchronous tasks scheduled in background),
    /// the notification block object should be invoked immediately.
    ///
    /// - Parameters:
    ///   - continuation: The closure to invoke on continuation.
    func notify(_ continuation: @escaping () -> Void)
}

extension DispatchContinuation {
    @available(iOS 13.0, tvOS 13.0, *)
    public func continuation() async {
        await withCheckedContinuation { notify($0.resume) }
    }
}

extension DispatchQueue: DispatchContinuation {
    /// Schedules the submission of continuation to execute when all current asynchronous tasks
    /// have finished executing.
    ///
    /// When submitted to a concurrent queue, the work item act as a barrier block. Work items
    /// submitted prior to the continuation execute to completion, at which point the continuation
    /// work item executes.
    ///
    /// - Parameter continuation: The closure to invoke on continuation.
    public func notify(_ continuation: @escaping () -> Void) {
        async(flags: .barrier, execute: continuation)
    }
}

/// A sequence of ``DispatchContinuation`` that can notify completion of multiple
/// concurrent executions.
///
/// The sequence can notify continuation after execution in cascade or in parallel.
///
/// # Cascade
/// In the following example, `read`, `process`, `write` are asynchronous processes that
/// perform operations concurrently comply to ``DispatchContinuation``:
///
///     DispatchContinuationSequence(first: read)
///         .then(process)
///         .then(write)
///         .notify { }
///
/// The sequence will wait for the execution of `read`, when `read` notifies its continuation
/// **then** it waits for the execution of `process`, **then** `write` waits for continuation
/// of `write`.
///
/// Continuation in cascade can be useful when tasks are dependent, in this example `read`
/// will invoke `process` which will invoke `write`. We want to be notify when the full stream
/// has finished executing
///
/// # Parallel
/// When all element of a parallel sequence finish executing, the group notify its continuation,
/// regardless of the order of the sequence.
///
///     DispatchContinuationSequence(
///         group: [task1, task2, task3]
///     ).notify { }
///
/// A sequence can also combine parallel and cascade execution to notify continuation:
///
///     DispatchContinuationSequence(first: read)
///         .then(group: [process1, process2, process3])
///         .then(write)
///         .notify { }
///
public struct DispatchContinuationSequence: DispatchContinuation {
    public typealias Continuation = () -> Void

    private let block: (@escaping Continuation) -> Void

    private init(_ block: @escaping (@escaping Continuation) -> Void) {
        self.block = block
    }

    /// Notify continuation when all element of the sequence have finished executing.
    ///
    /// - Parameter continuation: The closure to invoke on continuation.
    public func notify(_ continuation: @escaping Continuation) {
        block(continuation)
    }
}

extension DispatchContinuationSequence {
    /// Creates an empty continuation sequence.
    ///
    /// Calling `notify` on an empty sequence will invoke continuation immediatly.
    public init() {
        self.block = { $0() }
    }

    /// Create a continuation sequence with the given first element.
    ///
    /// - Parameter element: The first ``DispatchContinuation`` element of the sequence.
    public init(first element: DispatchContinuation) {
        self.block = element.notify
    }

    /// Creates a sequence to perform continuation in parallel and get notify when all
    /// asynchronous tasks are completed.
    ///
    /// The following sequence:
    ///
    ///     DispatchContinuationSequence(group: [task1, task2], queue: queue)
    ///         .notify {
    ///             print("done")
    ///         }
    ///
    /// It will behave the same as the following:
    ///
    ///     let group = DispatchGroup()
    ///
    ///     group.enter()
    ///     task1.notify {
    ///         group.leave()
    ///     }
    ///     group.enter()
    ///     task2.notify {
    ///         group.leave()
    ///     }
    ///     group.notify(queue: queue) {
    ///         print("done")
    ///     }
    ///
    /// - Parameters:
    ///   - sequence: The sequence of ``DispatchContinuation`` to group.
    ///   - queue: The queue to which the supplied continuation block is submitted when the group completes.
    public init<S>(group sequence: S, queue: DispatchQueue = .global()) where S: Sequence, S.Element: DispatchContinuation {
        self.init(group: sequence.map { $0 as DispatchContinuation }, queue: queue)
    }

    /// Creates a sequence to perform continuation in parallel and get notify when all
    /// asynchronous tasks are completed.
    ///
    /// The following sequence:
    ///
    ///     DispatchContinuationSequence(group: [task1, task2], queue: queue)
    ///         .notify {
    ///             print("done")
    ///         }
    ///
    /// It will behave the same as the following:
    ///
    ///     let group = DispatchGroup()
    ///
    ///     group.enter()
    ///     task1.notify {
    ///         group.leave()
    ///     }
    ///     group.enter()
    ///     task2.notify {
    ///         group.leave()
    ///     }
    ///     group.notify(queue: queue) {
    ///         print("done")
    ///     }
    ///
    /// - Parameters:
    ///   - sequence: The sequence of ``DispatchContinuation`` to group.
    ///   - queue: The queue to which the supplied continuation block is submitted when the group completes.
    public init<S>(group sequence: S, queue: DispatchQueue = .global()) where S: Sequence, S.Element == DispatchContinuation {
        self.block = {
            let group = DispatchGroup()
            sequence.forEach {
                group.enter()
                $0.notify(group.leave)
            }
            group.notify(queue: queue, execute: $0)
        }
    }

    /// Execute the next continuation block when the current sequence notify its own
    /// continuation.
    ///
    /// Use the `then(_:)` method to perform continuation in cascade and get notify when
    /// all asynchronous tasks are completed.
    ///
    /// The following sequence:
    ///
    ///     DispatchContinuationSequence(first: task1)
    ///         .then(task2)
    ///         .then(task3)
    ///         .notify {
    ///             print("done")
    ///         }
    ///
    /// It will behave the same as the following:
    ///
    ///     task1.notify {
    ///         task2.notify {
    ///             task3.notify {
    ///                 print("done")
    ///             }
    ///         }
    ///     }
    ///
    /// - Parameter next: The next ``DispatchContinuation`` to wait for continuation.
    /// - Returns: The new sequence.
    public func then(_ next: DispatchContinuation) -> Self {
        DispatchContinuationSequence { continuation in
            self.notify { next.notify(continuation) }
        }
    }

    /// Execute the next sequence when the current sequence notify its own
    /// continuation.
    ///
    /// Use the `then(group:)` method to perform continuation in parallel and get notify when
    /// all asynchronous tasks are completed.
    ///
    /// The following sequence:
    ///
    ///     DispatchContinuationSequence(first: task1)
    ///         .then(group: [task2, task3], queue: queue)
    ///         .notify {
    ///             print("done")
    ///         }
    ///
    /// It will behave the same as the following:
    ///
    ///     task1.notify {
    ///         let group = DispatchGroup()
    ///
    ///         group.enter()
    ///         task2.notify {
    ///             group.leave()
    ///         }
    ///         group.enter()
    ///         task3.notify {
    ///             group.leave()
    ///         }
    ///         group.notify(queue: queue) {
    ///             print("done")
    ///         }
    ///     }
    ///
    /// - Parameter sequence: The next ``DispatchContinuation`` group.
    /// - Parameter queue: The queue to which the supplied continuation block is submitted when the group completes.
    /// 
    /// - Returns: The new sequence.
    public func then<S>(group sequence: S, queue: DispatchQueue = .global()) -> Self where S: Sequence, S.Element: DispatchContinuation {
        then(DispatchContinuationSequence(group: sequence, queue: queue))
    }

    /// Execute the next sequence when the current sequence notify its own
    /// continuation.
    ///
    /// Use the `then(group:)` method to perform continuation in parallel and get notify when
    /// all asynchronous tasks are completed.
    ///
    /// The following sequence:
    ///
    ///     DispatchContinuationSequence(first: task1)
    ///         .then(group: [task2, task3], queue: queue)
    ///         .notify {
    ///             print("done")
    ///         }
    ///
    /// It will behave the same as the following:
    ///
    ///     task1.notify {
    ///         let group = DispatchGroup()
    ///
    ///         group.enter()
    ///         task2.notify {
    ///             group.leave()
    ///         }
    ///         group.enter()
    ///         task3.notify {
    ///             group.leave()
    ///         }
    ///         group.notify(queue: queue) {
    ///             print("done")
    ///         }
    ///     }
    ///
    /// - Parameter sequence: The next ``DispatchContinuation`` group.
    /// - Parameter queue: The queue to which the supplied continuation block is submitted when the group completes.
    /// - Returns: The new sequence.
    public func then<S>(group sequence: S, queue: DispatchQueue = .global()) -> Self where S: Sequence, S.Element == DispatchContinuation {
        then(DispatchContinuationSequence(group: sequence, queue: queue))
    }
}
