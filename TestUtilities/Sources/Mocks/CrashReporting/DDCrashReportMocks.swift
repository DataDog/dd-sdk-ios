/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal
import CrashReporter

@testable import DatadogCrashReporting

extension DDCrashReport: AnyMockable, RandomMockable {
    public static func mockAny() -> DDCrashReport {
        return .mockWith()
    }

    public static func mockRandom() -> DDCrashReport {
        return DDCrashReport(
            date: .mockRandom(),
            type: .mockRandom(),
            message: .mockRandom(),
            stack: .mockRandom(),
            threads: .mockRandom(),
            binaryImages: .mockRandom(),
            meta: .mockRandom(),
            wasTruncated: .mockRandom(),
            context: .mockRandom(),
            additionalAttributes: mockRandomAttributes()
        )
    }

    public static func mockWith(
        date: Date? = .mockAny(),
        type: String = .mockAny(),
        message: String = .mockAny(),
        stack: String = .mockAny(),
        threads: [DDThread] = .mockAny(),
        binaryImages: [BinaryImage] = .mockAny(),
        meta: Meta = .mockAny(),
        wasTruncated: Bool = .mockAny(),
        context: Data? = .mockAny(),
        additionalAttributes: [String: Encodable]? = nil
    ) -> DDCrashReport {
        return DDCrashReport(
            date: date,
            type: type,
            message: message,
            stack: stack,
            threads: threads,
            binaryImages: binaryImages,
            meta: meta,
            wasTruncated: wasTruncated,
            context: context,
            additionalAttributes: additionalAttributes
        )
    }

    public static func mockRandomWith(context: CrashContext) -> DDCrashReport {
        return mockRandomWith(contextData: context.data)
    }

    public static func mockRandomWith(contextData: Data) -> DDCrashReport {
        return mockWith(
            date: .mockRandomInThePast(),
            type: .mockRandom(),
            message: .mockRandom(),
            stack: .mockRandom(),
            context: contextData,
            additionalAttributes: mockRandomAttributes()
        )
    }
}

extension DDCrashReport.Meta: AnyMockable, RandomMockable {
    public static func mockAny() -> DDCrashReport.Meta {
        return .mockWith()
    }

    public static func mockRandom() -> DDCrashReport.Meta {
        return DDCrashReport.Meta(
            incidentIdentifier: .mockRandom(),
            process: .mockRandom(),
            parentProcess: .mockRandom(),
            path: .mockRandom(),
            codeType: .mockRandom(),
            exceptionType: .mockRandom(),
            exceptionCodes: .mockRandom()
        )
    }

    public static func mockWith(
        incidentIdentifier: String? = .mockAny(),
        process: String? = .mockAny(),
        parentProcess: String? = .mockAny(),
        path: String? = .mockAny(),
        codeType: String? = .mockAny(),
        exceptionType: String? = .mockAny(),
        exceptionCodes: String? = .mockAny()
    ) -> DDCrashReport.Meta {
        return DDCrashReport.Meta(
            incidentIdentifier: incidentIdentifier,
            process: process,
            parentProcess: parentProcess,
            path: path,
            codeType: codeType,
            exceptionType: exceptionType,
            exceptionCodes: exceptionCodes
        )
    }
}

public final class ThirdPartyCrashReporterMock: ThirdPartyCrashReporter, @unchecked Sendable {
    public static var initializationError: Error?

    public var pendingCrashReport: DDCrashReport?
    public var pendingCrashReportError: Error?

    public var injectedContext: Data?

    public var hasPurgedPendingCrashReport = false
    public var hasPurgedPendingCrashReportError: Error?

    public var generatedBacktrace: BacktraceReport = .mockAny()

    public required init() throws {
        if let error = ThirdPartyCrashReporterMock.initializationError {
            throw error
        }
    }

    public func hasPendingCrashReport() -> Bool {
        return pendingCrashReport != nil
    }

    public func loadPendingCrashReport() throws -> DDCrashReport {
        if let error = pendingCrashReportError {
            throw error
        }
        return pendingCrashReport!
    }

    public func inject(context: Data) {
        injectedContext = context
    }

    public func purgePendingCrashReport() throws {
        if let error = hasPurgedPendingCrashReportError {
            throw error
        }
        hasPurgedPendingCrashReport = true
    }

    public func generateBacktrace(threadID: ThreadID) throws -> BacktraceReport {
        return generatedBacktrace
    }
}

// swiftlint:disable implicitly_unwrapped_optional
public class PLCrashReportMock: PLCrashReport {
    public class SystemInfoMock: PLCrashReportSystemInfo {
        public var mockTimestamp: Date! = nil

        override public var timestamp: Date! { mockTimestamp }
    }

    public class ProcessInfoMock: PLCrashReportProcessInfo {
        public var mockProcessName: String! = nil
        public var mockProcessPath: String! = nil
        public var mockParentProcessID: UInt = 0
        public var mockParentProcessName: String! = nil

        override public var processName: String! { mockProcessName }
        override public var processPath: String! { mockProcessPath }
        override public var parentProcessID: UInt { mockParentProcessID }
        override public var parentProcessName: String! { mockParentProcessName }
    }

