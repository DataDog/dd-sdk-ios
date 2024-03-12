/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import DatadogInternal
import CrashReporter

@testable import DatadogCrashReporting

internal class ThirdPartyCrashReporterMock: ThirdPartyCrashReporter {
    static var initializationError: Error?

    var pendingCrashReport: DDCrashReport?
    var pendingCrashReportError: Error?

    var injectedContext: Data?

    var hasPurgedPendingCrashReport = false
    var hasPurgedPendingCrashReportError: Error?

    var generatedBacktrace: BacktraceReport = .mockAny()

    required init() throws {
        if let error = ThirdPartyCrashReporterMock.initializationError {
            throw error
        }
    }

    func hasPendingCrashReport() -> Bool {
        return pendingCrashReport != nil
    }

    func loadPendingCrashReport() throws -> DDCrashReport {
        if let error = pendingCrashReportError {
            throw error
        }
        return pendingCrashReport!
    }

    func inject(context: Data) {
        injectedContext = context
    }

    func purgePendingCrashReport() throws {
        if let error = hasPurgedPendingCrashReportError {
            throw error
        }
        hasPurgedPendingCrashReport = true
    }

    func generateBacktrace(threadID: ThreadID) throws -> BacktraceReport {
        return generatedBacktrace
    }
}

// swiftlint:disable implicitly_unwrapped_optional
internal class PLCrashReportMock: PLCrashReport {
    class SystemInfoMock: PLCrashReportSystemInfo {
        var mockTimestamp: Date! = nil

        override var timestamp: Date! { mockTimestamp }
    }

    class ProcessInfoMock: PLCrashReportProcessInfo {
        var mockProcessName: String! = nil
        var mockProcessPath: String! = nil
        var mockParentProcessID: UInt = 0
        var mockParentProcessName: String! = nil

        override var processName: String! { mockProcessName }
        override var processPath: String! { mockProcessPath }
        override var parentProcessID: UInt { mockParentProcessID }
        override var parentProcessName: String! { mockParentProcessName }
    }

    class SignalInfo: PLCrashReportSignalInfo {
        var mockName: String! = nil
        var mockAddress: UInt64 = 0
        var mockCode: String! = nil

        override var name: String! { mockName }
        override var address: UInt64 { mockAddress }
        override var code: String! { mockCode }
    }

    class StackFrame: PLCrashReportStackFrameInfo {
        var mockInstructionPointer: UInt64 = 0

        override var instructionPointer: UInt64 { mockInstructionPointer }
    }

    class ExceptionInfo: PLCrashReportExceptionInfo {
        var mockExceptionName: String! = nil
        var mockExceptionReason: String! = nil
        var mockStackFrames: [StackFrame]! = nil

        override var exceptionName: String! { mockExceptionName }
        override var exceptionReason: String! { mockExceptionReason }
        override var stackFrames: [Any]! { mockStackFrames }
    }

    class ThreadInfo: PLCrashReportThreadInfo {
        var mockThreadNumber: Int = 0
        var mockCrashed = false
        var mockStackFrames: [StackFrame]! = nil

        override var threadNumber: Int { mockThreadNumber }
        override var crashed: Bool { mockCrashed }
        override var stackFrames: [Any]! { mockStackFrames }
    }

    class BinaryImageInfo: PLCrashReportBinaryImageInfo {
        class ProcessorInfo: PLCrashReportProcessorInfo {
            var mockTypeEncoding: PLCrashReportProcessorTypeEncoding = PLCrashReportProcessorTypeEncodingUnknown
            var mockType: UInt64 = 0
            var mockSubtype: UInt64 = 0

            override var typeEncoding: PLCrashReportProcessorTypeEncoding { mockTypeEncoding }
            override var type: UInt64 { mockType }
            override var subtype: UInt64 { mockSubtype }
        }

        var mockImageName: String! = nil
        var mockHasImageUUID = false
        var mockImageUUID: String! = nil
        var mockImageSize: UInt64 = 0
        var mockImageBaseAddress: UInt64 = 0
        var mockCodeType: ProcessorInfo! = nil

        override var imageName: String! { mockImageName }
        override var hasImageUUID: Bool { mockHasImageUUID }
        override var imageUUID: String! { mockImageUUID }
        override var imageSize: UInt64 { mockImageSize }
        override var imageBaseAddress: UInt64 { mockImageBaseAddress }
        override var codeType: PLCrashReportProcessorInfo! { mockCodeType }
    }

