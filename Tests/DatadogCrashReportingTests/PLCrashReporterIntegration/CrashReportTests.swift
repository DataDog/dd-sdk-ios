/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogCrashReporting
import CrashReporter

class CrashReportTests: XCTestCase {
    // MARK: - Consistency

    func testGivenPLCrashReportWithConsistentValues_whenInitializing_itReturnsValue() throws {
        // Given
        let mockStackFrame = PLCrashReportMock.StackFrame()

        let mockThread = PLCrashReportMock.ThreadInfo()
        mockThread.mockStackFrames = [mockStackFrame]

        let mockImage = PLCrashReportMock.BinaryImageInfo()
        mockImage.mockHasImageUUID = true
        mockImage.mockImageUUID = .mockRandom()
        mockImage.mockImageName = .mockRandom()

        let mock = PLCrashReportMock()
        mock.mockUUIDRef = CFUUIDCreate(nil)
        mock.mockSystemInfo = .init()
        mock.mockProcessInfo = .init()
        mock.mockHasProcessInfo = true
        mock.mockSignalInfo = .init()
        mock.mockExceptionInfo = .init()
        mock.mockHasExceptionInfo = true
        mock.mockThreads = [mockThread]
        mock.mockImages = [mockImage]

        // When
        let crashReport = try CrashReport(from: mock)

        // Then
        XCTAssertNotNil(crashReport.incidentIdentifier)
        XCTAssertNotNil(crashReport.systemInfo)
        XCTAssertNotNil(crashReport.processInfo)
        XCTAssertNotNil(crashReport.signalInfo)
        XCTAssertNotNil(crashReport.exceptionInfo)
        XCTAssertEqual(crashReport.threads.count, 1)
        XCTAssertEqual(crashReport.threads[0].stackFrames.count, 1)
        XCTAssertEqual(crashReport.binaryImages.count, 1)
    }

    func testGivenPLCrashReportWithNoThreadsAndImages_whenInitializing_itReturnsNil() throws {
        // Given
        let mock = PLCrashReportMock()
        mock.mockThreads = nil
        mock.mockImages = nil

        // When
        XCTAssertThrowsError(try CrashReport(from: mock)) { error in
            // Then
            let exception = error as! CrashReportException
            XCTAssertEqual(exception.description, "Received inconsistent `PLCrashReport` # has threads = false, has images = false")
        }
    }

    func testGivenPLCrashReportWithSomeInconsistentValues_whenInitializing_itReturnsValue() throws {
        // Given
        let mock = PLCrashReportMock()
        mock.mockUUIDRef = Bool.random() ? CFUUIDCreate(nil) : nil
        mock.mockSystemInfo = Bool.random() ? .init() : nil
        mock.mockProcessInfo = Bool.random() ? .init() : nil
        mock.mockHasProcessInfo = Bool.random()
        mock.mockSignalInfo = Bool.random() ? .init() : nil
        mock.mockExceptionInfo = Bool.random() ? .init() : nil
        mock.mockHasExceptionInfo = Bool.random()
        mock.mockThreads = [.init()]
        mock.mockImages = [.init()]

        // When
        let crashReport = try CrashReport(from: mock)

        // Then
        XCTAssertNotNil(crashReport, "It should initialize as long as it  has threads and images")
    }

    // MARK: - Values

    func testItReadsIncidentIdentifier() throws {
        // Given
        let uuid = UUID().uuidString

        let mock = PLCrashReportMock()
        mock.mockUUIDRef = CFUUIDCreateFromString(nil, uuid as CFString)
        mock.mockThreads = [.init()]
        mock.mockImages = [.init()]

        // When
        let crashReport = try XCTUnwrap(CrashReport(from: mock))

        // Then
        XCTAssertEqual(crashReport.incidentIdentifier, uuid)
    }

    func testItReadsSystemInfo() throws {
        // Given
        let mock = PLCrashReportMock()
        mock.mockSystemInfo = .init()
        mock.mockSystemInfo.mockTimestamp = .mockRandomInThePast()
        mock.mockThreads = [.init()]
        mock.mockImages = [.init()]

        // When
        let crashReport = try XCTUnwrap(CrashReport(from: mock))

        // Then
        XCTAssertEqual(crashReport.systemInfo?.timestamp, mock.mockSystemInfo.mockTimestamp)
    }

