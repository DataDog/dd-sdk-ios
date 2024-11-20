/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if canImport(CrashReporter)

import Foundation
import CrashReporter

/// An intermediate representation of crash report when transforming `PLCrashReport` to `DDCrashReport`.
///
/// It implements preliminary consistency check for Objective-C `PLCrashReport` and provides additional
/// type-safety for accessing its implicitly unwrapped optional values.
internal struct CrashReport {
    /// A client-generated 16-byte UUID of the incident.
    var incidentIdentifier: String?
    /// System information from the moment of crash.
    var systemInfo: SystemInfo?
    /// Information about the process that crashed.
    var processInfo: CrashedProcessInfo?
    /// Information about the fatal signal.
    var signalInfo: SignalInfo?
    /// Uncaught exception information. Only available if a crash was caused by an uncaught exception, otherwise `nil`.
    var exceptionInfo: ExceptionInfo?
    /// Information about all threads running at the moment of crash.
    var threads: [ThreadInfo]
    /// Information about binary images loaded by the process.
    var binaryImages: [BinaryImageInfo]
    /// Custom user data injected before the crash occurred.
    var contextData: Data?
    /// Additional flag (for telemetry) meaning if any of the stack traces was truncated due to minification.
    var wasTruncated: Bool
}

/// Intermediate representation of `PLCrashReportSystemInfo`.
internal struct SystemInfo {
    /// Date and time when the crash report was generated.
    var timestamp: Date?
}

/// Intermediate representation of `PLCrashReportProcessInfo`.
internal struct CrashedProcessInfo {
    /// The name of the process.
    var processName: String?
    /// The process ID.
    var processID: UInt
    /// The path to the process executable.
    var processPath: String?
    /// The parent process ID.
    var parentProcessID: UInt
    /// The parent process name
    var parentProcessName: String?
}

/// Intermediate representation of `PLCrashReportSignalInfo`.
internal struct SignalInfo {
    /// The name of the corresponding BSD termination signal, e.g. `SIGTRAP`.
    /// This corresponds to _"Exception Type"_ in Apple Crash Report format.
    var name: String?
    /// Termination signal code, e.g. `"#0`. Together with `address` it can be used for giving more
    /// context, e.g. `"#0 at 0x1b0ad6aa8"`.
    /// This corresponds to _"Exception Codes"_ in Apple Crash Report format.
    var code: String?
    /// The faulting instruction address.
    var address: UInt64
}

/// Intermediate representation of `PLCrashReportExceptionInfo`.
internal struct ExceptionInfo {
    /// The exception name, e.g. `NSInternalInconsistencyException`.
    var name: String?
    /// The exception reason, e.g. `unable to dequeue a cell with identifier foo - (...)`.
    var reason: String?
    /// The stack trace of this exception.
    var stackFrames: [StackFrame]
}

/// Intermediate representation of `PLCrashReportThreadInfo`.
internal struct ThreadInfo {
    /// Application thread number.
    var threadNumber: Int
    /// If this thread crashed.
    var crashed: Bool
    /// The stack trace of this thread.
    var stackFrames: [StackFrame]
}

/// Intermediate representation of `PLCrashReportBinaryImageInfo`.
internal struct BinaryImageInfo {
    internal struct CodeType {
        /// The name of CPU architecture.
        var architectureName: String?
    }

    /// The UUID of this image.
    var uuid: String?
    /// The name of this image (referenced by "library name" in the stack frame).
    var imageName: String
    /// If its a system library image.
    var isSystemImage: Bool
    /// Image code type (code architecture information).
    var codeType: CodeType?
    /// The load address of this image.
    var imageBaseAddress: UInt64
    /// The size of this image segment.
    var imageSize: UInt64
}

/// Intermediate representation of `PLCrashReportStackFrameInfo`.
internal struct StackFrame {
    /// The number of this frame in the stack trace.
    /// This must be recorded as less meaningful stack frames might be removed when minifying the `CrashReport`.
    var number: Int
    /// The name of the library that produced this frame (the "image name" from binary image).
    var libraryName: String?
    /// The load address of the library that produced this frame (the "image base address" from binary image).
    var libraryBaseAddress: UInt64?
    /// The instruction pointer of this frame.
    var instructionPointer: UInt64
}

// MARK: - Reading intermediate values from PLCR types

internal struct CrashReportException: Error {
    let description: String
}

extension CrashReport {
    init(from plcr: PLCrashReport) throws {
        guard let threads = plcr.threads,
              let images = plcr.images else {
            // Sanity check - this shouldn't be reachable.
            // The crash report must specify some threads and some binary images.
            throw CrashReportException(
                description: "Received inconsistent `PLCrashReport` # has threads = \(plcr.threads != nil), has images = \(plcr.images != nil)"
            )
        }

        if let uuid = plcr.uuidRef, let uuidString = CFUUIDCreateString(nil, uuid) {
            self.incidentIdentifier = uuidString as String
        } else {
            self.incidentIdentifier = nil
        }

        self.systemInfo = SystemInfo(from: plcr)
        self.processInfo = CrashedProcessInfo(from: plcr)
        self.signalInfo = SignalInfo(from: plcr)
        self.exceptionInfo = ExceptionInfo(from: plcr)

        self.threads = threads
            .compactMap { $0 as? PLCrashReportThreadInfo }
            .map { ThreadInfo(from: $0, in: plcr) }

        self.binaryImages = images
            .compactMap { $0 as? PLCrashReportBinaryImageInfo }
            .compactMap { BinaryImageInfo(from: $0) }

        self.contextData = plcr.customData
        self.wasTruncated = false
    }
}

