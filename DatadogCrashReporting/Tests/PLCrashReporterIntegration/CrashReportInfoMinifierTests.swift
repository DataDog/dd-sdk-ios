/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogCrashReporting

class CrashReportInfoMinifierTests: XCTestCase {
    private var crashReport: CrashReportInfo = .mockAny()

    // MARK: - Minimizing number of stack frames

    func tesWhenNumberOfStackFramesExceedsTheLimit_itRemovesFramesToFitTheLimit() {
        // Given
        let limit: Int = .mockRandom(min: 10, max: 2_048)
        let stackFrames: [StackFrame] = (0..<(limit * 2)).map { .mockWith(number: $0) }

        // When
        XCTAssertGreaterThan(stackFrames.count, limit)

        crashReport.wasTruncated = false
        crashReport.exceptionInfo = .mockWith(stackFrames: stackFrames)
        crashReport.threads = (0..<Int.mockRandom(min: 1, max: 10)).map { _ in ThreadInfo.mockWith(stackFrames: stackFrames) }

        // Then
        let minifier = CrashReportInfoMinifier(stackFramesLimit: limit)
        minifier.minify(crashReport: &crashReport)

        XCTAssertTrue(crashReport.wasTruncated)
        XCTAssertEqual(crashReport.exceptionInfo?.stackFrames.count, limit)
        crashReport.threads.forEach { thread in
            XCTAssertEqual(thread.stackFrames.count, limit)
        }
    }

    func tesWhenNumberOfStackFramesIsBelowTheLimit_itDoesNotRemoveAnyFrame() {
        // Given
        let limit: Int = .mockRandom(min: 10, max: 2_048)
        let stackFrames: [StackFrame] = (0..<(limit / 2)).map { .mockWith(number: $0) }

        // When
        XCTAssertLessThan(stackFrames.count, limit)

        crashReport.wasTruncated = false
        crashReport.exceptionInfo = .mockWith(stackFrames: stackFrames)
        crashReport.threads = (0..<Int.mockRandom(min: 1, max: 10)).map { _ in ThreadInfo.mockWith(stackFrames: stackFrames) }

        // Then
        let minifier = CrashReportInfoMinifier(stackFramesLimit: limit)
        minifier.minify(crashReport: &crashReport)

        XCTAssertFalse(crashReport.wasTruncated)
        XCTAssertEqual(crashReport.exceptionInfo?.stackFrames.count, stackFrames.count)
        crashReport.threads.forEach { thread in
            XCTAssertEqual(thread.stackFrames.count, stackFrames.count)
        }
    }

    func testWhenNumberOfStackFramesIsEqualToTheLimit_itDoesNotRemoveAnyFrame() {
        // Given
        let limit: Int = .mockRandom(min: 10, max: 2_048)
        let stackFrames: [StackFrame] = (0..<limit).map { .mockWith(number: $0) }

        // When
        XCTAssertEqual(stackFrames.count, limit)

        crashReport.wasTruncated = false
        crashReport.exceptionInfo = .mockWith(stackFrames: stackFrames)
        crashReport.threads = (0..<Int.mockRandom(min: 1, max: 10)).map { _ in ThreadInfo.mockWith(stackFrames: stackFrames) }

        // Then
        let minifier = CrashReportInfoMinifier(stackFramesLimit: limit)
        minifier.minify(crashReport: &crashReport)

        XCTAssertFalse(crashReport.wasTruncated)
        XCTAssertEqual(crashReport.exceptionInfo?.stackFrames.count, stackFrames.count)
        crashReport.threads.forEach { thread in
            XCTAssertEqual(thread.stackFrames.count, stackFrames.count)
        }
    }