    func testItReadsProcessInfo() throws {
        // Given
        let mock = PLCrashReportMock()
        mock.mockHasProcessInfo = true
        mock.mockProcessInfo = .init()
        mock.mockProcessInfo.mockProcessName = .mockRandom()
        mock.mockProcessInfo.mockProcessPath = .mockRandom()
        mock.mockProcessInfo.mockParentProcessID = .mockRandom()
        mock.mockProcessInfo.mockParentProcessName = .mockRandom()
        mock.mockThreads = [.init()]
        mock.mockImages = [.init()]

        // When
        let crashReport = try XCTUnwrap(CrashReport(from: mock))

        // Then
        XCTAssertEqual(crashReport.processInfo?.processName, mock.mockProcessInfo.mockProcessName)
        XCTAssertEqual(crashReport.processInfo?.processPath, mock.mockProcessInfo.mockProcessPath)
        XCTAssertEqual(crashReport.processInfo?.parentProcessID, mock.mockProcessInfo.mockParentProcessID)
        XCTAssertEqual(crashReport.processInfo?.parentProcessName, mock.mockProcessInfo.mockParentProcessName)
    }

    func testItReadsSignalInfo() throws {
        // Given
        let mock = PLCrashReportMock()
        mock.mockSignalInfo = .init()
        mock.mockSignalInfo.mockName = .mockRandom()
        mock.mockSignalInfo.mockCode = .mockRandom()
        mock.mockSignalInfo.mockAddress = .mockRandom()
        mock.mockThreads = [.init()]
        mock.mockImages = [.init()]

        // When
        let crashReport = try XCTUnwrap(CrashReport(from: mock))

        // Then
        XCTAssertEqual(crashReport.signalInfo?.name, mock.mockSignalInfo.mockName)
        XCTAssertEqual(crashReport.signalInfo?.code, mock.mockSignalInfo.mockCode)
        XCTAssertEqual(crashReport.signalInfo?.address, mock.mockSignalInfo.mockAddress)
    }

    func testItReadsExceptionInfo() throws {
        // Given
        let mockStackFrames: [PLCrashReportMock.StackFrame] = (0x01..<0x10).map { value in
            let mockStackFrame = PLCrashReportMock.StackFrame()
            mockStackFrame.mockInstructionPointer = UInt64(value)
            return mockStackFrame
        }

        let mock = PLCrashReportMock()
        mock.mockHasExceptionInfo = true
        mock.mockExceptionInfo = .init()
        mock.mockExceptionInfo.mockExceptionName = .mockRandom()
        mock.mockExceptionInfo.mockExceptionReason = .mockRandom()
        mock.mockExceptionInfo.mockStackFrames = mockStackFrames

        // When
        let exceptionInfo = try XCTUnwrap(ExceptionInfo(from: mock))

        // Then
        XCTAssertEqual(exceptionInfo.name, mock.mockExceptionInfo.mockExceptionName)
        XCTAssertEqual(exceptionInfo.reason, mock.mockExceptionInfo.mockExceptionReason)
        XCTAssertEqual(exceptionInfo.stackFrames.count, mockStackFrames.count)
    }

    func testItReadsThreadInfo() throws {
        // Given
        let mockStackFrames: [PLCrashReportMock.StackFrame] = (0x01..<0x10).map { value in
            let mockStackFrame = PLCrashReportMock.StackFrame()
            mockStackFrame.mockInstructionPointer = UInt64(value)
            return mockStackFrame
        }

        let mockThread = PLCrashReportMock.ThreadInfo()
        mockThread.mockThreadNumber = .mockRandom()
        mockThread.mockCrashed = .random()
        mockThread.mockStackFrames = mockStackFrames

        let mock = PLCrashReportMock()
        mock.mockThreads = [mockThread]

        // When
        let threadInfo = try XCTUnwrap(ThreadInfo(from: mockThread, in: mock))

        // Then
        XCTAssertEqual(threadInfo.threadNumber, mockThread.mockThreadNumber)
        XCTAssertEqual(threadInfo.crashed, mockThread.mockCrashed)
        XCTAssertEqual(threadInfo.stackFrames.count, mockStackFrames.count)
    }

    private let systemImagePaths_device = [
        "/System/Library/PrivateFrameworks/UIKitCore.framework/UIKitCore",
        "/usr/lib/system/libdyld.dylib"
    ]
    private let systemImagePaths_simulator = [
        "/Users/john.appleseed/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Library/Developer/CoreSimulator/Profiles/Runtimes/iOS.simruntime/Contents/Resources/RuntimeRoot/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation"
    ]
    private let userImagePaths_device = [
        "/private/var/containers/Bundle/Application/0000/Example.app/Example",
        "/private/var/containers/Bundle/Application/0000/Example.app/Frameworks/DatadogCrashReporting.framework/DatadogCrashReporting"
    ]
    private let userImagePaths_simulator = [
        "/Users/john.appleseed/Library/Developer/CoreSimulator/Devices/0000/data/Containers/Bundle/Application/0000/Example.app/Example",
        "/Users/john.appleseed/Library/Developer/Xcode/DerivedData/Datadog-abcd/Build/Products/Release-iphonesimulator/DatadogCrashReporting.framework/DatadogCrashReporting"
    ]

