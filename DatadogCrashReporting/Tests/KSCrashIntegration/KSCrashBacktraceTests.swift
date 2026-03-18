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
        #if os(watchOS)
        throw XCTSkip("Backtrace generation is not supported on watchOS (thread_get_state unavailable)")
        #endif
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
        #if os(watchOS)
        throw XCTSkip("Backtrace generation is not supported on watchOS (thread_get_state unavailable)")
        #endif
        // Given
        let backtrace = KSCrashBacktrace()
        let expectation = XCTestExpectation(description: "Background thread backtrace")
        var backgroundThreadID: ThreadID?
        var capturedReport: BacktraceReport?

        // When - Create a background thread
        Thread.detachNewThread {
            let semaphore = DispatchSemaphore(value: 0)
            backgroundThreadID = Thread.currentThreadID

            // Capture backtrace from main thread
            DispatchQueue.global().async {
                do {
                    capturedReport = try backtrace.generateBacktrace(threadID: backgroundThreadID!)
                    expectation.fulfill()
                } catch {
                    XCTFail("Failed to generate backtrace: \(error)")
                    expectation.fulfill()
                }

                semaphore.signal()
            }

            // keep thread alive to generate its backtrace
            semaphore.wait()
        }

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
        let systemImage = report.binaryImages.first(where: { $0.libraryName == "Foundation" })

        XCTAssertFalse(userImage?.isSystemLibrary ?? true, "Should include current binary image")
        XCTAssertTrue(systemImage?.isSystemLibrary ?? false, "Should include Foundation system image")
        XCTAssertFalse(report.binaryImages.contains(where: { $0.libraryName == "xctest" }), "Should not include xctest")
        XCTAssertEqual(report.threads.count, 1, "Should have one thread")
        XCTAssertEqual(report.stack, report.threads[0].stack)
        XCTAssertFalse(report.threads[0].name.isEmpty, "Thread should have a name")
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

    // MARK: - watchOS Tests

    /// On watchOS, `thread_get_state` is not available, so KSCrash cannot capture machine context
    /// for non-crashing threads. `generateBacktrace` must return `nil` unconditionally to prevent
    /// reporting corrupt or empty backtraces.
    func testGenerateBacktraceReturnsNilOnWatchOS() throws {
        #if !os(watchOS)
        throw XCTSkip("This test verifies watchOS-specific behavior")
        #else
        // Given
        let backtrace = KSCrashBacktrace()

        // When
        let report = try backtrace.generateBacktrace(threadID: Thread.currentThreadID)

        // Then
        XCTAssertNil(report, "generateBacktrace should return nil on watchOS")
        #endif
    }
}
