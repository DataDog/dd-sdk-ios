/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogInternal
@testable import DatadogCrashReporting

class KSCrashBacktraceTests: XCTestCase {
    /// Regex pattern to match stack frame format: index library_name address load_address + offset
    /// Library name can contain spaces (e.g., "DatadogCrashReportingTests iOS")
    let regex = try! NSRegularExpression(pattern: #"^\d+\s+.+?\s+0x[0-9a-f]+\s+0x[0-9a-f]+\s+\+\s+\d+$"#, options: [.anchorsMatchLines])

    // MARK: - Current Thread Tests

    func testCurrentThreadStackContainsTestFrames() throws {
        // Given
        let backtrace = KSCrashBacktrace()
        let currentThreadID = Thread.currentThreadID

        // When
        let report = try XCTUnwrap(try backtrace.generateBacktrace(threadID: currentThreadID))

        // Then
        report.stack.split(separator: "\n").forEach { line in
            let range = NSRange(line.startIndex..., in: line)

            // Validate each line matches the expected format
            XCTAssertNotNil(
                regex.firstMatch(in: String(line), range: range),
                "Stack line should match format 'index library address load_address + offset': \(line)"
            )
        }

        let userImage = report.binaryImages.first(where: { $0.libraryName.contains("DatadogCrashReportingTests") })
        let systemImage = report.binaryImages.first(where: { $0.libraryName == "xctest" })

        XCTAssertFalse(userImage?.isSystemLibrary ?? true, "Should include current binary image")
        XCTAssertTrue(systemImage?.isSystemLibrary ?? false, "Should include xctest system image")
        XCTAssertEqual(report.threads.count, 1, "Should have one thread")
        XCTAssertEqual(report.stack, report.threads[0].stack)
        XCTAssertFalse(report.threads[0].name.isEmpty, "Thread should have a name")
    }

    // MARK: - Other Thread Tests

    func testGenerateBacktraceForBackgroundThread() throws {
        // Given
        let backtrace = KSCrashBacktrace()
        let expectation = XCTestExpectation(description: "Background thread backtrace")
        var capturedReport: BacktraceReport?
        var backgroundThreadID: ThreadID?

        // Use a lock-protected flag so the background thread busy-spins inside `keepThreadBusy()`
        // (defined in this test module). This keeps user code frames on the stack at capture time.
        let threadReady = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var shouldStop = false

        // When - Create a background thread that busy-spins inside user code
        Thread.detachNewThread {
            backgroundThreadID = Thread.currentThreadID
            threadReady.signal()
            KSCrashBacktraceTests.keepThreadBusy(lock: lock, stop: &shouldStop) // user code on the stack
        }

        // Wait for the background thread to be ready and spinning
        threadReady.wait()
        Thread.sleep(forTimeInterval: 0.05) // ensure thread enters the busy loop

        // Capture backtrace while background thread is spinning in user code
        do {
            capturedReport = try backtrace.generateBacktrace(threadID: backgroundThreadID!)
            expectation.fulfill()
        } catch {
            XCTFail("Failed to generate backtrace: \(error)")
            expectation.fulfill()
        }

        // Stop the background thread
        lock.lock()
        shouldStop = true
        lock.unlock()

        wait(for: [expectation], timeout: 5.0)

        // Then
        XCTAssertNotNil(capturedReport, "Should generate backtrace for background thread")
        let report = try XCTUnwrap(capturedReport)

        report.stack.split(separator: "\n").forEach { line in
            let range = NSRange(line.startIndex..., in: line)

            // Validate each line matches the expected format
            XCTAssertNotNil(
                regex.firstMatch(in: String(line), range: range),
                "Stack line should match format 'index library address load_address + offset': \(line)"
            )
        }

        let userImage = report.binaryImages.first(where: { $0.libraryName.contains("DatadogCrashReportingTests") })
        XCTAssertFalse(userImage?.isSystemLibrary ?? true, "Should include current binary image")
        XCTAssertTrue(
            report.binaryImages.contains(where: { $0.isSystemLibrary }),
            "Should include system binary images"
        )
        XCTAssertFalse(report.binaryImages.contains(where: { $0.libraryName == "xctest" }), "Should not include xctest")
        XCTAssertEqual(report.threads.count, 1, "Should have one thread")
        XCTAssertEqual(report.stack, report.threads[0].stack)
        XCTAssertFalse(report.threads[0].name.isEmpty, "Thread should have a name")
    }

    /// Keeps the current thread busy with user code frames on the stack until the flag is set.
    /// This function must not be inlined so it appears as a distinct frame in the backtrace.
    @inline(never)
    private static func keepThreadBusy(lock: NSLock, stop: UnsafeMutablePointer<Bool>) {
        while true {
            lock.lock()
            let done = stop.pointee
            lock.unlock()
            if done { break }
            Thread.sleep(forTimeInterval: 0.001)
        }
    }

    func testInvalidThreadIDReturnsNil() throws {
        // Given - An invalid thread ID
        let backtrace = KSCrashBacktrace()
        let invalidThreadID: ThreadID = 0

        // When
        let report = try backtrace.generateBacktrace(threadID: invalidThreadID)

        // Then
        XCTAssertNil(report, "Should return nil for invalid thread ID")
    }
}
