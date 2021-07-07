/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog
@testable import DatadogCrashReporting

class DDCrashReportExporterTests: XCTestCase {
    private let exporter = DDCrashReportExporter()
    private var crashReport: CrashReport = .mockAny()

    // MARK: - Formatting `error.type`

    func testExportingErrorType() {
        crashReport.signalInfo = .init(name: "SIGNAME", code: "SIG_CODE", address: .mockAny())
        XCTAssertEqual(exporter.export(crashReport).type, "SIGNAME (SIG_CODE)")

        crashReport.signalInfo = .init(name: "SIGNAME", code: nil, address: .mockAny())
        XCTAssertEqual(exporter.export(crashReport).type, "SIGNAME (<unknown>)")

        crashReport.signalInfo = .init(name: nil, code: "SIG_CODE", address: .mockAny())
        XCTAssertEqual(exporter.export(crashReport).type, "<unknown> (SIG_CODE)")

        crashReport.signalInfo = .init(name: nil, code: nil, address: .mockAny())
        XCTAssertEqual(exporter.export(crashReport).type, "<unknown> (<unknown>)")
    }

    // MARK: - Formatting `error.message`

    func testExportingErrorMessageFromExceptionInfo() {
        crashReport.exceptionInfo = .init(name: "ExceptionName", reason: "Exception reason", stackFrames: [])
        XCTAssertEqual(
            exporter.export(crashReport).message,
            "Terminating app due to uncaught exception 'ExceptionName', reason: 'Exception reason'."
        )

        crashReport.exceptionInfo = .init(name: "ExceptionName", reason: nil, stackFrames: [])
        XCTAssertEqual(
            exporter.export(crashReport).message,
            "Terminating app due to uncaught exception 'ExceptionName', reason: '<unknown>'."
        )

        crashReport.exceptionInfo = .init(name: nil, reason: "Exception reason", stackFrames: [])
        XCTAssertEqual(
            exporter.export(crashReport).message,
            "Terminating app due to uncaught exception '<unknown>', reason: 'Exception reason'."
        )
    }

    func testExportingErrorMessageFromSignalInfo() throws {
        let signalDescriptionByName = [
            "SIGSIGNAL 0": "Signal 0",
            "SIGHUP": "Hangup",
            "SIGINT": "Interrupt",
            "SIGQUIT": "Quit",
            "SIGILL": "Illegal instruction",
            "SIGTRAP": "Trace/BPT trap",
            "SIGABRT": "Abort trap",
            "SIGEMT": "EMT trap",
            "SIGFPE": "Floating point exception",
            "SIGKILL": "Killed",
            "SIGBUS": "Bus error",
            "SIGSEGV": "Segmentation fault",
            "SIGSYS": "Bad system call",
            "SIGPIPE": "Broken pipe",
            "SIGALRM": "Alarm clock",
            "SIGTERM": "Terminated",
            "SIGURG": "Urgent I/O condition",
            "SIGSTOP": "Suspended (signal)",
            "SIGTSTP": "Suspended",
            "SIGCONT": "Continued",
            "SIGCHLD": "Child exited",
            "SIGTTIN": "Stopped (tty input)",
            "SIGTTOU": "Stopped (tty output)",
            "SIGIO": "I/O possible",
            "SIGXCPU": "Cputime limit exceeded",
            "SIGXFSZ": "Filesize limit exceeded",
            "SIGVTALRM": "Virtual timer expired",
            "SIGPROF": "Profiling timer expired",
            "SIGWINCH": "Window size changes",
            "SIGINFO": "Information request",
            "SIGUSR1": "User defined signal 1",
            "SIGUSR2": "User defined signal 2",
        ]

        signalDescriptionByName.forEach { signalName, signalDescription in
            crashReport.signalInfo = .init(name: signalName, code: .mockAny(), address: .mockAny())

            let expectedMessage = "Application crash: \(signalName) (\(signalDescription))"
            XCTAssertEqual(exporter.export(crashReport).message, expectedMessage)
        }
    }

    func testExportingErrorMessageWhenBothSignalAndExceptionInfoAreUnavailable() {
        crashReport.signalInfo = nil
        crashReport.exceptionInfo = nil
        XCTAssertEqual(exporter.export(crashReport).message, "Application crash: <unknown>")
    }

    func testExportingErrorMessageWhenBothSignalAndExceptionInfoAreAvailable() {
        crashReport.signalInfo = .init(name: "SIGHUP", code: .mockAny(), address: .mockAny())
        crashReport.exceptionInfo = .init(name: "ExceptionName", reason: "Exception reason", stackFrames: [])
        XCTAssertEqual(
            exporter.export(crashReport).message,
            "Terminating app due to uncaught exception 'ExceptionName', reason: 'Exception reason'.",
            "It should prefer exception information"
        )
    }

    // MARK: - Formatting `error.stack`

