/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import Datadog

/// Exports intermediate `CrashReport` to `DDCrashReport`.
///
/// The responsibility of this component is to format crash information for integration with Error Tracking, namely:
/// * `error.type`,
/// * `error.message`,
/// * `error.stack`.
///
/// Next to the `error` information it exports thread stack frames and binary images for symbolication process. All stack traces
/// are formatted using Apple-like format. The implementation is based on the PLCR's formatter, ref.:
/// https://github.com/microsoft/plcrashreporter/blob/master/Source/PLCrashReportTextFormatter.m
internal struct DDCrashReportExporter {
    private let unknown = "<unknown>"
    private let unavailable = "???"
    /// Truncation mark printed in a stack trace in the place of stack frames that were removed.
    private let stackTraceTruncationMark = "..."

    func export(_ crashReport: CrashReport) -> DDCrashReport {
        let ddCrashReport = DDCrashReport(
            date: crashReport.systemInfo?.timestamp,
            type: formatType(for: crashReport),
            message: formatMessage(for: crashReport),
            stack: formatStack(for: crashReport),
            threads: threads(from: crashReport),
            binaryImages: binaryImages(from: crashReport),
            meta: meta(for: crashReport),
            wasTruncated: crashReport.wasTruncated,
            context: crashReport.contextData
        )

        // Dump in Apple format for testing symbolicator:
        var appleFormat = ""
        appleFormat += "Main stack:\n"
        appleFormat += ddCrashReport.stack
        appleFormat += "\n\n"

        for thread in ddCrashReport.threads {
            appleFormat += "Thread \(thread.name):\n"
            appleFormat += thread.stack
            appleFormat += "\n\n"
        }

        appleFormat += "Binary Images:\n"
        for image in ddCrashReport.binaryImages {
            appleFormat += "\(image.loadAddress) - \(image.maxAddress) \(image.libraryName) \(image.architecture) <\(image.uuid)> /image/path"
            appleFormat += "\n"
        }

        print("⚡️⚡️⚡️")
        print(appleFormat)
        print("⚡️⚡️⚡️")

        return ddCrashReport
    }

    // MARK: - Formatting `error.type`, `error.message` and `error.stack`

    /// Formats the error type - in Datadog Error Tracking this corresponds to `error.type`.
    ///
    /// **Note:** This value is used for building error's fingerprint in Error Tracking, thus its cardinality must be controlled.
    private func formatType(for crashReport: CrashReport) -> String {
        return "\(crashReport.signalInfo?.name ?? unknown) (\(crashReport.signalInfo?.code ?? unknown))"
    }

    /// Formats the error message - in Datadog Error Tracking this corresponds to `error.message`.
    ///
    /// **Note:** This value is used for building error's fingerprint in Error Tracking, thus its cardinality must be controlled.
    private func formatMessage(for crashReport: CrashReport) -> String {
        if let exception = crashReport.exceptionInfo {
            // If the crash was caused by an uncaught exception
            let exceptionName = exception.name ?? unknown // e.g. `NSInvalidArgumentException`
            let exceptionReason = exception.reason ?? unknown // e.g. `-[NSObject objectForKey:]: unrecognized selector sent to instance 0x...`
            return "Terminating app due to uncaught exception '\(exceptionName)', reason: '\(exceptionReason)'."
        } else {
            // Use signal description available in OS
            guard let signalName = crashReport.signalInfo?.name else { // e.g. SIGILL
                return "Application crash: \(unknown)"
            }

            let knownSignalNames = Mirror(reflecting: sys_signame)
                .children
                .compactMap { $0.value as? UnsafePointer<Int8> }
                .map { String(cString: $0).uppercased() } // [HUP, INT, QUIT, ILL, TRAP, ABRT, ...]

            let knownSignalDescriptions = Mirror(reflecting: sys_siglist)
                .children
                .compactMap { $0.value as? UnsafePointer<Int8> }
                .map { String(cString: $0) } // [Hangup, Interrupt, Quit, Illegal instruction, ...]

            if knownSignalNames.count == knownSignalDescriptions.count { // sanity check
                if let index = knownSignalNames.firstIndex(where: { signalName == "SIG\($0)" }) {
                    let signalDescription = knownSignalDescriptions[index]
                    return "Application crash: \(signalName) (\(signalDescription))"
                }
            }

            return "Application crash: \(unknown)"
        }
    }

    /// Formats the error stack - in Datadog Error Tracking this corresponds to `error.stack`.
    ///
    /// **Note:** This produces unsymbolicated stack trace, which is later symbolicated backend-side and used for building error's fingerprint in Error Tracking.
    private func formatStack(for crashReport: CrashReport) -> String {
        let crashedThread = crashReport.threads.first { $0.crashed }
        let exception = crashReport.exceptionInfo

        // Consider most meaningful stack trace in this order:
        // - uncaught exception stack trace (if available)
        // - crashed thread stack trace (must be available)
        // - first thread stack trace (sanity fallback)
        let mostMeaningfulStackFrames = exception?.stackFrames
            ?? crashedThread?.stackFrames
            ?? crashReport.threads.first?.stackFrames

        guard let stackFrames = mostMeaningfulStackFrames else {
            return unavailable // should never be reached
        }

        return string(from: stackFrames)
    }

