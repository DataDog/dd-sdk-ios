/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

// swiftlint:disable duplicate_imports
#if COCOAPODS
import KSCrash
#elseif swift(>=6.0)
internal import KSCrashRecording
#else
@_implementationOnly import KSCrashRecording
#endif
// swiftlint:enable duplicate_imports

/// A backtrace generator that uses KSCrash to capture stack traces for threads.
///
/// This implementation uses KSCrash's low-level symbolication capabilities to generate
/// backtraces for specified threads, including thread information, stack frames, and
/// binary image metadata.
internal struct KSCrashBacktrace: BacktraceReporting {
    /// Telemetry interface for reporting errors during backtrace generation.
    let telemetry: Telemetry

    /// Creates a new KSCrash-based backtrace generator.
    /// - Parameter telemetry: The telemetry interface for error reporting. Defaults to `NOPTelemetry()`.
    init(telemetry: Telemetry = NOPTelemetry()) {
        self.telemetry = telemetry
    }

    func generateBacktrace(threadID: ThreadID) throws -> BacktraceReport? {
        // Convert Mach thread_t to pthread_t
        guard let pthread = pthread_from_mach_thread_np(threadID) else {
            telemetry.error("Failed to get pthread for thread with ID: \(threadID)")
            return nil
        }

        // Capture backtrace for the thread. Initialize count with the maximum number of frames
        // we want to capture, which will be updated with the actual number of frames captured.
        var count = DatadogMinifyFilter.Constants.maxNumberOfStackFrames
        var addresses = [uintptr_t](repeating: 0, count: count)
        count = Int(captureBacktrace(thread: pthread, addresses: &addresses, count: Int32(count)))

        guard count > 0 else {
            return nil
        }

        var binaryImages: [UInt64: BinaryImage] = [:]
        let stack = (0..<count).compactMap { index in
            let address = addresses[index]

            guard
                let binaryImage = symbolicate(address: address),
                let imageName = binaryImage.name,
                let path = NSString(utf8String: imageName),
                let imageUUID = binaryImage.uuid
            else {
                return String(format: "%-4ld ??? 0x%016llx 0x0 + 0", index, address) // no binary image info
            }

            let libraryName = path.lastPathComponent
            let loadAddress = binaryImage.address
            let uuid = UUID(uuid: imageUUID.withMemoryRebound(to: uuid_t.self, capacity: 1) { $0.pointee })

            let offset: UInt64
            if address >= loadAddress {
                offset = UInt64(address) - loadAddress
            } else {
                offset = 0
                telemetry.error("Invalid image load address, symbolication will fail")
            }

            // Get architecture from binary image's CPU type
            let architecture = String(cString: kscpu_archForCPU(
                cpu_type_t(binaryImage.cpuType),
                cpu_subtype_t(binaryImage.cpuSubType)
            ))

            if binaryImages[loadAddress] == nil {
                binaryImages[loadAddress] = BinaryImage(
                    libraryName: libraryName,
                    uuid: uuid.uuidString,
                    architecture: architecture,
                    path: path,
                    loadAddress: loadAddress,
                    maxAddress: loadAddress + binaryImage.size
                )
            }

            // Format: frame_index (4 chars left-aligned) + library_name (35 chars left-aligned) + addresses + offset
            return String(format: "%-4ld %-35@ 0x%016llx 0x%016llx + %lld", index, libraryName, address, loadAddress, offset)
        }
        .joined(separator: "\n")

        // Create thread info
        let thread = DDThread(
            name: getThreadName(pthread: pthread) ?? "Thread \(threadID)",
            stack: stack,
            crashed: false,
            state: nil
        )

        return BacktraceReport(
            stack: stack,
            threads: [thread],
            binaryImages: Array(binaryImages.values),
            wasTruncated: false
        )
    }

    /// Get the name of a pthread
    private func getThreadName(pthread: pthread_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 256)
        guard pthread_getname_np(pthread, &buffer, buffer.count) == KERN_SUCCESS, buffer[0] != 0 else {
            telemetry.error("Failed to get pthread name")
            return nil // fails or empty
        }
        return String(cString: buffer)
    }
}

/// Symbolicate an address and return full binary image information including CPU type.
///
/// This function bypasses KSCrash's `ksbt_symbolicateAddress()` because that function only
/// returns a subset of binary image information via `KSSymbolInformation`, which lacks the
/// CPU type and subtype fields. Instead, we directly call the underlying `ksdl_*` functions
/// to get the complete `KSBinaryImage` struct, which includes `cpuType` and `cpuSubType`.
/// This allows us to determine the correct architecture (arm64, arm64e, etc.) for each
/// binary image, which is critical for accurate stacktrace symbolication.
private func symbolicate(address: uintptr_t) -> KSBinaryImage? {
    let untaggedAddress = kssymbolicator_callInstructionAddress(address)
    let instructionPointer = UnsafeRawPointer(bitPattern: untaggedAddress)

    // Use standard dladdr() instead of ksdl_dladdr() to work around a bug where ksdl_dladdr()
    // can return the wrong image when looking up addresses in the presence of dynamic
    // frameworks. The bug causes unsigned arithmetic underflow when calculating the
    // instruction offset.
    //
    // This was fixed in KSCrash and is currently pending release.
    // See: https://github.com/DataDog/dd-sdk-ios/issues/2645
    var info = Dl_info()
    guard
        dladdr(instructionPointer, &info) != 0,
        let baseAddress = info.dli_fbase,
        let fileName = info.dli_fname
    else {
        return nil
    }

    // Get full binary image info including CPU type
    var binaryImage = KSBinaryImage()
    guard ksdl_binaryImageForHeader(baseAddress, fileName, &binaryImage) else {
        return nil
    }

    return binaryImage
}