extension SystemInfo {
    init?(from plcr: PLCrashReport) {
        guard let systemInfo = plcr.systemInfo else {
            return nil
        }

        self.timestamp = systemInfo.timestamp
    }
}

extension CrashedProcessInfo {
    init?(from plcr: PLCrashReport) {
        guard plcr.hasProcessInfo, let processInfo = plcr.processInfo else {
            return nil
        }

        self.processName = processInfo.processName
        self.processID = processInfo.processID
        self.processPath = processInfo.processPath
        self.parentProcessID = processInfo.parentProcessID
        self.parentProcessName = processInfo.parentProcessName
    }
}

extension SignalInfo {
    init?(from plcr: PLCrashReport) {
        guard let signalInfo = plcr.signalInfo else {
            return nil
        }

        self.name = signalInfo.name
        self.code = signalInfo.code
        self.address = signalInfo.address
    }
}

extension ExceptionInfo {
    init?(from plcr: PLCrashReport) {
        guard plcr.hasExceptionInfo, let exceptionInfo = plcr.exceptionInfo else {
            // The crash was not caused by an uncaught exception.
            return nil
        }

        self.name = exceptionInfo.exceptionName
        self.reason = exceptionInfo.exceptionReason

        if let stackFrames = exceptionInfo.stackFrames {
            self.stackFrames = stackFrames
                .compactMap { $0 as? PLCrashReportStackFrameInfo }
                .enumerated()
                .map { number, frame in StackFrame(from: frame, number: number, in: plcr) }
        } else {
            self.stackFrames = []
        }
    }
}

extension ThreadInfo {
    init(from threadInfo: PLCrashReportThreadInfo, in crashReport: PLCrashReport) {
        self.threadNumber = threadInfo.threadNumber
        self.crashed = threadInfo.crashed

        if let stackFrames = threadInfo.stackFrames {
            self.stackFrames = stackFrames
                .compactMap { $0 as? PLCrashReportStackFrameInfo }
                .enumerated()
                .map { number, frame in StackFrame(from: frame, number: number, in: crashReport) }
        } else {
            self.stackFrames = []
        }
    }
}

extension BinaryImageInfo {
    init?(from imageInfo: PLCrashReportBinaryImageInfo) {
        guard let imagePath = imageInfo.imageName else {
            // We can drop this image as it won't be useful for symbolication
            return nil
        }

        self.uuid = imageInfo.imageUUID
        self.imageName = URL(fileURLWithPath: imagePath).lastPathComponent

        #if targetEnvironment(simulator)
        self.isSystemImage = Self.isPathSystemImageInSimulator(imagePath)
        #else
        self.isSystemImage = Self.isPathSystemImageInDevice(imagePath)
        #endif

        if let codeType = imageInfo.codeType {
            self.codeType = CodeType(from: codeType)
        } else {
            // The architecture name of this image is unknown, but symbolication will be possible.
            self.codeType = nil
        }

        self.imageBaseAddress = imageInfo.imageBaseAddress
        self.imageSize = imageInfo.imageSize
    }

    static func isPathSystemImageInSimulator(_ path: String) -> Bool {
        // in simulator, example system image path: ~/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/...
        return path.contains("/Contents/Developer/Platforms/")
    }

    static func isPathSystemImageInDevice(_ path: String) -> Bool {
        // in device, example user image path: .../containers/Bundle/Application/0000/Runner.app/Frameworks/...
        let isUserImage = path.contains("/Bundle/Application/")
        return !isUserImage
    }
}

extension BinaryImageInfo.CodeType {
    init?(from processorInfo: PLCrashReportProcessorInfo) {
        guard processorInfo.typeEncoding == PLCrashReportProcessorTypeEncodingMach else {
            // Unknown processor type - skip.
            return nil
        }

        let type = processorInfo.type
        let subtype = processorInfo.subtype
        let subtypeMask = UInt64(CPU_SUBTYPE_MASK)

        // Ref. for this check:
        // https://github.com/microsoft/plcrashreporter/blob/dbb05c0bc883bde1cfcad83e7add25862c95d11f/Source/PLCrashReportTextFormatter.m#L371
        switch type {
        case UInt64(CPU_TYPE_X86):      self.architectureName = "i386"
        case UInt64(CPU_TYPE_X86_64):   self.architectureName = "x86_64"
        case UInt64(CPU_TYPE_ARM):      self.architectureName = "arm"
        case UInt64(CPU_TYPE_ARM64):
            switch subtype & ~subtypeMask {
            case UInt64(CPU_SUBTYPE_ARM64_ALL): self.architectureName = "arm64"
            case UInt64(CPU_SUBTYPE_ARM64_V8):  self.architectureName = "armv8"
            case UInt64(CPU_SUBTYPE_ARM64E):    self.architectureName = "arm64e"
            default:                            self.architectureName = "arm64-unknown"
            }
        default:
            self.architectureName = nil
        }
    }
}

extension StackFrame {
    init(from stackFrame: PLCrashReportStackFrameInfo, number: Int, in crashReport: PLCrashReport) {
        self.number = number
        self.instructionPointer = stackFrame.instructionPointer

        // Without "library name" and its "base address" symbolication will not be possible,
        // but the presence of this frame in the stack will be still relevant.
        let image = crashReport.image(forAddress: stackFrame.instructionPointer)

        self.libraryBaseAddress = image?.imageBaseAddress

        if let imagePath = image?.imageName {
            self.libraryName = URL(fileURLWithPath: imagePath).lastPathComponent
        }
    }
}

#endif // canImport(CrashReporter)