    // MARK: - Exporting threads and binary images

    private func threads(from crashReport: CrashReport) -> [DDCrashReport.Thread] {
        return crashReport.threads.map { thread in
            return DDCrashReport.Thread(
                name: "Thread \(thread.threadNumber)",
                stack: string(from: thread.stackFrames),
                crashed: thread.crashed,
                state: nil // TODO: RUMM-1462 Send registers state for crashed thread
            )
        }
    }

    private func binaryImages(from crashReport: CrashReport) -> [DDCrashReport.BinaryImage] {
        return crashReport.binaryImages.map { image in
            // Ref. for this computation:
            // https://github.com/microsoft/plcrashreporter/blob/dbb05c0bc883bde1cfcad83e7add25862c95d11f/Source/PLCrashReportTextFormatter.m#L447
            let loadAddressHex = "0x\(image.imageBaseAddress.toHex)"
            var maxAddressOffset = image.imageSize.subtractIfNoOverflow(1) ?? image.imageSize
            maxAddressOffset = max(1, maxAddressOffset)
            let maxAddress = image.imageBaseAddress.addIfNoOverflow(maxAddressOffset) ?? image.imageBaseAddress
            let maxAddressHex = "0x\(maxAddress.toHex)"

            return DDCrashReport.BinaryImage(
                libraryName: image.imageName ?? unavailable,
                uuid: image.uuid,
                architecture: image.codeType?.architectureName ?? unavailable,
                isSystemLibrary: image.isSystemImage,
                loadAddress: loadAddressHex,
                maxAddress: maxAddressHex
            )
        }
    }

    // MARK: - Exporting meta information

    private func meta(for crashReport: CrashReport) -> DDCrashReport.Meta {
        var parentProcessDescription: String? = nil

        if let processInfo = crashReport.processInfo {
            if let parentProcessName = processInfo.parentProcessName {
                parentProcessDescription = "\(parentProcessName) [\(processInfo.parentProcessID)]"
            } else {
                parentProcessDescription = "[\(processInfo.parentProcessID)]"
            }
        }

        let anyBinaryImageWithKnownArchitecture = crashReport.binaryImages.first { $0.codeType?.architectureName != nil }
        let cpuArchitecture = anyBinaryImageWithKnownArchitecture?.codeType?.architectureName

        return .init(
            incidentIdentifier: crashReport.incidentIdentifier,
            processName: crashReport.processInfo?.processName,
            parentProcess: parentProcessDescription,
            path: crashReport.processInfo?.processPath,
            codeType: cpuArchitecture,
            exceptionType: crashReport.signalInfo?.name,
            exceptionCodes: crashReport.signalInfo?.code
        )
    }

    // MARK: - Common

    /// Converts stack frames to newline-separated text format.
    private func string(from stackFrames: [StackFrame]) -> String {
        var lines: [String] = []
        var previousFrameNumber: Int? = nil

        stackFrames.forEach { frame in
            let frameNumber = "\(frame.number)".addSuffix(repeating: " ", targetLength: 3)
            let libraryName = (frame.libraryName ?? unavailable).addSuffix(repeating: " ", targetLength: 35)

            // Ref. for this computations:
            // https://github.com/microsoft/plcrashreporter/blob/dbb05c0bc883bde1cfcad83e7add25862c95d11f/Source/PLCrashReportTextFormatter.m#L496-L499
            let instructionAddressHex = "0x\(frame.instructionPointer.toHex.addPrefix(repeating: "0", targetLength: 16))"
            var imageBaseAddressHex = "0x0"
            var instructionOffsetDec = "0"

            if let libraryBaseAddress = frame.libraryBaseAddress {
                imageBaseAddressHex = "0x\(libraryBaseAddress.toHex)"
                instructionOffsetDec = "\(frame.instructionPointer.subtractIfNoOverflow(libraryBaseAddress) ?? 0)"
            }

            if let previousFrameNumber = previousFrameNumber {
                let isSucceedingLine = frame.number == previousFrameNumber + 1
                if !isSucceedingLine {
                    // If some frames were reduced, insert truncation symbol:
                    lines.append(stackTraceTruncationMark)
                }
            }

            lines.append("\(frameNumber) \(libraryName) \(instructionAddressHex) \(imageBaseAddressHex) + \(instructionOffsetDec)")
            previousFrameNumber = frame.number
        }

        return lines.joined(separator: "\n")
    }
}
