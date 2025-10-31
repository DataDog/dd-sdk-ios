/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import KSCrashRecording
@testable import DatadogCrashReporting

class DatadogMinifyFilterTests: XCTestCase {
    // MARK: - Binary Images Filtering

    func testMinify_RemovesUnreferencedBinaryImages() throws {
        // Given
        let filter = DatadogMinifyFilter()
        let json = """
        {
            "crash": {
                "threads": [{
                    "backtrace": {
                        "contents": [
                            {"object_addr": 4096},
                            {"object_addr": 8192}
                        ]
                    }
                }]
            },
            "binary_images": [
                {"image_addr": 4096},
                {"image_addr": 8192},
                {"image_addr": 12288},
                {"image_addr": 16384}
            ]
        }
        """.data(using: .utf8)!

        let dict = try XCTUnwrap(JSONSerialization.jsonObject(with: json) as? [String: Any])
        let report = CrashFieldDictionary(from: dict)

        // When
        let minified = try filter.minify(report: report)

        // Then
        let binaryImages: [CrashFieldDictionary] = try minified.value(forKey: .binaryImages)
        XCTAssertEqual(binaryImages.count, 2)
        try XCTAssertEqual(binaryImages[0].value(forKey: .imageAddress), 4_096)
        try XCTAssertEqual(binaryImages[1].value(forKey: .imageAddress), 8_192)
    }

    func testMinify_HandlesMultipleThreadsAndRecrashReport() throws {
        // Given
        let filter = DatadogMinifyFilter()
        let json = """
        {
            "crash": {
                "threads": [
                    {"backtrace": {"contents": [{"object_addr": 4096}]}},
                    {"backtrace": {"contents": [{"object_addr": 8192}]}}
                ]
            },
            "recrash_report": {
                "crash": {
                    "threads": [
                        {"backtrace": {"contents": [{"object_addr": 12288}]}}
                    ]
                }
            },
            "binary_images": [
                {"image_addr": 4096},
                {"image_addr": 8192},
                {"image_addr": 12288},
                {"image_addr": 36864}
            ]
        }
        """.data(using: .utf8)!

        let dict = try XCTUnwrap(JSONSerialization.jsonObject(with: json) as? [String: Any])
        let report = CrashFieldDictionary(from: dict)

        // When
        let minified = try filter.minify(report: report)

        // Then
        let binaryImages: [CrashFieldDictionary] = try minified.value(forKey: .binaryImages)
        XCTAssertEqual(binaryImages.count, 3)
        try XCTAssertEqual(binaryImages[0].value(forKey: .imageAddress), 4_096)
        try XCTAssertEqual(binaryImages[1].value(forKey: .imageAddress), 8_192)
        try XCTAssertEqual(binaryImages[2].value(forKey: .imageAddress), 12_288)
    }

    // MARK: - Stack Frame Limiting

    func testMinify_LimitsStackFramesWhenExceedingLimit() throws {
        // Given
        let filter = DatadogMinifyFilter(stackFramesLimit: 5)
        let json = """
        {
            "crash": {
                "threads": [{
                    "backtrace": {
                        "contents": [
                            {"object_addr": 0}, {"object_addr": 1}, {"object_addr": 2},
                            {"object_addr": 3}, {"object_addr": 4}, {"object_addr": 5},
                            {"object_addr": 6}, {"object_addr": 7}, {"object_addr": 8},
                            {"object_addr": 9}
                        ]
                    }
                }]
            },
            "binary_images": []
        }
        """.data(using: .utf8)!

        let dict = try XCTUnwrap(JSONSerialization.jsonObject(with: json) as? [String: Any])
        let report = CrashFieldDictionary(from: dict)

        // When
        let minified = try filter.minify(report: report)

        // Then
        let threads: [CrashFieldDictionary] = try minified.value(forKey: .crash, .threads)
        let backtrace: [CrashFieldDictionary] = try threads[0].value(forKey: .backtrace, .contents)
        XCTAssertEqual(backtrace.count, 5)
        try XCTAssertTrue(threads[0].value(forKey: .backtrace, .truncated))
    }

