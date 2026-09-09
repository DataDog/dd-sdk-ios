/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogCrashReporting
@testable import DatadogInternal

/// Tests integration of `DatadogCore` and `DatadogCrashReporting` for backtrace generation.
class GeneratingBacktraceTests: XCTestCase {
    private var core: DatadogCoreProxy! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUp() {
        super.setUp()
        core = DatadogCoreProxy(context: .mockWith(trackingConsent: .granted))
    }

    override func tearDownWithError() throws {
        try core.flushAndTearDown()
        core = nil
        super.tearDown()
    }

    func testGeneratingBacktraceOfTheCurrentThread() throws {
        #if os(watchOS)
        throw XCTSkip("Backtrace generation is not supported on watchOS")
        #endif
        // Given
        CrashReporting.enable(in: core)
        XCTAssertNotNil(core.get(feature: BacktraceReportingFeature.self), "`BacktraceReportingFeature` must be registered")

        // When
        let backtrace = try XCTUnwrap(core.backtraceReporter.generateBacktrace())

        // Then
        XCTAssertGreaterThan(backtrace.threads.count, 0, "Some thread(s) should be recorded")
        XCTAssertGreaterThan(backtrace.binaryImages.count, 0, "Some binary image(s) should be recorded")
        XCTAssertFalse(backtrace.threads.contains(where: { $0.crashed }), "No thread should be marked as crashed")

        XCTAssertTrue(
            backtrace.stack.contains("DatadogIntegrationTests"),
            "Backtrace stack should include at least one frame from `DatadogCoreTests` image"
        )
        XCTAssertTrue(
            backtrace.stack.contains("XCTest"),
            "Backtrace stack should include at least one frame from `XCTest` image"
        )
        XCTAssertTrue(
            backtrace.binaryImages.contains(where: { $0.libraryName == "DatadogIntegrationTests" }),
            "Backtrace should include the image for `DatadogCoreTests`"
        )
        XCTAssertTrue(
            // Assert on prefix as it is `XCTestCore` on iOS 15+ and `XCTest` earlier:
            backtrace.binaryImages.contains(where: { $0.libraryName.hasPrefix("XCTest") }),
            "Backtrace should include the image for `XCTest`"
        )
    }

    /// Reads the setting the way RUM does: by name, through `CrashReportingConfiguration`.
    ///
    /// `nil` means Crash Reporting was never enabled. Resolving the `?? true` fallback here instead would make the
    /// assertions pass even if nothing were registered at all.
    private func appHangBacktraceEnabled(in core: DatadogCoreProtocol) -> Bool? {
        core.feature(named: Feature.crashReporting, type: CrashReportingConfiguration.self)?
            .appHangBacktraceEnabled
    }

    /// Number of warnings emitted about the opt-out being undone.
    ///
    /// Filtered by substring because `KSCrash` is a process singleton: from the second enabling test onwards it
    /// prints its own "already installed" warning, which is unrelated. The phrase is unique to the console
    /// warning, so this cannot start counting the telemetry message that accompanies it.
    private func optOutWarnings(in spy: PrintFunctionSpy) -> Int {
        spy.printedMessages.filter { $0.contains("undoes the earlier opt-out") }.count
    }

    func testWhenCrashReportingIsEnabledOnce_itDoesNotWarnAboutTheOptOut() {
        // Given
        let printFunction = PrintFunctionSpy()
        consolePrint = printFunction.print
        defer { consolePrint = { message, _ in print(message) } }

        // When
        CrashReporting.enable(with: .init(appHangBacktraceEnabled: false), in: core)

        // Then
        XCTAssertEqual(appHangBacktraceEnabled(in: core), false)
        XCTAssertEqual(optOutWarnings(in: printFunction), 0, "There is no earlier value to undo")
    }

    func testWhenCrashReportingIsReEnabledWithoutTheOptOut_itWarnsAndAppliesTheLatestValue() {
        // Given (`register(feature:)` overwrites by name, so a second `enable` replaces the configuration too)
        let printFunction = PrintFunctionSpy()
        consolePrint = printFunction.print
        defer { consolePrint = { message, _ in print(message) } }

        CrashReporting.enable(with: .init(appHangBacktraceEnabled: false), in: core)

        // When (a wrapper SDK enables Crash Reporting again with defaults)
        CrashReporting.enable(in: core)

        // Then
        XCTAssertEqual(appHangBacktraceEnabled(in: core), true, "The latest call wins")
        XCTAssertEqual(optOutWarnings(in: printFunction), 1, "Undoing an explicit opt-out must not pass unnoticed")
    }

