/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Reduces information in intermediate `CrashReport`:
/// - it removes binary images which are not necessary for symbolication,
/// - it removes less important stack frames from stack frames which exceed our limits.
internal struct CrashReportMinifier {
    struct Constants {
        /// The maximum number of stack frames in each stack trace.
        /// When stack trace exceeds this limit, it will be reduced by dropping less important frames.
        static let maxNumberOfStackFrames = 200
    }

    /// The maximum number of stack frames in each stack trace.
    let stackFramesLimit: Int

    init(stackFramesLimit: Int = Constants.maxNumberOfStackFrames) {
        self.stackFramesLimit = stackFramesLimit
    }

    func minify(crashReport: inout CrashReport) {
        var ifAnyStackFrameWasRemoved = false

        // Keep exception stack trace under limit:
        if let exceptionStackFrames = crashReport.exceptionInfo?.stackFrames {
            let reducedStackFrames = limit(stackFrames: exceptionStackFrames)
            ifAnyStackFrameWasRemoved = ifAnyStackFrameWasRemoved || (reducedStackFrames.count != exceptionStackFrames.count)
            crashReport.exceptionInfo?.stackFrames = reducedStackFrames
        }

        // Keep thread stack traces under limit:
        crashReport.threads = crashReport.threads.map { thread in
            var thread = thread
            let reducedStackFrames = limit(stackFrames: thread.stackFrames)
            ifAnyStackFrameWasRemoved = ifAnyStackFrameWasRemoved || (reducedStackFrames.count != thread.stackFrames.count)
            thread.stackFrames = reducedStackFrames
            return thread
        }

        // Set telemetry flag:
        crashReport.wasTruncated = ifAnyStackFrameWasRemoved

        // Remove binary images which are not referenced in any stack trace:
        crashReport.binaryImages = remove(
            binaryImages: crashReport.binaryImages,
            notUsedInAnyStackOf: crashReport
        )
    }

    // MARK: - Private

    /// Removes less important stack frames to ensure that their count is equal or below `stackFramesLimit`.
    /// Frames are removed at the middle of stack trace, which preserves the most important upper and bottom frames.
    private func limit(stackFrames: [StackFrame]) -> [StackFrame] {
        if stackFrames.count > stackFramesLimit {
            var frames = stackFrames

            let numberOfFramesToRemove = stackFrames.count - stackFramesLimit
            let middleFrameIndex = stackFrames.count / 2
            let lowerBound = middleFrameIndex - numberOfFramesToRemove / 2
            let upperBound = lowerBound + numberOfFramesToRemove

            frames.removeSubrange(lowerBound..<upperBound)

            return frames
        }
        return stackFrames
    }

    /// Removes binary images not referenced from any stack in given `CrashReport`.
    /// These images are not important for symbolication process, thus we can remove them.
    private func remove(binaryImages: [BinaryImageInfo], notUsedInAnyStackOf crashReport: CrashReport) -> [BinaryImageInfo] {
        var imageNamesFromStackFrames: Set<String> = []

        // Add image names from exception stack
        if let exceptionStackFrames = crashReport.exceptionInfo?.stackFrames {
            imageNamesFromStackFrames.formUnion(exceptionStackFrames.compactMap { $0.libraryName })
        }

        // Add image names from thread stacks
        crashReport.threads.forEach { thread in
            imageNamesFromStackFrames.formUnion(thread.stackFrames.compactMap { $0.libraryName })
        }

        return binaryImages.filter { image in
            return imageNamesFromStackFrames.contains(image.imageName) // if it's referenced in the stack trace
        }
    }
}
