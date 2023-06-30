/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 *
 * This file includes software created by Matt Gallagher on 2016/02/03 and modified by Datadog.
 * Copyright © 2016 Matt Gallagher ( https://www.cocoawithlove.com ).
 *
 * Permission to use, copy, modify, and/or distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 *
 * Use of this source code is governed by ISC license: https://github.com/mattgallagher/CwlUtils/blob/master/LICENSE.txt
 */

import Foundation

/// A "static"-only namespace around a series of functions that operate on buffers returned from the `Darwin.sysctl` function
internal struct Sysctl {
    /// Possible errors.
    enum Error: Swift.Error {
        case unknown
        case malformedUTF8
        case posixError(POSIXErrorCode)
    }

    /// Access the raw data for an array of sysctl identifiers.
    private static func data(for keys: [Int32]) throws -> [Int8] {
        return try keys.withUnsafeBufferPointer { keysPointer throws -> [Int8] in
            // Preflight the request to get the required data size
            var requiredSize = 0
            let preFlightResult = Darwin.sysctl(UnsafeMutablePointer<Int32>(mutating: keysPointer.baseAddress), UInt32(keys.count), nil, &requiredSize, nil, 0)
            if preFlightResult != 0 {
                throw POSIXErrorCode(rawValue: errno).map {
                    print($0.rawValue)
                    return Error.posixError($0)
                } ?? Error.unknown
            }

            // Run the actual request with an appropriately sized array buffer
            let data: [Int8] = Array(repeating: 0, count: requiredSize)
            let result = data.withUnsafeBufferPointer { dataBuffer -> Int32 in
                return Darwin.sysctl(UnsafeMutablePointer<Int32>(mutating: keysPointer.baseAddress), UInt32(keys.count), UnsafeMutableRawPointer(mutating: dataBuffer.baseAddress), &requiredSize, nil, 0)
            }
            if result != 0 {
                throw POSIXErrorCode(rawValue: errno).map { Error.posixError($0) } ?? Error.unknown
            }

            return data
        }
    }

    /// Invoke `sysctl` with an array of identifers, interpreting the returned buffer as a `String`. This function will throw `Error.malformedUTF8` if the buffer returned from `sysctl` cannot be interpreted as a UTF8 buffer.
    private static func string(for keys: [Int32]) throws -> String {
        let optionalString = try data(for: keys).withUnsafeBufferPointer { dataPointer -> String? in
            dataPointer.baseAddress.flatMap { String(validatingUTF8: $0) }
        }
        guard let s = optionalString else {
            throw Error.malformedUTF8
        }
        return s
    }

    /// e.g. "MacPro4,1" or "iPhone8,1"
    /// NOTE: this is *corrected* on iOS devices to fetch hw.machine
    static func getModel() throws -> String {
        #if os(iOS) && !arch(x86_64) && !arch(i386) // iOS device && not Simulator
            return try Sysctl.string(for: [CTL_HW, HW_MACHINE])
        #else
            return try Sysctl.string(for: [CTL_HW, HW_MODEL])
        #endif
    }
}