    func testWhenCrashReportingIsReEnabledWithTheOptOut_itDoesNotWarn() {
        // Given (the app opts out *after* something else enabled Crash Reporting with defaults)
        let printFunction = PrintFunctionSpy()
        consolePrint = printFunction.print
        defer { consolePrint = { message, _ in print(message) } }

        CrashReporting.enable(in: core)

        // When
        CrashReporting.enable(with: .init(appHangBacktraceEnabled: false), in: core)

        // Then
        XCTAssertEqual(appHangBacktraceEnabled(in: core), false)
        XCTAssertEqual(
            optOutWarnings(in: printFunction),
            0,
            "This ends in the state the app asked for, so warning would report a correct outcome"
        )
    }

    func testWhenCrashReportingIsReEnabledWithTheSameOptOut_itDoesNotWarn() {
        // Given
        let printFunction = PrintFunctionSpy()
        consolePrint = printFunction.print
        defer { consolePrint = { message, _ in print(message) } }

        CrashReporting.enable(with: .init(appHangBacktraceEnabled: false), in: core)

        // When
        CrashReporting.enable(with: .init(appHangBacktraceEnabled: false), in: core)

        // Then
        XCTAssertEqual(appHangBacktraceEnabled(in: core), false)
        XCTAssertEqual(optOutWarnings(in: printFunction), 0, "Nothing changed")
    }

    func testGivenAppHangBacktracesDisabled_whenGeneratingBacktrace_itStillGeneratesIt() throws {
        #if os(watchOS)
        throw XCTSkip("Backtrace generation is not supported on watchOS")
        #endif
        // Given
        CrashReporting.enable(with: .init(appHangBacktraceEnabled: false), in: core)

        // Then
        XCTAssertEqual(appHangBacktraceEnabled(in: core), false)

        // Only the App Hangs consumer is gated - other consumers must keep working:
        let backtrace = try XCTUnwrap(core.backtraceReporter.generateBacktrace())
        XCTAssertGreaterThan(backtrace.threads.count, 0, "Some thread(s) should be recorded")
        XCTAssertGreaterThan(backtrace.binaryImages.count, 0, "Some binary image(s) should be recorded")
    }

    func testGivenCrashReportingNotEnabled_itPublishesNoOptOut() {
        // Then (nothing is published, so backtrace generation is *unavailable* rather than *disabled* - it is the
        // `?? true` fallback at the RUM call site, not this Feature, that decides what an absent configuration means)
        XCTAssertNil(appHangBacktraceEnabled(in: core))
    }

    func testGeneratingBacktraceOfTheMainThread() throws {
        #if os(watchOS)
        throw XCTSkip("Backtrace generation is not supported on watchOS")
        #endif
        // Given
        CrashReporting.enable(in: core)

        // When
        XCTAssertTrue(Thread.current.isMainThread)
        let threadID = Thread.currentThreadID
        let backtrace = try XCTUnwrap(core.backtraceReporter.generateBacktrace(threadID: threadID))

        // Then
        XCTAssertFalse(backtrace.stack.isEmpty)
        XCTAssertTrue(backtrace.stack.contains("XCTestCore"), "Main thread stack should include XCTestCore symbols")
    }

    func testGeneratingBacktraceOfSecondaryThread() throws {
        #if os(watchOS)
        throw XCTSkip("Backtrace generation is not supported on watchOS")
        #endif
        // Given
        CrashReporting.enable(in: core)

        // When
        let semaphore = DispatchSemaphore(value: 0)
        var threadID: ThreadID?

        let thread = Thread {
            XCTAssertFalse(Thread.current.isMainThread)
            threadID = Thread.currentThreadID
            semaphore.signal()
            Thread.sleep(forTimeInterval: 1)
        }

        thread.start()
        XCTAssertEqual(semaphore.wait(timeout: .now() + 5), .success)
        thread.cancel()

        let backtrace = try XCTUnwrap(core.backtraceReporter.generateBacktrace(threadID: threadID!))

        // Then
        XCTAssertFalse(backtrace.stack.isEmpty)
        XCTAssertFalse(backtrace.stack.contains("UIKit"), "Secondary thread stack should NOT include UIKit symbols")
    }
}