    public class SignalInfo: PLCrashReportSignalInfo {
        public var mockName: String! = nil
        public var mockAddress: UInt64 = 0
        public var mockCode: String! = nil

        override public var name: String! { mockName }
        override public var address: UInt64 { mockAddress }
        override public var code: String! { mockCode }
    }

    public class StackFrame: PLCrashReportStackFrameInfo {
        public var mockInstructionPointer: UInt64 = 0

        override public var instructionPointer: UInt64 { mockInstructionPointer }
    }

    public class ExceptionInfo: PLCrashReportExceptionInfo {
        public var mockExceptionName: String! = nil
        public var mockExceptionReason: String! = nil
        public var mockStackFrames: [StackFrame]! = nil

        override public var exceptionName: String! { mockExceptionName }
        override public var exceptionReason: String! { mockExceptionReason }
        override public var stackFrames: [Any]! { mockStackFrames }
    }

    public class ThreadInfo: PLCrashReportThreadInfo {
        public var mockThreadNumber: Int = 0
        public var mockCrashed = false
        public var mockStackFrames: [StackFrame]! = nil

        override public var threadNumber: Int { mockThreadNumber }
        override public var crashed: Bool { mockCrashed }
        override public var stackFrames: [Any]! { mockStackFrames }
    }

    public class BinaryImageInfo: PLCrashReportBinaryImageInfo {
        public class ProcessorInfo: PLCrashReportProcessorInfo {
            public var mockTypeEncoding: PLCrashReportProcessorTypeEncoding = PLCrashReportProcessorTypeEncodingUnknown
            public var mockType: UInt64 = 0
            public var mockSubtype: UInt64 = 0

            override public var typeEncoding: PLCrashReportProcessorTypeEncoding { mockTypeEncoding }
            override public var type: UInt64 { mockType }
            override public var subtype: UInt64 { mockSubtype }
        }

        public var mockImageName: String! = nil
        public var mockHasImageUUID = false
        public var mockImageUUID: String! = nil
        public var mockImageSize: UInt64 = 0
        public var mockImageBaseAddress: UInt64 = 0
        public var mockCodeType: ProcessorInfo! = nil

        override public var imageName: String! { mockImageName }
        override public var hasImageUUID: Bool { mockHasImageUUID }
        override public var imageUUID: String! { mockImageUUID }
        override public var imageSize: UInt64 { mockImageSize }
        override public var imageBaseAddress: UInt64 { mockImageBaseAddress }
        override public var codeType: PLCrashReportProcessorInfo! { mockCodeType }
    }

    public var mockSystemInfo: SystemInfoMock! = nil
    public var mockUUIDRef: CFUUID! = nil
    public var mockHasProcessInfo = false
    public var mockProcessInfo: ProcessInfoMock! = nil
    public var mockSignalInfo: SignalInfo! = nil
    public var mockHasExceptionInfo = false
    public var mockExceptionInfo: ExceptionInfo! = nil
    public var mockThreads: [ThreadInfo]! = nil
    public var mockImages: [BinaryImageInfo]! = nil
    public var mockCustomData: Data! = nil

    override public var systemInfo: PLCrashReportSystemInfo! { mockSystemInfo }
    override public var uuidRef: CFUUID! { mockUUIDRef }
    override public var hasProcessInfo: Bool { mockHasProcessInfo }
    override public var processInfo: PLCrashReportProcessInfo! { mockProcessInfo }
    override public var signalInfo: PLCrashReportSignalInfo! { mockSignalInfo }
    override public var hasExceptionInfo: Bool { mockHasExceptionInfo }
    override public var exceptionInfo: PLCrashReportExceptionInfo! { mockExceptionInfo }
    override public var threads: [Any]! { mockThreads }
    override public var images: [Any]! { mockImages }
    override public var customData: Data! { mockCustomData }

    public var mockImageForAddress: [UInt64: PLCrashReportBinaryImageInfo] = [:]

    override public func image(forAddress address: UInt64) -> PLCrashReportBinaryImageInfo! {
        return mockImageForAddress[address]
    }
}
// swiftlint:enable implicitly_unwrapped_optional

extension CrashReport {
    public static func mockAny() -> CrashReport {
        return mockWith()
    }

    public static func mockWith(
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
    public static func mockWith(
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
    public static func mockWith(
        name: String? = .mockAny(),
        reason: String? = .mockAny(),
        stackFrames: [StackFrame] = []
    ) -> ExceptionInfo {
        return ExceptionInfo(name: name, reason: reason, stackFrames: stackFrames)
    }
}

extension ThreadInfo {
    public static func mockWith(
        threadNumber: Int = .mockAny(),
        crashed: Bool = .mockAny(),
        stackFrames: [StackFrame] = []
    ) -> ThreadInfo {
        return ThreadInfo(threadNumber: threadNumber, crashed: crashed, stackFrames: stackFrames)
    }
}

extension BinaryImageInfo {
    public static func mockWith(
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
    public static func mockWith(
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