    func testExportingErrorStackFromExceptionInfo() {
        let stackFrames: [StackFrame] = [
            .init(libraryName: "Foo", libraryBaseAddress: 100, instructionPointer: 102),
            .init(libraryName: "Foo", libraryBaseAddress: 100, instructionPointer: 112),
            .init(libraryName: "Bar", libraryBaseAddress: 300, instructionPointer: 302),
            .init(libraryName: "Bizz", libraryBaseAddress: 400, instructionPointer: 432),
        ]

        crashReport.exceptionInfo = .init(name: .mockAny(), reason: .mockAny(), stackFrames: stackFrames)
        let expectedStack = """
        0   Foo                                 0x0000000000000066 0x64 + 2
        1   Foo                                 0x0000000000000070 0x64 + 12
        2   Bar                                 0x000000000000012e 0x12c + 2
        3   Bizz                                0x00000000000001b0 0x190 + 32
        """

        XCTAssertEqual(exporter.export(crashReport).stack, expectedStack)
    }

    func testExportingErrorStackFromThreadInfo() {
        let crashedThreadStackFrames: [StackFrame] = [
            .init(libraryName: "Foo", libraryBaseAddress: 100, instructionPointer: 102),
            .init(libraryName: "Foo", libraryBaseAddress: 100, instructionPointer: 112),
            .init(libraryName: "Bar", libraryBaseAddress: 300, instructionPointer: 302),
            .init(libraryName: "Bizz", libraryBaseAddress: 400, instructionPointer: 432),
        ]
        let otherThreadStackFrames: [StackFrame] = [
            .init(libraryName: "Foo", libraryBaseAddress: 100, instructionPointer: 110),
            .init(libraryName: "Bazz", libraryBaseAddress: 500, instructionPointer: 550),
        ]

        crashReport.exceptionInfo = nil
        crashReport.threads = [
            .init(threadNumber: 0, crashed: false, stackFrames: otherThreadStackFrames),
            .init(threadNumber: 1, crashed: true, stackFrames: crashedThreadStackFrames),
            .init(threadNumber: 2, crashed: false, stackFrames: otherThreadStackFrames),
        ]

        let expectedStack = """
        0   Foo                                 0x0000000000000066 0x64 + 2
        1   Foo                                 0x0000000000000070 0x64 + 12
        2   Bar                                 0x000000000000012e 0x12c + 2
        3   Bizz                                0x00000000000001b0 0x190 + 32
        """

        XCTAssertEqual(exporter.export(crashReport).stack, expectedStack)
    }

    func testExportingErrorStackWhenBothThreadAndExceptionInfoAreUnavailable() {
        crashReport.exceptionInfo = nil
        crashReport.threads = []
        XCTAssertEqual(exporter.export(crashReport).stack, "???")
    }

    func testExportingVeryLongErrorStack() {
        let stackFrames: [StackFrame] = (0..<10_024).map { index in
            StackFrame(
                libraryName: "VeryLongLibraryName-abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ-\(index)",
                libraryBaseAddress: 100,
                instructionPointer: 102
            )
        }
        crashReport.exceptionInfo = .init(name: .mockAny(), reason: .mockAny(), stackFrames: stackFrames)

        let exportedStack = exporter.export(crashReport).stack
        let lastExportedStackFrame = exportedStack.split(separator: "\n").last!

        XCTAssertEqual(
            "10023 VeryLongLibraryName-abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ-10023 0x0000000000000066 0x64 + 2",
            lastExportedStackFrame
        )
    }

    // MARK: - Formatting threads

    func testExportingThreads() {
        let crashedThreadStackFrames: [StackFrame] = [
            .init(libraryName: "Foo", libraryBaseAddress: 100, instructionPointer: 102),
            .init(libraryName: "Foo", libraryBaseAddress: 100, instructionPointer: 112),
            .init(libraryName: "Bar", libraryBaseAddress: 300, instructionPointer: 302),
            .init(libraryName: "Bizz", libraryBaseAddress: 400, instructionPointer: 432),
        ]
        let otherThreadStackFrames: [StackFrame] = [
            .init(libraryName: "Foo", libraryBaseAddress: 100, instructionPointer: 110),
            .init(libraryName: "Bazz", libraryBaseAddress: 500, instructionPointer: 550),
        ]

        crashReport.threads = [
            .init(threadNumber: 0, crashed: false, stackFrames: otherThreadStackFrames),
            .init(threadNumber: 1, crashed: true, stackFrames: crashedThreadStackFrames),
            .init(threadNumber: 2, crashed: false, stackFrames: otherThreadStackFrames),
        ]

        let exportedThreads = exporter.export(crashReport).threads

        let expectedCrashedThreadStack = """
        0   Foo                                 0x0000000000000066 0x64 + 2
        1   Foo                                 0x0000000000000070 0x64 + 12
        2   Bar                                 0x000000000000012e 0x12c + 2
        3   Bizz                                0x00000000000001b0 0x190 + 32
        """
        let expectedOtherThreadStack = """
        0   Foo                                 0x000000000000006e 0x64 + 10
        1   Bazz                                0x0000000000000226 0x1f4 + 50
        """

        XCTAssertEqual(exportedThreads.count, 3)
        XCTAssertEqual(exportedThreads[0].name, "Thread 0")
        XCTAssertFalse(exportedThreads[0].crashed)
        XCTAssertEqual(exportedThreads[0].stack, expectedOtherThreadStack)

        XCTAssertEqual(exportedThreads[1].name, "Thread 1")
        XCTAssertTrue(exportedThreads[1].crashed)
        XCTAssertEqual(exportedThreads[1].stack, expectedCrashedThreadStack)

        XCTAssertEqual(exportedThreads[2].name, "Thread 2")
        XCTAssertFalse(exportedThreads[2].crashed)
        XCTAssertEqual(exportedThreads[2].stack, expectedOtherThreadStack)
    }

