/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if !os(watchOS)
import Foundation

/// A Thread subclass designed for profiling tests with controlled execution and synchronization
final class MockThread: Thread {
    private let workBlock: () -> Void
    private let completionSemaphore = DispatchSemaphore(value: 0)
    private var workCompleted = false

    /// Create a mock thread with a work block
    /// - Parameter work: The work to execute on the thread
    init(work: @escaping () -> Void) {
        self.workBlock = work
        super.init()
        self.name = "MockThread-\(UUID())"
    }

    override func main() {
        // Execute the work if not cancelled
        if !isCancelled {
            workBlock()
        }

        // Mark work as completed
        workCompleted = true
        completionSemaphore.signal()
    }

    /// Wait for work to complete
    /// - Parameter timeout: Maximum time to wait
    /// - Returns: true if work completed, false if timeout
    @discardableResult
    func waitForWorkCompletion(timeout: TimeInterval = 5.0) -> Bool {
        let result = completionSemaphore.wait(timeout: .now() + timeout)
        return result == .success && workCompleted
    }

    /// Cancel the thread and clean up
    override func cancel() {
        super.cancel()

        // Signal semaphore to unblock any waiting calls
        completionSemaphore.signal()
    }
}

/// Helper class to manage multiple profiled threads for testing
final class MockThreadGroup {
    private(set) var threads: [MockThread] = []

    /// Add a thread to the group
    /// - Parameter thread: The thread to add
    func add(_ thread: MockThread) {
        threads.append(thread)
    }

    /// Create and add a thread with work
    /// - Parameter work: The work block for the thread
    /// - Returns: The created thread
    @discardableResult
    func createThread(work: @escaping () -> Void) -> MockThread {
        let thread = MockThread(work: work)
        add(thread)
        return thread
    }

    /// Start all threads
    func startAll() {
        threads.forEach { $0.start() }
    }

    /// Wait for all threads to complete their work
    /// - Parameter timeout: Timeout for each thread
    /// - Returns: true if all completed
    @discardableResult
    func waitForAllCompletion(timeout: TimeInterval = 5.0) -> Bool {
        return threads.allSatisfy { $0.waitForWorkCompletion(timeout: timeout) }
    }

    /// Cancel and clean up all threads
    func cancelAll() {
        threads.forEach { $0.cancel() }
        threads.removeAll()
    }

    deinit {
        cancelAll()
    }
}
#endif // !os(watchOS)
