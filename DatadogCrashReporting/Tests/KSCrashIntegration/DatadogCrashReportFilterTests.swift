/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogInternal
import TestUtilities
import KSCrashRecording
@testable import DatadogCrashReporting

class DatadogCrashReportFilterTests: XCTestCase {
    /// Regex pattern to match stack frame format: index library_name address load_address + offset
    /// Library name can contain spaces (e.g., "DatadogCrashReportingTests iOS")
    private let stackFrameRegex = try! NSRegularExpression(pattern: #"^(\d+)\s+(.+?)\s+(0x[0-9a-f]+)\s+(0x[0-9a-f]+)\s+\+\s+(\d+)$"#, options: [.anchorsMatchLines])

    private func parseStackFrame(_ frame: String) throws -> (index: Int, libraryName: String, instructionAddr: String, loadAddr: String, offset: Int) {
        let range = NSRange(frame.startIndex..., in: frame)
        guard
            let match = stackFrameRegex.firstMatch(in: frame, range: range),
            match.numberOfRanges == 6,
            let index           = Range(match.range(at: 1), in: frame)  .flatMap({ Int(frame[$0]) }),
            let libraryName     = Range(match.range(at: 2), in: frame)  .flatMap({ String(frame[$0]) }),
            let instructionAddr = Range(match.range(at: 3), in: frame)  .flatMap({ String(frame[$0]) }),
            let loadAddr        = Range(match.range(at: 4), in: frame)  .flatMap({ String(frame[$0]) }),
            let offset          = Range(match.range(at: 5), in: frame)  .flatMap({ Int(frame[$0]) })
        else {
            throw DDAssertError.expectedFailure("Stack trace of unexpected format")
        }

        return (index, libraryName, instructionAddr, loadAddr, offset)
    }

    func testFilterReports_ConvertsValidCrashReportToDDCrashReport() throws {
        // Given
        let json = """
        {
            "report": {
                "timestamp": "2025-10-22T14:14:12.007336Z",
                "id": "incident-123"
            },
            "system": {
                "cpu_arch": "arm64",
                "process_id": 12345,
                "process_name": "MyApp",
                "parent_process_id": 1,
                "parent_process_name": "launchd",
                "CFBundleExecutablePath": "/var/containers/Bundle/Application/MyApp"
            },
            "crash": {
                "error": {
                    "signal": {
                        "name": "SIGSEGV",
                        "code_name": "SEGV_MAPERR"
                    }
                },
                "diagnosis": "Application crash: SIGSEGV (Segmentation fault)",
                "threads": [
                    {
                        "index": 0,
                        "crashed": true,
                        "backtrace": {
                            "contents": [
                                {
                                    "instruction_addr": 4096,
                                    "object_addr": 4000,
                                    "object_name": "MyApp"
                                }
                            ]
                        }
                    }
                ]
            },
            "binary_images": [
                {
                    "name": "/var/containers/Bundle/Application/MyApp/MyApp",
                    "uuid": "12345678-1234-1234-1234-123456789012",
                    "image_addr": 4096,
                    "image_size": 8192,
                    "cpu_type": 16777228,
                    "cpu_subtype": 0
                }
            ],
            "user": {
                "dd": "🐶"
            }
        }
        """.data(using: .utf8)!

        let dict = try XCTUnwrap(JSONSerialization.jsonObject(with: json) as? [String: Any])
        let report = AnyCrashReport(CrashFieldDictionary(from: dict))
        let filter = DatadogCrashReportFilter()
        var capturedReports: [CrashReport]?

        // When
        filter.filterReports([report]) { reports, error in
            XCTAssertNil(error)
            capturedReports = reports
        }

        // Then
        XCTAssertEqual(capturedReports?.count, 1)
        let ddReport = try XCTUnwrap(capturedReports?.first?.untypedValue as? DDCrashReport)

        // Verify error type and message
        XCTAssertEqual(ddReport.type, "SIGSEGV (SEGV_MAPERR)", "Should format type as 'signal (code)'")
        XCTAssertEqual(ddReport.message, "Application crash: SIGSEGV (Segmentation fault)", "Should include signal description")

        // Verify metadata
        XCTAssertEqual(ddReport.meta.incidentIdentifier, "incident-123", "Should extract incident identifier")
        XCTAssertEqual(ddReport.meta.process, "MyApp [12345]", "Should format process as 'name [pid]'")
        XCTAssertEqual(ddReport.meta.parentProcess, "launchd [1]", "Should format parent process as 'name [pid]'")
        XCTAssertEqual(ddReport.meta.path, "/var/containers/Bundle/Application/MyApp", "Should extract executable path")
        XCTAssertEqual(ddReport.meta.codeType, "arm64", "Should extract architecture")
        XCTAssertEqual(ddReport.meta.exceptionType, "SIGSEGV", "Should extract exception type")
        XCTAssertEqual(ddReport.meta.exceptionCodes, "SEGV_MAPERR", "Should extract exception codes")

        // Verify threads
        XCTAssertEqual(ddReport.threads.count, 1, "Should have 1 thread")
        XCTAssertTrue(ddReport.threads[0].crashed, "Thread should be marked as crashed")
        XCTAssertEqual(ddReport.threads[0].name, "Thread 0", "Should default thread name")
        XCTAssertFalse(ddReport.threads[0].stack.isEmpty, "Thread should have stack")

        // Verify stack format using regex parser
        let stackLines = ddReport.stack.split(separator: "\n")
        XCTAssertEqual(stackLines.count, 1, "Should have 1 stack frame")

        let parsed = try parseStackFrame(String(stackLines[0]))
        XCTAssertEqual(parsed.index, 0, "Frame index should be 0")
        XCTAssertEqual(parsed.libraryName, "MyApp", "Library name should be MyApp")
        XCTAssertEqual(parsed.instructionAddr, "0x0000000000001000", "Instruction address should match")
        XCTAssertEqual(parsed.loadAddr, "0x0000000000000fa0", "Load address should match (4000 in hex)")
        XCTAssertEqual(parsed.offset, 96, "Offset should be 96 (4096 - 4000)")

        // Verify binary images
        XCTAssertEqual(ddReport.binaryImages.count, 1, "Should have 1 binary image")
        let binaryImage = ddReport.binaryImages[0]
        XCTAssertEqual(binaryImage.libraryName, "MyApp", "Should extract library name from path")
        XCTAssertEqual(binaryImage.uuid, "12345678-1234-1234-1234-123456789012", "Should preserve UUID")
        XCTAssertEqual(binaryImage.architecture, "arm64", "Should extract architecture")
        XCTAssertEqual(binaryImage.loadAddress, "0x0000000000001000", "Should format load address")
        XCTAssertEqual(binaryImage.maxAddress, "0x0000000000003000", "Should calculate max address")
        XCTAssertFalse(binaryImage.isSystemLibrary, "MyApp should not be a system library")

        // Verify context
        XCTAssertEqual(ddReport.context, Data(#"{"dd":"🐶"}"#.utf8), "Should decode context data")
        XCTAssertFalse(ddReport.wasTruncated, "Should not be truncated by default")
    }

    func testFilterReports_HandlesMinimalCrashReport() throws {
        // Given
        let json = """
        {
            "report": {
                "timestamp": "2025-10-22T14:14:12.007Z",
                "id": "incident-456"
            },
            "system": {
                "cpu_arch": "x86_64"
            },
            "crash": {
                "error": {
                    "signal": {}
                },
                "threads": []
            },
            "binary_images": []
        }
        """.data(using: .utf8)!

        let dict = try XCTUnwrap(JSONSerialization.jsonObject(with: json) as? [String: Any])
        let report = AnyCrashReport(CrashFieldDictionary(from: dict))
        let filter = DatadogCrashReportFilter()
        var capturedReports: [CrashReport]?

        // When
        filter.filterReports([report]) { reports, error in
            XCTAssertNil(error)
            capturedReports = reports
        }

        // Then
        let ddReport = try XCTUnwrap(capturedReports?.first?.untypedValue as? DDCrashReport)
        XCTAssertEqual(ddReport.type, "<unknown> (#0)")
        XCTAssertEqual(ddReport.message, "No crash reason provided")
        XCTAssertEqual(ddReport.stack, "???")
    }

    func testFilterReports_ExtractsCrashedThreadStack() throws {
        // Given
        let contextData = Data("test".utf8).base64EncodedString()
        let json = """
        {
            "report": {
                "timestamp": "2025-10-22T14:14:12Z",
                "id": "incident-789"
            },
            "system": {
                "cpu_arch": "arm64"
            },
            "crash": {
                "error": {
                    "signal": {
                        "name": "SIGABRT"
                    }
                },
                "threads": [
                    {
                        "index": 0,
                        "crashed": false,
                        "backtrace": {
                            "contents": [
                                {
                                    "instruction_addr": 1000,
                                    "object_addr": 900,
                                    "object_name": "libsystem"
                                }
                            ]
                        }
                    },
                    {
                        "index": 1,
                        "crashed": true,
                        "backtrace": {
                            "contents": [
                                {
                                    "instruction_addr": 5000,
                                    "object_addr": 4900,
                                    "object_name": "MyFramework"
                                },
                                {
                                    "instruction_addr": 5120,
                                    "object_addr": 4900,
                                    "object_name": "MyFramework"
                                }
                            ]
                        }
                    }
                ]
            },
            "binary_images": [],
            "user": {
                "dd": "\(contextData)"
            }
        }
        """.data(using: .utf8)!

        let dict = try XCTUnwrap(JSONSerialization.jsonObject(with: json) as? [String: Any])
        let report = AnyCrashReport(CrashFieldDictionary(from: dict))
        let filter = DatadogCrashReportFilter()
        var capturedReports: [CrashReport]?

        // When
        filter.filterReports([report]) { reports, error in
            capturedReports = reports
        }

        // Then
        let ddReport = try XCTUnwrap(capturedReports?.first?.untypedValue as? DDCrashReport)

        // Verify stack contains only crashed thread
        XCTAssertTrue(ddReport.stack.contains("MyFramework"), "Stack should contain crashed thread frames")
        XCTAssertFalse(ddReport.stack.contains("libsystem"), "Stack should not contain non-crashed thread frames")

        // Verify stack format using regex parser
        let stackLines = ddReport.stack.split(separator: "\n")
        XCTAssertEqual(stackLines.count, 2, "Should have 2 stack frames")

        // First frame: 0   MyFramework   0x0000000000001388 0x1324 + 100
        let firstFrame = try parseStackFrame(String(stackLines[0]))
        XCTAssertEqual(firstFrame.index, 0, "First frame index should be 0")
        XCTAssertEqual(firstFrame.libraryName, "MyFramework", "First frame library should be MyFramework")
        XCTAssertEqual(firstFrame.instructionAddr, "0x0000000000001388", "First frame instruction address should be 5000 in hex")
        XCTAssertEqual(firstFrame.loadAddr, "0x0000000000001324", "First frame load address should be 4900 in hex")
        XCTAssertEqual(firstFrame.offset, 100, "First frame offset should be 100 (5000 - 4900)")

        // Second frame: 1   MyFramework   0x0000000000001400 0x1324 + 220
        let secondFrame = try parseStackFrame(String(stackLines[1]))
        XCTAssertEqual(secondFrame.index, 1, "Second frame index should be 1")
        XCTAssertEqual(secondFrame.libraryName, "MyFramework", "Second frame library should be MyFramework")
        XCTAssertEqual(secondFrame.instructionAddr, "0x0000000000001400", "Second frame instruction address should be 5120 in hex")
        XCTAssertEqual(secondFrame.loadAddr, "0x0000000000001324", "Second frame load address should be 4900 in hex")
        XCTAssertEqual(secondFrame.offset, 220, "Second frame offset should be 220 (5120 - 4900)")

        // Verify threads
        XCTAssertEqual(ddReport.threads.count, 2, "Should have 2 threads")
        XCTAssertFalse(ddReport.threads[0].crashed, "First thread should not be crashed")
        XCTAssertTrue(ddReport.threads[1].crashed, "Second thread should be crashed")
        XCTAssertEqual(ddReport.threads[1].stack, ddReport.stack, "Crashed thread stack should match main stack")
    }

    func testFilterReports_DetectsSystemVsUserBinaryImages() throws {
        // Given
        let contextData = Data("test".utf8).base64EncodedString()
        let json = """
        {
            "report": {
                "timestamp": "2025-10-22T14:14:12Z",
                "id": "incident-999"
            },
            "system": {
                "cpu_arch": "arm64"
            },
            "crash": {
                "error": {
                    "signal": {}
                },
                "threads": []
            },
            "binary_images": [
                {
                    "name": "/Contents/Developer/Platforms/Frameworks/Foundation.framework/Foundation",
                    "uuid": "12345678-1234-1234-1234-123456789ABC",
                    "image_addr": 4096,
                    "image_size": 8192,
                    "cpu_type": 16777228,
                    "cpu_subtype": 0
                },
                {
                    "name": "/var/containers/Bundle/Application/MyApp/MyApp",
                    "uuid": "ABCDEF01-2345-6789-ABCD-EF0123456789",
                    "image_addr": 16384,
                    "image_size": 32768,
                    "cpu_type": 16777228,
                    "cpu_subtype": 0
                }
            ],
            "user": {
                "dd": "\(contextData)"
            }
        }
        """.data(using: .utf8)!

        let dict = try XCTUnwrap(JSONSerialization.jsonObject(with: json) as? [String: Any])
        let report = AnyCrashReport(CrashFieldDictionary(from: dict))
        let filter = DatadogCrashReportFilter()
        var capturedReports: [CrashReport]?

        // When
        filter.filterReports([report]) { reports, error in
            capturedReports = reports
        }

        // Then
        let ddReport = try XCTUnwrap(capturedReports?.first?.untypedValue as? DDCrashReport)
        XCTAssertEqual(ddReport.binaryImages.count, 2, "Should have 2 binary images")

        // Verify system image details
        let systemImage = try XCTUnwrap(ddReport.binaryImages.first { $0.libraryName == "Foundation" })
        XCTAssertEqual(systemImage.isSystemLibrary, true, "Foundation should be a system library")
        XCTAssertEqual(systemImage.uuid, "12345678-1234-1234-1234-123456789ABC", "Should preserve UUID")
        XCTAssertEqual(systemImage.architecture, "arm64", "Should extract architecture from system info")
        XCTAssertEqual(systemImage.loadAddress, "0x0000000000001000", "Should format load address as hex")
        XCTAssertEqual(systemImage.maxAddress, "0x0000000000003000", "Should calculate max address (load + size)")

        // Verify user image details
        let userImage = try XCTUnwrap(ddReport.binaryImages.first { $0.libraryName == "MyApp" })
        XCTAssertEqual(userImage.isSystemLibrary, false, "MyApp should be a user library")
        XCTAssertEqual(userImage.uuid, "ABCDEF01-2345-6789-ABCD-EF0123456789", "Should preserve UUID")
        XCTAssertEqual(userImage.architecture, "arm64", "Should extract architecture from system info")
        XCTAssertEqual(userImage.loadAddress, "0x0000000000004000", "Should format load address as hex")
        XCTAssertEqual(userImage.maxAddress, "0x000000000000c000", "Should calculate max address (load + size)")
    }

    func testFilterReports_MarksTruncatedBacktraces() throws {
        // Given
        let contextData = Data("test".utf8).base64EncodedString()
        let json = """
        {
            "report": {
                "timestamp": "2025-10-22T14:14:12Z",
                "id": "incident-truncated"
            },
            "system": {
                "cpu_arch": "arm64"
            },
            "crash": {
                "error": {
                    "signal": {}
                },
                "threads": [
                    {
                        "index": 0,
                        "crashed": true,
                        "backtrace": {
                            "contents": [
                                {
                                    "instruction_addr": 1000,
                                    "object_addr": 900,
                                    "object_name": "MyApp"
                                }
                            ],
                            "truncated": true
                        }
                    }
                ]
            },
            "binary_images": [],
            "user": {
                "dd": "\(contextData)"
            }
        }
        """.data(using: .utf8)!

        let dict = try XCTUnwrap(JSONSerialization.jsonObject(with: json) as? [String: Any])
        let report = AnyCrashReport(CrashFieldDictionary(from: dict))
        let filter = DatadogCrashReportFilter()
        var capturedReports: [CrashReport]?

        // When
        filter.filterReports([report]) { reports, error in
            capturedReports = reports
        }

        // Then
        let ddReport = try XCTUnwrap(capturedReports?.first?.untypedValue as? DDCrashReport)
        XCTAssertTrue(ddReport.wasTruncated)
    }

    func testFilterReports_ReturnsErrorForInvalidReportType() {
        // Given
        let report = AnyCrashReport(["invalid": "data"])
        let filter = DatadogCrashReportFilter()
        var capturedError: Error?

        // When
        filter.filterReports([report]) { reports, error in
            capturedError = error
        }

        // Then
        XCTAssertNotNil(capturedError)
        XCTAssertTrue(capturedError is CrashReportException)
    }

    func testFilterReports_HandlesMultipleReports() throws {
        // Given
        let contextData = Data("test".utf8).base64EncodedString()
        let json1 = """
        {
            "report": {"timestamp": "2025-10-22T14:14:12Z", "id": "1"},
            "system": {"cpu_arch": "arm64"},
            "crash": {"error": {"signal": {"name": "SIGSEGV"}}, "threads": []},
            "binary_images": [],
            "user": {"dd": "\(contextData)"}
        }
        """.data(using: .utf8)!
        let json2 = """
        {
            "report": {"timestamp": "2025-10-22T14:15:12Z", "id": "2"},
            "system": {"cpu_arch": "arm64"},
            "crash": {"error": {"signal": {"name": "SIGABRT"}}, "threads": []},
            "binary_images": [],
            "user": {"dd": "\(contextData)"}
        }
        """.data(using: .utf8)!

        let dict1 = try XCTUnwrap(JSONSerialization.jsonObject(with: json1) as? [String: Any])
        let dict2 = try XCTUnwrap(JSONSerialization.jsonObject(with: json2) as? [String: Any])
        let report1 = AnyCrashReport(CrashFieldDictionary(from: dict1))
        let report2 = AnyCrashReport(CrashFieldDictionary(from: dict2))
        let filter = DatadogCrashReportFilter()
        var capturedReports: [CrashReport]?

        // When
        filter.filterReports([report1, report2]) { reports, error in
            XCTAssertNil(error)
            capturedReports = reports
        }

        // Then
        XCTAssertEqual(capturedReports?.count, 2)
        let ddReport1 = try XCTUnwrap(capturedReports?[0].untypedValue as? DDCrashReport)
        let ddReport2 = try XCTUnwrap(capturedReports?[1].untypedValue as? DDCrashReport)
        XCTAssertEqual(ddReport1.meta.incidentIdentifier, "1")
        XCTAssertEqual(ddReport2.meta.incidentIdentifier, "2")
    }
}