    // MARK: - Formatting binary images

    func testExportingBinaryImages() {
        let architectureName: String = .mockRandom()
        crashReport.binaryImages = (0..<10).map { index in
            .mockWith(
                uuid: "uuid-\(index)",
                imageName: "image\(index)",
                isSystemImage: index % 2 == 0,
                architectureName: architectureName
            )
        }

        let exportedImages = exporter.export(crashReport).binaryImages

        XCTAssertEqual(exportedImages.count, 10)
        exportedImages.enumerated().forEach { index, exportedImage in
            XCTAssertEqual(exportedImage.uuid, "uuid-\(index)")
            XCTAssertEqual(exportedImage.libraryName, "image\(index)")
            XCTAssertEqual(exportedImage.isSystemLibrary, index % 2 == 0)
            XCTAssertEqual(exportedImage.architecture, architectureName)
        }
    }

    func testExportingBinaryImageAddressRange() throws {
        let randomImageLoadAddress: UInt64 = .mockRandom()
        let randomImageSize: UInt64 = .mockRandom()

        crashReport.binaryImages = [.mockWith(imageBaseAddress: randomImageLoadAddress, imageSize: randomImageSize)]
        let exportedImage = try XCTUnwrap(exporter.export(crashReport).binaryImages.first)

        let expectedLoadAddress = "0x" + randomImageLoadAddress.toHex
        let offset = max(1, randomImageSize.subtractIfNoOverflow(1) ?? randomImageSize)
        let expectedMaxAddress = "0x" + (randomImageLoadAddress.addIfNoOverflow(offset) ?? randomImageLoadAddress).toHex

        XCTAssertEqual(exportedImage.loadAddress, expectedLoadAddress)
        XCTAssertEqual(exportedImage.maxAddress, expectedMaxAddress)
    }

    // MARK: - Formatting other values

    func testExportingReportDate() {
        let randomDate: Date = .mockRandomInThePast()
        crashReport.systemInfo = .init(timestamp: randomDate)
        XCTAssertEqual(exporter.export(crashReport).date, randomDate)
    }

    func testExportingIncidentIdentifier() {
        let randomIdentifier: String = .mockRandom()
        crashReport.incidentIdentifier = randomIdentifier
        XCTAssertEqual(exporter.export(crashReport).meta.incidentIdentifier, randomIdentifier)
    }

    func testExportingProcessName() {
        let randomName: String = .mockRandom()
        crashReport.processInfo = .mockWith(processName: randomName)
        XCTAssertEqual(exporter.export(crashReport).meta.processName, randomName)
    }

    func testExportingParentProcess() {
        let randomName: String = .mockRandom()
        let randomID: UInt = .mockRandom()

        crashReport.processInfo = .mockWith(parentProcessID: randomID, parentProcessName: randomName)
        XCTAssertEqual(exporter.export(crashReport).meta.parentProcess, "\(randomName) [\(randomID)]")

        crashReport.processInfo = .mockWith(parentProcessID: randomID, parentProcessName: nil)
        XCTAssertEqual(exporter.export(crashReport).meta.parentProcess, "[\(randomID)]")
    }

    func testExportingProcessPath() {
        let randomPath: String = .mockRandom()
        crashReport.processInfo = .mockWith(processPath: randomPath)
        XCTAssertEqual(exporter.export(crashReport).meta.path, randomPath)
    }

    func testExportingCodeType() {
        let randomArchitectureName: String = .mockRandom()
        crashReport.binaryImages = [.mockWith(architectureName: randomArchitectureName)]
        XCTAssertEqual(exporter.export(crashReport).meta.codeType, randomArchitectureName)
    }

    func testExportingExceptionType() {
        let randomName: String = .mockRandom()
        crashReport.signalInfo = .init(name: randomName, code: .mockAny(), address: .mockAny())
        XCTAssertEqual(exporter.export(crashReport).meta.exceptionType, randomName)
    }

    func testExportingExceptionCodes() {
        let randomCode: String = .mockRandom()
        crashReport.signalInfo = .init(name: .mockAny(), code: randomCode, address: .mockAny())
        XCTAssertEqual(exporter.export(crashReport).meta.exceptionCodes, randomCode)
    }

    func testExportingContext() throws {
        let randomData: Data = .mockRandom()
        crashReport.contextData = randomData
        XCTAssertEqual(exporter.export(crashReport).context, randomData)
    }
}