    func testWhenRemovingFrames_itRemovesTheMiddleOnes() {
        crashReport.wasTruncated = false
        crashReport.exceptionInfo = .mockWith(
            stackFrames: (0..<3).map { .mockWith(number: $0) } // 3 frames
        )
        CrashReportInfoMinifier(stackFramesLimit: 2).minify(crashReport: &crashReport) // remove 1 frames
        XCTAssertTrue(crashReport.wasTruncated)
        XCTAssertEqual(crashReport.exceptionInfo?.stackFrames.count, 2)
        XCTAssertEqual(crashReport.exceptionInfo?.stackFrames[0].number, 0)
        XCTAssertEqual(crashReport.exceptionInfo?.stackFrames[1].number, 2)

        crashReport.wasTruncated = false
        crashReport.exceptionInfo = .mockWith(
            stackFrames: (0..<4).map { .mockWith(number: $0) } // 4 frames
        )
        CrashReportInfoMinifier(stackFramesLimit: 2).minify(crashReport: &crashReport) // remove 2 frames
        XCTAssertTrue(crashReport.wasTruncated)
        XCTAssertEqual(crashReport.exceptionInfo?.stackFrames.count, 2)
        XCTAssertEqual(crashReport.exceptionInfo?.stackFrames[0].number, 0)
        XCTAssertEqual(crashReport.exceptionInfo?.stackFrames[1].number, 3)

        crashReport.wasTruncated = false
        crashReport.exceptionInfo = .mockWith(
            stackFrames: (0..<5).map { .mockWith(number: $0) } // 4 frames
        )
        CrashReportInfoMinifier(stackFramesLimit: 3).minify(crashReport: &crashReport) // remove 2 frames
        XCTAssertTrue(crashReport.wasTruncated)
        XCTAssertEqual(crashReport.exceptionInfo?.stackFrames.count, 3)
        XCTAssertEqual(crashReport.exceptionInfo?.stackFrames[0].number, 0)
        XCTAssertEqual(crashReport.exceptionInfo?.stackFrames[1].number, 3)
        XCTAssertEqual(crashReport.exceptionInfo?.stackFrames[2].number, 4)
    }

    // MARK: - Minimizing number of binary images

    func testWhenReducingBinaryImages_itRemovesImagesNotReferencedInStackTrace() {
        // Given
        crashReport.binaryImages = [
            .mockWith(imageName: "library1"),
            .mockWith(imageName: "library2"),
            .mockWith(imageName: "library3"),
            .mockWith(imageName: "library4"),
        ]
        crashReport.exceptionInfo = .mockWith(
            stackFrames: [
                .mockWith(libraryName: "library1"),
                .mockWith(libraryName: "library3")
            ]
        )
        crashReport.threads = []

        // When
        let minifier = CrashReportInfoMinifier(stackFramesLimit: .max)
        minifier.minify(crashReport: &crashReport)

        // Then
        XCTAssertEqual(crashReport.binaryImages.count, 2)
        XCTAssertTrue(crashReport.binaryImages.contains(where: { $0.imageName == "library1" }))
        XCTAssertTrue(crashReport.binaryImages.contains(where: { $0.imageName == "library3" }))
    }

    func testWhenReducingBinaryImages_itPreservesImagesReferencedInAnyStackTrace() {
        // Given
        let limit: Int = .mockRandom(min: 30, max: 100)
        let numberOfFramesPerStack: Int = .mockRandom(min: limit, max: limit * 2) // random above the limit
        let numberOfThreads: Int = .mockRandom(min: 1, max: 10)

        let totalNumberOfStackFrames = numberOfFramesPerStack * (numberOfThreads + 1) // +1 for the exception stack
        let numberOfBinaryImages: Int = .mockRandom(
            min: totalNumberOfStackFrames + 1, // more than number of stack frames
            max: totalNumberOfStackFrames * 2
        )

        // create mock images:
        crashReport.binaryImages = (0..<numberOfBinaryImages)
            .map { "image\($0)" }
            .map { .mockWith(imageName: $0) }

        // create mock exception stack with frames referencing random `crashReport.binaryImages`:
        crashReport.exceptionInfo = .mockWith(
            stackFrames: (0..<numberOfFramesPerStack).map { frameNumber in
                .mockWith(libraryName: crashReport.binaryImages.randomElement()!.imageName)
            }
        )

        // create mock thread stacks with frames referencing random `crashReport.binaryImages`:
        crashReport.threads = (0..<numberOfThreads).map { threadNumber in
            .mockWith(
                threadNumber: threadNumber,
                stackFrames: (0..<numberOfFramesPerStack).map { frameNumber in
                    .mockWith(libraryName: crashReport.binaryImages.randomElement()!.imageName)
                }
            )
        }

        // When
        let minifier = CrashReportInfoMinifier(stackFramesLimit: limit)
        minifier.minify(crashReport: &crashReport)

        // Then
        var imageNamesFromStackFrames: Set<String> = []
        imageNamesFromStackFrames.formUnion(crashReport.exceptionInfo!.stackFrames.map { $0.libraryName! })
        imageNamesFromStackFrames.formUnion(crashReport.threads.flatMap { $0.stackFrames.map { $0.libraryName! } })

        var imageNamesFromBinaryImages: Set<String> = []
        imageNamesFromBinaryImages.formUnion(crashReport.binaryImages.map { $0.imageName })

        XCTAssertEqual(
            imageNamesFromStackFrames,
            imageNamesFromBinaryImages,
            "Reduced `crashReport.binaryImages` should only contain images referenced from stack frames"
        )
    }
}
