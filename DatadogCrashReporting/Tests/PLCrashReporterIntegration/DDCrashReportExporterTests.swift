/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import CrashReporter

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
        let signalNames = [
            "SIGSIGNAL 0", "SIGHUP", "SIGINT", "SIGQUIT", "SIGILL", "SIGTRAP",
            "SIGABRT", "SIGEMT", "SIGFPE", "SIGKILL", "SIGBUS", "SIGSEGV", "SIGSYS",
            "SIGPIPE", "SIGALRM", "SIGTERM", "SIGURG", "SIGSTOP", "SIGTSTP", "SIGCONT",
            "SIGCHLD", "SIGTTIN", "SIGTTOU", "SIGIO", "SIGXCPU", "SIGXFSZ", "SIGVTALRM",
            "SIGPROF", "SIGWINCH", "SIGINFO", "SIGUSR1", "SIGUSR2"
        ]

        func readSignalDescriptionFromOS(signalName: String) -> String? {
            let knownSignalNames = Mirror(reflecting: sys_signame)
                .children
                .compactMap { $0.value as? UnsafePointer<Int8> }
                .map { String(cString: $0).uppercased() } // [HUP, INT, QUIT, ILL, TRAP, ABRT, ...]

            let knownSignalDescriptions = Mirror(reflecting: sys_siglist)
                .children
                .compactMap { $0.value as? UnsafePointer<Int8> }
                .map { String(cString: $0) } // [Hangup, Interrupt, Quit, Illegal instruction, ...]

            XCTAssertEqual(knownSignalNames.count, knownSignalDescriptions.count) // sanity check

            if let index = knownSignalNames.firstIndex(where: { signalName == "SIG\($0)" }) {
                return knownSignalDescriptions[index]
            } else {
                return nil
            }
        }

        signalNames.forEach { signalName in
            crashReport.signalInfo = .init(name: signalName, code: .mockAny(), address: .mockAny())

            let expectedSignalDescription = readSignalDescriptionFromOS(signalName: signalName)
            let expectedMessage = "Application crash: \(signalName) (\(expectedSignalDescription!))"

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
            .init(number: 0, libraryName: "Foo", libraryBaseAddress: 100, instructionPointer: 102),
            .init(number: 1, libraryName: "Foo", libraryBaseAddress: 100, instructionPointer: 112),
            .init(number: 2, libraryName: "Bar", libraryBaseAddress: 300, instructionPointer: 302),
            .init(number: 3, libraryName: "Bizz", libraryBaseAddress: 400, instructionPointer: 432),
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
            .init(number: 0, libraryName: "Foo", libraryBaseAddress: 100, instructionPointer: 102),
            .init(number: 1, libraryName: "Foo", libraryBaseAddress: 100, instructionPointer: 112),
            .init(number: 2, libraryName: "Bar", libraryBaseAddress: 300, instructionPointer: 302),
            .init(number: 3, libraryName: "Bizz", libraryBaseAddress: 400, instructionPointer: 432),
        ]
        let otherThreadStackFrames: [StackFrame] = [
            .init(number: 0, libraryName: "Foo", libraryBaseAddress: 100, instructionPointer: 110),
            .init(number: 1, libraryName: "Bazz", libraryBaseAddress: 500, instructionPointer: 550),
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
                number: index,
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

    func testWhenSomeSucceedingFramesInTheStackAreMissing_itPrintsNonconsecutiveFrameNumbers() {
        let stackFrames: [StackFrame] = [
            .init(number: 0, libraryName: "Foo", libraryBaseAddress: 100, instructionPointer: 102),
            .init(number: 1, libraryName: "Foo", libraryBaseAddress: 100, instructionPointer: 112),
            // missing line number: 2
            .init(number: 3, libraryName: "Bizz", libraryBaseAddress: 400, instructionPointer: 432),
            // missing line number: 4
            .init(number: 5, libraryName: "Bizz", libraryBaseAddress: 400, instructionPointer: 432),
        ]

        crashReport.exceptionInfo = .init(name: .mockAny(), reason: .mockAny(), stackFrames: stackFrames)
        let actualStack = exporter.export(crashReport).stack
        let expectedStack = """
        0   Foo                                 0x0000000000000066 0x64 + 2
        1   Foo                                 0x0000000000000070 0x64 + 12
        3   Bizz                                0x00000000000001b0 0x190 + 32
        5   Bizz                                0x00000000000001b0 0x190 + 32
        """

        XCTAssertEqual(actualStack, expectedStack)
    }

    func testWhenLastFrameInTheStackHasNoLibraryBaseAddress_itIsFilteredOut() {
        let stackFrames: [StackFrame] = [
            .init(number: 0, libraryName: "Foo", libraryBaseAddress: 100, instructionPointer: 102),
            .init(number: 1, libraryName: "Foo", libraryBaseAddress: 100, instructionPointer: 112),
            .init(number: 2, libraryName: "Bizz", libraryBaseAddress: 400, instructionPointer: 432),
            .init(number: 3, libraryName: "Bizz", libraryBaseAddress: nil, instructionPointer: 432),
        ]

        crashReport.exceptionInfo = .init(name: .mockAny(), reason: .mockAny(), stackFrames: stackFrames)

        let actualStack = exporter.export(crashReport).stack
        let expectedStack = """
        0   Foo                                 0x0000000000000066 0x64 + 2
        1   Foo                                 0x0000000000000070 0x64 + 12
        2   Bizz                                0x00000000000001b0 0x190 + 32
        """

        XCTAssertEqual(actualStack, expectedStack)
    }

    // MARK: - Formatting threads

    func testExportingThreads() {
        let crashedThreadStackFrames: [StackFrame] = [
            .init(number: 0, libraryName: "Foo", libraryBaseAddress: 100, instructionPointer: 102),
            .init(number: 1, libraryName: "Foo", libraryBaseAddress: 100, instructionPointer: 112),
            .init(number: 2, libraryName: "Bar", libraryBaseAddress: 300, instructionPointer: 302),
            .init(number: 3, libraryName: "Bizz", libraryBaseAddress: 400, instructionPointer: 432),
        ]
        let otherThreadStackFrames: [StackFrame] = [
            .init(number: 0, libraryName: "Foo", libraryBaseAddress: 100, instructionPointer: 110),
            .init(number: 1, libraryName: "Bazz", libraryBaseAddress: 500, instructionPointer: 550),
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

    func testWhenLastFrameInThreadStackHasNoLibraryBaseAddress_itIsNotFilteredOut() {
        let crashedThreadStackFrames: [StackFrame] = [
            .init(number: 0, libraryName: "Foo", libraryBaseAddress: 100, instructionPointer: 102),
            .init(number: 1, libraryName: "Foo", libraryBaseAddress: 100, instructionPointer: 112),
            .init(number: 2, libraryName: "Bizz", libraryBaseAddress: 400, instructionPointer: 432),
            .init(number: 3, libraryName: nil, libraryBaseAddress: nil, instructionPointer: 432),
        ]

        crashReport.threads = [
            .init(threadNumber: 0, crashed: true, stackFrames: crashedThreadStackFrames),
        ]

        let actualStack = exporter.export(crashReport).threads[0].stack
        let expectedStack = """
        0   Foo                                 0x0000000000000066 0x64 + 2
        1   Foo                                 0x0000000000000070 0x64 + 12
        2   Bizz                                0x00000000000001b0 0x190 + 32
        3   ???                                 0x00000000000001b0 0x0 + 0
        """

        XCTAssertEqual(actualStack, expectedStack)
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

    func testExportingBinaryImageWhenUUIDIsUnavailable() {
        // Given
        crashReport.binaryImages = [.mockWith(uuid: nil)]

        // When
        let exportedImages = exporter.export(crashReport).binaryImages

        // Then
        XCTAssertEqual(exportedImages.first?.uuid, "???")
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

    func testExportingProcess() {
        let randomName: String = .mockRandom()
        let randomID: UInt = .mockRandom()
        crashReport.processInfo = .mockWith(
            processName: randomName,
            processID: randomID
        )
        XCTAssertEqual(exporter.export(crashReport).meta.process, "\(randomName) [\(randomID)]")
    }

    func testExportingProcessID() {
        let randomID: UInt = .mockRandom()
        crashReport.processInfo = .mockWith(
            processName: nil,
            processID: randomID
        )
        XCTAssertEqual(exporter.export(crashReport).meta.process, "[\(randomID)]")
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

    func testExportingAdditionalTelemetry() {
        let randomFlag: Bool = .random()
        crashReport.wasTruncated = randomFlag
        XCTAssertEqual(exporter.export(crashReport).wasTruncated, randomFlag)
    }

    // MARK: - Comparing with PLCR text format

    func testExportedStacksHaveTheSameFormatAndValuesAsIfTheyWereExportedFromPLCR() throws {
        let crashReporter = try PLCrashReporter(configuration: .ddConfiguration())!

        // Given
        let plCrashReport = try PLCrashReport(
            data: try crashReporter.generateLiveReportAndReturnError()
        )

        // When
        let exporter = DDCrashReportExporter()
        let ddCrashReport = exporter.export(try CrashReport(from: plCrashReport))

        // Then
        let plcrTextFormat = PLCrashReportTextFormatter.stringValue(for: plCrashReport, with: PLCrashReportTextFormatiOS)!

        ddCrashReport.threads.forEach { thread in
            XCTAssertTrue(
                plcrTextFormat.contains(thread.stack),
                """
                Stack:
                ```
                \(thread.stack)
                ```

                does not appear in PLCR text format:
                ```
                \(plcrTextFormat)
                ```
                """
            )
        }
    }

    func testExportedBinaryImagesHaveTheSameValuesAsIfTheyWereExportedFromPLCR() throws {
        let crashReporter = try PLCrashReporter(configuration: .ddConfiguration())!

        // Given
        let plCrashReport = try PLCrashReport(
            data: try crashReporter.generateLiveReportAndReturnError()
        )

        // When
        let exporter = DDCrashReportExporter()
        let ddCrashReport = exporter.export(try CrashReport(from: plCrashReport))

        // Then
        let plcrTextFormat = PLCrashReportTextFormatter.stringValue(for: plCrashReport, with: PLCrashReportTextFormatiOS)!
        let plcrByLines = plcrTextFormat.split(separator: "\n").reversed() // matching in reversed report is 2x faster

        ddCrashReport.binaryImages.forEach { binaryImage in
            XCTAssertTrue(
                plcrByLines.contains { line in
                    // PLCR uses free-form text format, e.g.:
                    // `       0x10ce2e000 -        0x10ced9fff +Example x86_64  <aaf339bd11e1347a91fcefdce2714ad7> /.../Example.app/Example`
                    // Instead of matching the whole line, just checking if all values appear in the line should be enough:
                    let matchLoadAddress = line.contains(binaryImage.loadAddress)
                    let matchMaxAddress = line.contains(binaryImage.maxAddress)
                    let matchArchitecture = line.contains(binaryImage.architecture)
                    let matchLibraryName = line.contains(binaryImage.libraryName)
                    let matchUUID = line.contains(binaryImage.uuid)
                    return matchLoadAddress && matchMaxAddress && matchArchitecture && matchLibraryName && matchUUID
                }
            )
        }
    }

    // MARK: - Validate size of the Crash report

    func testPLCrashReporterWithSmallSizeForTheReport() throws {
        // Given
        let maxReportBytes: UInt = 1_024

        // When
        let crashReporter = try PLCrashReporter(configuration: .ddConfiguration(maxReportBytes: maxReportBytes))

        // Then
        var plCrashReport: PLCrashReport?
        do {
            // The generated report is bigger than the defined maxReportBytes
            let data = try crashReporter?.generateLiveReportAndReturnError()
            plCrashReport = try PLCrashReport(data: data)
        } catch {
            XCTAssertTrue(error.localizedDescription.matches(regex: "Could not decode crash report with size of (\\d+) bytes."))
        }

        XCTAssertNil(plCrashReport)
    }
}
