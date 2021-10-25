/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import MachO

/// It stores information about loaded mach images
private struct MachImage {
    let header: UnsafePointer<mach_header>?
    let slide: UInt64
    let path: String
}

internal struct SymbolicatedStackFrame {
    let symbol: String
    let isUserFrame: Bool
    let originalStackFrame: StackFrame
}

internal struct CrashReportSymbolicator {
    private let crashReport: CrashReport

    init(crashReport: CrashReport) {
        self.crashReport = crashReport
    }

    /// Structure to store all loaded libraries and images in the process
    private var machImagesByLibraryName: [String: MachImage] = {
        /// User library addresses are randomized each time an app is run, create a map to locate library addresses by name,
        /// system libraries are not so address returned is 0
        var images = [String: MachImage]()
        let numImages = _dyld_image_count()
        for i in 0 ..< numImages {
            let path = String(cString: _dyld_get_image_name(i))
            let name = URL(fileURLWithPath: path).lastPathComponent
            let header = _dyld_get_image_header(i)
            let slide = _dyld_get_image_vmaddr_slide(i)
            if slide != 0 {
                images[name] = MachImage(header: header, slide: UInt64(UInt(bitPattern: header)), path: path)
            }
        }
        return images
    }()

    func symbolicate(stackFrames: [StackFrame]) -> [SymbolicatedStackFrame] {
        return stackFrames.compactMap { frame in
            guard let libraryName = frame.libraryName else {
                print("⚠️ no library name in '\(frame)'")
                return nil
            }
            // Read image from crash report:
            guard let binaryImage = crashReport.binaryImages.first(where: { $0.imageName == libraryName }) else {
                print("⚠️ no binary image for '\(libraryName)'")
                return nil
            }
            // Read image from current process:
            guard let machImage = machImagesByLibraryName[libraryName] else {
                print("⚠️ no mach image for '\(libraryName)'")
                return nil
            }

            let instructionOffset = frame.instructionPointer - binaryImage.imageBaseAddress
            let instructionAddress = machImage.slide + instructionOffset

            guard let pointer = UnsafeRawPointer(bitPattern: UInt(instructionAddress)) else {
                print("⚠️ can't construct pointer")
                return nil
            }

            var info = Dl_info()
            let result = dladdr(pointer, &info)
            if result != 0 {
                var symbolName = info.dli_sname != nil ? String(cString: info.dli_sname) : ""
                if symbolName != "" {
                    symbolName = demangleName(symbolName)
                }
                return SymbolicatedStackFrame(
                    symbol: symbolName,
                    isUserFrame: !binaryImage.isSystemImage,
                    originalStackFrame: frame
                )
            }

            print("⚠️ can't read symbol for pointer (dladdr result: \(result)")
            return nil
        }
    }

    private func addressToUInt(_ address: String) -> UInt? {
        guard let float64 = Float64(address) else {
            return nil
        }
        return UInt(float64)
    }

    private func demangleName(_ mangledName: String) -> String {
        return mangledName.utf8CString.withUnsafeBufferPointer { mangledNameUTF8CStr in
            let demangledNamePtr = _stdlib_demangleImpl(
                mangledName: mangledNameUTF8CStr.baseAddress,
                mangledNameLength: UInt(mangledNameUTF8CStr.count - 1),
                outputBuffer: nil,
                outputBufferSize: nil,
                flags: 0
            )

            if let demangledNamePtr = demangledNamePtr {
                let demangledName = String(cString: demangledNamePtr)
                free(demangledNamePtr)
                return demangledName
            }
            return mangledName
        }
    }
}

/// It's just for the POC. We can't ship this, as it's depending on ABI without guarateeing its stability.
@_silgen_name("swift_demangle")
private func _stdlib_demangleImpl(
    mangledName: UnsafePointer<CChar>?,
    mangledNameLength: UInt,
    outputBuffer: UnsafeMutablePointer<CChar>?,
    outputBufferSize: UnsafeMutablePointer<UInt>?,
    flags: UInt32
) -> UnsafeMutablePointer<CChar>?