    func testItDetectsSystemImages() throws {
        for systemImagePath in systemImagePaths_device {
            XCTAssertTrue(BinaryImageInfo.isPathSystemImageInDevice(systemImagePath), "\(systemImagePath) is a system image")
        }
        for systemImagePath in systemImagePaths_simulator {
            XCTAssertTrue(BinaryImageInfo.isPathSystemImageInSimulator(systemImagePath), "\(systemImagePath) is a system image")
        }
        for userImagePath in userImagePaths_device {
            XCTAssertFalse(BinaryImageInfo.isPathSystemImageInDevice(userImagePath), "\(userImagePath) is an user image")
        }
        for userImagePath in userImagePaths_simulator {
            XCTAssertFalse(BinaryImageInfo.isPathSystemImageInSimulator(userImagePath), "\(userImagePath) is an user image")
        }
    }

    func testItReadsBinaryImageInfo() throws {
        func mock(with imagePath: URL) -> PLCrashReportMock.BinaryImageInfo {
            let mock = PLCrashReportMock.BinaryImageInfo()
            mock.mockImageUUID = .mockRandom()
            mock.mockHasImageUUID = true
            mock.mockImageName = imagePath.path
            mock.mockImageBaseAddress = .mockRandom()
            mock.mockImageSize = .mockRandom()
            mock.mockCodeType = .init()
            mock.mockCodeType.mockTypeEncoding = PLCrashReportProcessorTypeEncodingMach
            mock.mockCodeType.mockType = UInt64(CPU_TYPE_X86_64)
            return mock
        }

        // Given
        #if targetEnvironment(simulator)
        let systemImagePath = URL(string: systemImagePaths_simulator.randomElement()!)!
        let userImagePath = URL(string: userImagePaths_simulator.randomElement()!)!
        #else
        let systemImagePath = URL(string: systemImagePaths_device.randomElement()!)!
        let userImagePath = URL(string: userImagePaths_device.randomElement()!)!
        #endif

        let mockSystemImage = mock(with: systemImagePath)
        let mockUserImage = mock(with: userImagePath)

        // When
        let systemBinaryImageInfo = try XCTUnwrap(BinaryImageInfo(from: mockSystemImage))
        let userBinaryImageInfo = try XCTUnwrap(BinaryImageInfo(from: mockUserImage))

        // Then
        XCTAssertEqual(systemBinaryImageInfo.uuid, mockSystemImage.mockImageUUID)
        XCTAssertEqual(systemBinaryImageInfo.imageName, systemImagePath.lastPathComponent)
        XCTAssertTrue(systemBinaryImageInfo.isSystemImage, "\(systemImagePath) is a system image")
        XCTAssertEqual(systemBinaryImageInfo.imageBaseAddress, mockSystemImage.mockImageBaseAddress)
        XCTAssertEqual(systemBinaryImageInfo.imageSize, mockSystemImage.mockImageSize)
        XCTAssertEqual(systemBinaryImageInfo.codeType?.architectureName, "x86_64")

        XCTAssertEqual(userBinaryImageInfo.uuid, mockUserImage.mockImageUUID)
        XCTAssertEqual(userBinaryImageInfo.imageName, userImagePath.lastPathComponent)
        XCTAssertFalse(userBinaryImageInfo.isSystemImage, "\(userImagePath) is a user image")
        XCTAssertEqual(userBinaryImageInfo.imageBaseAddress, mockUserImage.mockImageBaseAddress)
        XCTAssertEqual(userBinaryImageInfo.imageSize, mockUserImage.mockImageSize)
        XCTAssertEqual(userBinaryImageInfo.codeType?.architectureName, "x86_64")
    }