    func testMinify_DoesNotLimitStackFramesWhenBelowLimit() throws {
        // Given
        let filter = DatadogMinifyFilter(stackFramesLimit: 10)
        let json = """
        {
            "crash": {
                "threads": [{
                    "backtrace": {
                        "contents": [
                            {"object_addr": 0}, {"object_addr": 1}, {"object_addr": 2},
                            {"object_addr": 3}, {"object_addr": 4}
                        ]
                    }
                }]
            },
            "binary_images": []
        }
        """.data(using: .utf8)!

        let dict = try XCTUnwrap(JSONSerialization.jsonObject(with: json) as? [String: Any])
        let report = CrashFieldDictionary(from: dict)

        // When
        let minified = try filter.minify(report: report)

        // Then
        let threads: [CrashFieldDictionary] = try minified.value(forKey: .crash, .threads)
        let backtrace: [CrashFieldDictionary] = try threads[0].value(forKey: .backtrace, .contents)
        XCTAssertEqual(backtrace.count, 5)

        let truncated: Bool? = try threads[0].valueIfPresent(forKey: .backtrace, .truncated)
        XCTAssertNil(truncated)
    }

    func testMinify_RemovesMiddleFramesWhenLimiting() throws {
        // Given - 10 frames, limit to 6
        let filter = DatadogMinifyFilter(stackFramesLimit: 6)
        let json = """
        {
            "crash": {
                "threads": [{
                    "backtrace": {
                        "contents": [
                            {"object_addr": 0, "marker": "frame_0"},
                            {"object_addr": 100, "marker": "frame_1"},
                            {"object_addr": 200, "marker": "frame_2"},
                            {"object_addr": 300, "marker": "frame_3"},
                            {"object_addr": 400, "marker": "frame_4"},
                            {"object_addr": 500, "marker": "frame_5"},
                            {"object_addr": 600, "marker": "frame_6"},
                            {"object_addr": 700, "marker": "frame_7"},
                            {"object_addr": 800, "marker": "frame_8"},
                            {"object_addr": 900, "marker": "frame_9"}
                        ]
                    }
                }]
            },
            "binary_images": []
        }
        """.data(using: .utf8)!

        let dict = try XCTUnwrap(JSONSerialization.jsonObject(with: json) as? [String: Any])
        let report = CrashFieldDictionary(from: dict)

        // When
        let minified = try filter.minify(report: report)

        // Then - should keep top and bottom frames, remove middle ones
        let threads: [CrashFieldDictionary] = try minified.value(forKey: .crash, .threads)
        let backtrace: [CrashFieldDictionary] = try threads[0].value(forKey: .backtrace, .contents)
        XCTAssertEqual(backtrace.count, 6)

        // Verify we kept the top frames and bottom frames
        try XCTAssertEqual(backtrace[0].value(forKey: .key("marker")), "frame_0")
        try XCTAssertEqual(backtrace[1].value(forKey: .key("marker")), "frame_1")
        try XCTAssertEqual(backtrace[4].value(forKey: .key("marker")), "frame_8")
        try XCTAssertEqual(backtrace[5].value(forKey: .key("marker")), "frame_9")
    }

    // MARK: - Filter Integration

    func testFilterReports_ProcessesReportSuccessfully() throws {
        // Given
        let filter = DatadogMinifyFilter()
        let json = """
        {
            "crash": {
                "threads": [{
                    "backtrace": {
                        "contents": [{"object_addr": 4096}]
                    }
                }]
            },
            "binary_images": [
                {"image_addr": 4096},
                {"image_addr": 36864}
            ]
        }
        """.data(using: .utf8)!

        let dict = try XCTUnwrap(JSONSerialization.jsonObject(with: json) as? [String: Any])
        let inputDict = CrashFieldDictionary(from: dict)
        let report = AnyCrashReport(inputDict)
        var capturedReports: [CrashReport]?
        var capturedError: Error? = NSError()

        // When
        filter.filterReports([report]) { reports, error in
            capturedReports = reports
            capturedError = error
        }

        // Then
        XCTAssertNil(capturedError)
        XCTAssertEqual(capturedReports?.count, 1)

        let outputDict = try XCTUnwrap(capturedReports?.first?.untypedValue as? CrashFieldDictionary)
        let binaryImages: [CrashFieldDictionary] = try outputDict.value(forKey: .binaryImages)
        XCTAssertEqual(binaryImages.count, 1)
        try XCTAssertEqual(binaryImages[0].value(forKey: .imageAddress), 4_096)
    }

    func testFilterReports_ReturnsErrorForInvalidReportType() throws {
        // Given
        let filter = DatadogMinifyFilter()
        let invalidReport = AnyCrashReport("not a dictionary")
        var capturedReports: [CrashReport]? = []
        var capturedError: Error?

        // When
        filter.filterReports([invalidReport]) { reports, error in
            capturedReports = reports
            capturedError = error
        }

        // Then
        XCTAssertNotNil(capturedReports)
        XCTAssertNotNil(capturedError)

        let exception = try XCTUnwrap(capturedError as? CrashReportException)
        XCTAssertTrue(exception.description.contains("not a CrashDictionary"))
    }
}
