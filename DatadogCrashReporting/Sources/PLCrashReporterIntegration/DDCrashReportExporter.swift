/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import DatadogInternal

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

    /// Different signals and their descriptions available in OS.
    private let knownSignalDescriptionByName = [
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

    func export(_ crashReport: CrashReport) -> DDCrashReport {
        return DDCrashReport(
            date: crashReport.systemInfo?.timestamp,
            type: formattedType(for: crashReport),
            message: formattedMessage(for: crashReport),
            stack: formattedStack(for: crashReport),
            threads: formattedThreads(from: crashReport),
            binaryImages: formattedBinaryImages(from: crashReport),
            meta: formattedMeta(for: crashReport),
            wasTruncated: crashReport.wasTruncated,
            context: crashReport.contextData
        )
    }

    // MARK: - Formatting `error.type`, `error.message` and `error.stack`

    /// Formats the error type - in Datadog Error Tracking this corresponds to `error.type`.
    ///
    /// **Note:** This value is used for building error's fingerprint in Error Tracking, thus its cardinality must be controlled.
    private func formattedType(for crashReport: CrashReport) -> String {
        return "\(crashReport.signalInfo?.name ?? unknown) (\(crashReport.signalInfo?.code ?? unknown))"
    }

    /// Formats the error message - in Datadog Error Tracking this corresponds to `error.message`.
    ///
    /// **Note:** This value is used for building error's fingerprint in Error Tracking, thus its cardinality must be controlled.
    private func formattedMessage(for crashReport: CrashReport) -> String {
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

            if let signalDescription = knownSignalDescriptionByName[signalName] {
                return "Application crash: \(signalName) (\(signalDescription))"
            } else {
                return "Application crash: \(unknown)"
            }
        }
    }

    /// Formats the error stack - in Datadog Error Tracking this corresponds to `error.stack`.
    ///
    /// **Note:** This produces unsymbolicated stack trace, which is later symbolicated backend-side and used for building error's fingerprint in Error Tracking.
    private func formattedStack(for crashReport: CrashReport) -> String {
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

        return string(from: sanitized(stackFrames: stackFrames))
    }

    // MARK: - Sanitizing

    private func sanitized(stackFrames: [StackFrame]) -> [StackFrame] {
        guard let lastFrame = stackFrames.last else {
            return stackFrames
        }

        // RUMM-2025: Often the last frame has no library name nor its base address. This results with
        // producing malformed frame, e.g. `XX  ???                   0x00000001045f0250  0x000000000 + 4368302672`
        // which can't be symbolicated. To make it cleaner in UI and to avoid BE symbolication errors, we filter
        // out such trailing frame. Ref.: https://github.com/microsoft/plcrashreporter/issues/193
        let sanitizedFrames = lastFrame.libraryBaseAddress == nil ? stackFrames.dropLast() : stackFrames
        return sanitizedFrames
    }

    // MARK: - Exporting threads and binary images

    private func formattedThreads(from crashReport: CrashReport) -> [DDThread] {
        return crashReport.threads.map { thread in
            return DDThread(
                name: "Thread \(thread.threadNumber)",
                stack: string(from: thread.stackFrames), // we don't sanitize frames in `error.threads[]`
                crashed: thread.crashed,
                state: nil // TODO: RUMM-1462 Send registers state for crashed thread
            )
        }
    }

    private func formattedBinaryImages(from crashReport: CrashReport) -> [BinaryImage] {
        return crashReport.binaryImages.map { image in
            // Ref. for this computation:
            // https://github.com/microsoft/plcrashreporter/blob/dbb05c0bc883bde1cfcad83e7add25862c95d11f/Source/PLCrashReportTextFormatter.m#L447
            let loadAddressHex = "0x\(image.imageBaseAddress.toHex)"
            var maxAddressOffset = image.imageSize.subtractIfNoOverflow(1) ?? image.imageSize
            maxAddressOffset = max(1, maxAddressOffset)
            let maxAddress = image.imageBaseAddress.addIfNoOverflow(maxAddressOffset) ?? image.imageBaseAddress
            let maxAddressHex = "0x\(maxAddress.toHex)"

            return BinaryImage(
                libraryName: image.imageName,
                uuid: image.uuid ?? unavailable,
                architecture: image.codeType?.architectureName ?? unavailable,
                isSystemLibrary: image.isSystemImage,
                loadAddress: loadAddressHex,
                maxAddress: maxAddressHex
            )
        }
    }

    // MARK: - Exporting meta information

    private func formattedMeta(for crashReport: CrashReport) -> DDCrashReport.Meta {
        let process = crashReport.processInfo.map { info in
            info.processName.map { "\($0) [\(info.processID)]" } ?? "[\(info.processID)]"
        }

        let parentProcess = crashReport.processInfo.map { info in
            info.parentProcessName.map { "\($0) [\(info.parentProcessID)]" } ?? "[\(info.parentProcessID)]"
        }

        let anyBinaryImageWithKnownArchitecture = crashReport.binaryImages.first { $0.codeType?.architectureName != nil }
        let cpuArchitecture = anyBinaryImageWithKnownArchitecture?.codeType?.architectureName

        return .init(
            incidentIdentifier: crashReport.incidentIdentifier,
            process: process,
            parentProcess: parentProcess,
            path: crashReport.processInfo?.processPath,
            codeType: cpuArchitecture,
            exceptionType: crashReport.signalInfo?.name,
            exceptionCodes: crashReport.signalInfo?.code
        )
    }

    // MARK: - Common

    /// Converts stack frames to newline-separated text format.
    private func string(from stackFrames: [StackFrame]) -> String {
        let lines: [String] = stackFrames.map { frame in
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

            return "\(frameNumber) \(libraryName) \(instructionAddressHex) \(imageBaseAddressHex) + \(instructionOffsetDec)"
        }

        return lines.joined(separator: "\n")
    }
}