    func testItReadsCodeType() {
        typealias ProcessorInfo = PLCrashReportMock.BinaryImageInfo.ProcessorInfo
        typealias CodeType = BinaryImageInfo.CodeType

        func mockKnownProcessorInfo(type: UInt64, subtype: UInt64) -> ProcessorInfo {
            let mock = ProcessorInfo()
            mock.mockTypeEncoding = PLCrashReportProcessorTypeEncodingMach
            mock.mockType = type
            mock.mockSubtype = subtype
            return mock
        }

        func mockUnknownProcessorInfo() -> ProcessorInfo {
            let mock = ProcessorInfo()
            mock.mockTypeEncoding = PLCrashReportProcessorTypeEncodingUnknown
            mock.mockType = .mockRandom()
            mock.mockSubtype = .mockRandom()
            return mock
        }

        var mock = mockKnownProcessorInfo(type: UInt64(CPU_TYPE_X86), subtype: .mockRandom())
        XCTAssertEqual(CodeType(from: mock)?.architectureName, "i386")

        mock = mockKnownProcessorInfo(type: UInt64(CPU_TYPE_X86_64), subtype: .mockRandom())
        XCTAssertEqual(CodeType(from: mock)?.architectureName, "x86_64")

        mock = mockKnownProcessorInfo(type: UInt64(CPU_TYPE_ARM), subtype: .mockRandom())
        XCTAssertEqual(CodeType(from: mock)?.architectureName, "arm")

        // We use XOR to get a value different than any XOR component:
        mock = mockKnownProcessorInfo(type: UInt64(CPU_TYPE_ARM ^ CPU_TYPE_X86_64 ^ CPU_TYPE_ARM ^ CPU_TYPE_ARM64), subtype: .mockRandom())
        XCTAssertNil(CodeType(from: mock)?.architectureName)

        mock = mockKnownProcessorInfo(type: UInt64(CPU_TYPE_ARM64), subtype: UInt64(CPU_SUBTYPE_ARM64_ALL))
        XCTAssertEqual(CodeType(from: mock)?.architectureName, "arm64")

        mock = mockKnownProcessorInfo(type: UInt64(CPU_TYPE_ARM64), subtype: UInt64(CPU_SUBTYPE_ARM64_V8))
        XCTAssertEqual(CodeType(from: mock)?.architectureName, "armv8")

        mock = mockKnownProcessorInfo(type: UInt64(CPU_TYPE_ARM64), subtype: UInt64(CPU_SUBTYPE_ARM64E))
        XCTAssertEqual(CodeType(from: mock)?.architectureName, "arm64e")

        // We use XOR to get a value different than any XOR component:
        mock = mockKnownProcessorInfo(type: UInt64(CPU_TYPE_ARM64), subtype: UInt64(CPU_SUBTYPE_ARM64_ALL ^ CPU_SUBTYPE_ARM64_V8 ^ CPU_SUBTYPE_ARM64E))
        XCTAssertEqual(CodeType(from: mock)?.architectureName, "arm64-unknown")

        mock = mockUnknownProcessorInfo()
        XCTAssertNil(CodeType(from: mock))
    }

    func testItReadsStackFrameWhenItsBinaryImageIsFound() {
        // Given
        let stackFrameNumber: Int = .mockRandom()
        let imagePath: URL = .mockRandomPath()
        let mockImage = PLCrashReportMock.BinaryImageInfo()
        mockImage.mockHasImageUUID = true
        mockImage.mockImageUUID = .mockRandom()
        mockImage.mockImageName = imagePath.path
        mockImage.mockImageBaseAddress = .mockRandom()

        let mockStackFrame = PLCrashReportMock.StackFrame()
        mockStackFrame.mockInstructionPointer = .mockRandom()

        // When
        let mock = PLCrashReportMock()
        mock.mockImageForAddress[mockStackFrame.mockInstructionPointer] = mockImage  // register mock image

        let stackFrameInfo = StackFrame(from: mockStackFrame, number: stackFrameNumber, in: mock)

        // Then
        XCTAssertEqual(stackFrameInfo.number, stackFrameNumber)
        XCTAssertEqual(stackFrameInfo.instructionPointer, mockStackFrame.mockInstructionPointer)
        XCTAssertEqual(stackFrameInfo.libraryName, imagePath.lastPathComponent)
        XCTAssertEqual(stackFrameInfo.libraryBaseAddress, mockImage.mockImageBaseAddress)
    }

    func testItReadsStackFrameWhenItsBinaryImageIsNotFound() {
        // Given
        let stackFrameNumber: Int = .mockRandom()
        let mockStackFrame = PLCrashReportMock.StackFrame()
        mockStackFrame.mockInstructionPointer = .mockRandom()

        // When
        let mock = PLCrashReportMock()
        mock.mockImageForAddress = [:]  // do not register any image

        let stackFrameInfo = StackFrame(from: mockStackFrame, number: stackFrameNumber, in: mock)

        // Then
        XCTAssertEqual(stackFrameInfo.number, stackFrameNumber)
        XCTAssertEqual(stackFrameInfo.instructionPointer, mockStackFrame.mockInstructionPointer)
        XCTAssertNil(stackFrameInfo.libraryName)
        XCTAssertNil(stackFrameInfo.libraryBaseAddress)
    }
}
