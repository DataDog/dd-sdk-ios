/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
// swiftlint:disable duplicate_imports
#if COCOAPODS
import KSCrash
#elseif swift(>=6.0)
internal import KSCrashRecording
#else
@_implementationOnly import KSCrashRecording
#endif
// swiftlint:enable duplicate_imports

internal final class DatadogMinifyFilter: NSObject, CrashReportFilter {
    struct Constants {
        /// The maximum number of stack frames in each stack trace.
        /// When stack trace exceeds this limit, it will be reduced by dropping less important frames.
        static let maxNumberOfStackFrames = 200
    }

    /// The maximum number of stack frames in each stack trace.
    let stackFramesLimit: Int

    required init(stackFramesLimit: Int = Constants.maxNumberOfStackFrames) {
        self.stackFramesLimit = stackFramesLimit
        super.init()
    }

    /// Filter the specified reports.
    ///
    /// - Parameters:
    ///   - reports: The reports to process.
    ///   - onCompletion: Block to call when processing is complete.
    func filterReports(
        _ reports: [CrashReport],
        onCompletion: (([CrashReport]?, (Error)?) -> Void)?
    ) {
        do {
            let reports = try reports.map { report in
                // Validate and extract the type-safe report dictionary
                guard let dict = report.untypedValue as? CrashFieldDictionary else {
                    throw CrashReportException(description: "KSCrash report untypedValue is not a CrashDictionary")
                }

                return try AnyCrashReport(minify(report: dict))
            }

            onCompletion?(reports, nil)
        } catch {
            onCompletion?(reports, error)
        }
    }

    /// Minifies a crash report by removing unused binary images.
    ///
    /// This method reduces the crash report size by filtering out binary images (libraries/frameworks)
    /// that don't appear in any thread's backtrace. Only binary images that are actually referenced
    /// in stack frames are kept.
    ///
    /// ## Algorithm
    ///
    /// 1. Collects all `object_addr` values from all thread backtraces into a set
    /// 2. Filters `binary_images` to keep only those whose `image_addr` appears in the set
    ///
    /// - Parameter report: The crash report to minify
    /// - Returns: A minified crash report with only referenced binary images
    /// - Throws: `CrashReportException` if report structure is invalid
    func minify(report: CrashFieldDictionary) throws -> CrashFieldDictionary {
        var minifiedReport = report
        var objectAddresses: Set<Int64> = []

        if var threads: [CrashFieldDictionary] = try report.valueIfPresent(forKey: .crash, .threads) {
            threads = try threads.map { try self.minify(thread: $0, objectAddresses: &objectAddresses) }
            minifiedReport.setValue(forKey: .crash, .threads, value: threads)
        }

        if var threads: [CrashFieldDictionary] = try report.valueIfPresent(forKey: .recrashReport, .crash, .threads) {
            threads = try threads.map { try self.minify(thread: $0, objectAddresses: &objectAddresses) }
            minifiedReport.setValue(forKey: .recrashReport, .crash, .threads, value: threads)
        }

        // Filter binary images to keep only those referenced in backtraces
        let binaryImages: [CrashFieldDictionary] = try report.value(forKey: .binaryImages)
        minifiedReport[.binaryImages] = try binaryImages.filter { image in
            try image.valueIfPresent(forKey: .imageAddress).map { objectAddresses.contains($0) } ?? false
        }

        return minifiedReport
    }

    private func minify(thread: CrashFieldDictionary, objectAddresses: inout Set<Int64>) throws -> CrashFieldDictionary {
        guard var backtrace: [CrashFieldDictionary] = try thread.valueIfPresent(forKey: .backtrace, .contents) else {
            return thread
        }

        let truncated = limit(backtrace: &backtrace)
        try objectAddresses.formUnion(backtrace.compactMap { try $0.valueIfPresent(forKey: .objectAddr) })

        guard truncated else {
            return thread
        }

        var thread = thread
        thread.setValue(forKey: .backtrace, .contents, value: backtrace)
        thread.setValue(forKey: .backtrace, .truncated, value: true)
        return thread
    }

    /// Removes less important stack frames to ensure that their count is equal or below `stackFramesLimit`.
    /// Frames are removed at the middle of stack trace, which preserves the most important upper and bottom frames.
    private func limit(backtrace frames: inout [CrashFieldDictionary]) -> Bool {
        guard frames.count > stackFramesLimit else {
            return false
        }

        let toRemove = frames.count - stackFramesLimit
        let middleFrameIndex = frames.count / 2
        let lowerBound = middleFrameIndex - toRemove / 2
        let upperBound = lowerBound + toRemove
        frames.removeSubrange(lowerBound..<upperBound)

        return true
    }
}
