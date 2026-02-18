/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if !os(watchOS)
import Foundation
import TestUtilities
import DatadogMachProfiler.Cxx

extension binary_image_t {
    static func mockAny() -> binary_image_t {
        return mockWith()
    }

    static func mockWith(
        loadAddress: UInt64 = 0x100000000,
        uuid: UUID = UUID(uuidString: "01234567-89AB-CDEF-0123-456789ABCDEF")!,
        filename: StaticString = "TestBinary"
    ) -> binary_image_t {
        return binary_image_t(
            load_address: loadAddress,
            uuid: uuid.uuid,
            filename: UnsafeRawPointer(filename.utf8Start).assumingMemoryBound(to: CChar.self)
        )
    }
}

extension stack_trace_t {
    static func mockWith(
        tid: UInt32,
        addresses: [UInt64],
        threadName: StaticString = "TestThread",
        timestamp: UInt64? = nil,
        samplingIntervalNanos: UInt64 = 10_000_000,
        binaryImage: binary_image_t = .mockAny()
    ) -> stack_trace_t {
        let frameCount = UInt32(addresses.count)
        let frames: UnsafeMutablePointer<stack_frame_t>?

        if frameCount > 0 {
            frames = UnsafeMutablePointer<stack_frame_t>.allocate(capacity: Int(frameCount))
            for (index, address) in addresses.enumerated() {
                frames![index] = stack_frame_t(
                    instruction_ptr: address,
                    image: binaryImage
                )
            }
        } else {
            frames = nil
        }

        return stack_trace_t(
            tid: tid,
            thread_name: UnsafeRawPointer(threadName.utf8Start).assumingMemoryBound(to: CChar.self),
            timestamp: timestamp ?? UInt64(Date().timeIntervalSince1970 * 1_000_000_000),
            sampling_interval_nanos: samplingIntervalNanos,
            frames: frames,
            frame_count: frameCount
        )
    }
}
#endif // !os(watchOS)