    var mockSystemInfo: SystemInfoMock! = nil
    var mockUUIDRef: CFUUID! = nil
    var mockHasProcessInfo = false
    var mockProcessInfo: ProcessInfoMock! = nil
    var mockSignalInfo: SignalInfo! = nil
    var mockHasExceptionInfo = false
    var mockExceptionInfo: ExceptionInfo! = nil
    var mockThreads: [ThreadInfo]! = nil
    var mockImages: [BinaryImageInfo]! = nil
    var mockCustomData: Data! = nil

    override var systemInfo: PLCrashReportSystemInfo! { mockSystemInfo }
    override var uuidRef: CFUUID! { mockUUIDRef }
    override var hasProcessInfo: Bool { mockHasProcessInfo }
    override var processInfo: PLCrashReportProcessInfo! { mockProcessInfo }
    override var signalInfo: PLCrashReportSignalInfo! { mockSignalInfo }
    override var hasExceptionInfo: Bool { mockHasExceptionInfo }
    override var exceptionInfo: PLCrashReportExceptionInfo! { mockExceptionInfo }
    override var threads: [Any]! { mockThreads }
    override var images: [Any]! { mockImages }
    override var customData: Data! { mockCustomData }

    var mockImageForAddress: [UInt64: PLCrashReportBinaryImageInfo] = [:]

    override func image(forAddress address: UInt64) -> PLCrashReportBinaryImageInfo! {
        return mockImageForAddress[address]
    }
}
// swiftlint:enable implicitly_unwrapped_optional

extension CrashReport {
    static func mockAny() -> CrashReport {
        return mockWith()
    }

    static func mockWith(
        incidentIdentifier: String? = nil,
        systemInfo: SystemInfo? = nil,
        processInfo: CrashedProcessInfo? = nil,
        signalInfo: SignalInfo? = nil,
        exceptionInfo: ExceptionInfo? = nil,
        threads: [ThreadInfo] = [],
        binaryImages: [BinaryImageInfo] = [],
        contextData: Data? = nil,
        wasTruncated: Bool = false
    ) -> CrashReport {
        return CrashReport(
            incidentIdentifier: incidentIdentifier,
            systemInfo: systemInfo,
            processInfo: processInfo,
            signalInfo: signalInfo,
            exceptionInfo: exceptionInfo,
            threads: threads,
            binaryImages: binaryImages,
            contextData: contextData,
            wasTruncated: wasTruncated
        )
    }
}

extension CrashedProcessInfo {
    static func mockWith(
        processName: String? = nil,
        processID: UInt = 1,
        processPath: String? = nil,
        parentProcessID: UInt = 0,
        parentProcessName: String? = nil
    ) -> CrashedProcessInfo {
        return CrashedProcessInfo(
            processName: processName,
            processID: processID,
            processPath: processPath,
            parentProcessID: parentProcessID,
            parentProcessName: parentProcessName
        )
    }
}

extension ExceptionInfo {
    static func mockWith(
        name: String? = .mockAny(),
        reason: String? = .mockAny(),
        stackFrames: [StackFrame] = []
    ) -> ExceptionInfo {
        return ExceptionInfo(name: name, reason: reason, stackFrames: stackFrames)
    }
}

extension ThreadInfo {
    static func mockWith(
        threadNumber: Int = .mockAny(),
        crashed: Bool = .mockAny(),
        stackFrames: [StackFrame] = []
    ) -> ThreadInfo {
        return ThreadInfo(threadNumber: threadNumber, crashed: crashed, stackFrames: stackFrames)
    }
}

extension BinaryImageInfo {
    static func mockWith(
        uuid: String? = .mockAny(),
        imageName: String = .mockAny(),
        isSystemImage: Bool = .random(),
        architectureName: String? = .mockAny(),
        imageBaseAddress: UInt64 = .mockAny(),
        imageSize: UInt64 = .mockAny()
    ) -> BinaryImageInfo {
        return BinaryImageInfo(
            uuid: uuid,
            imageName: imageName,
            isSystemImage: isSystemImage,
            codeType: .init(architectureName: architectureName),
            imageBaseAddress: imageBaseAddress,
            imageSize: imageSize
        )
    }
}

extension StackFrame {
    static func mockWith(
        number: Int = .mockAny(),
        libraryName: String? = .mockAny(),
        libraryBaseAddress: UInt64? = .mockAny(),
        instructionPointer: UInt64 = .mockAny()
    ) -> StackFrame {
        return StackFrame(
            number: number,
            libraryName: libraryName,
            libraryBaseAddress: libraryBaseAddress,
            instructionPointer: instructionPointer
        )
    }
}
