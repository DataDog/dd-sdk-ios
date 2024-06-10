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
public struct Sysctl {
    /// Possible errors.
    enum Error: Swift.Error {
        case unknown
        case malformedUTF8
        case malformedData
        case posixError(POSIXErrorCode)
    }

    public init() {
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
    static func model() throws -> String {
        #if os(iOS) && !arch(x86_64) && !arch(i386) // iOS device && not Simulator
            return try Sysctl.string(for: [CTL_HW, HW_MACHINE])
        #else
            return try Sysctl.string(for: [CTL_HW, HW_MODEL])
        #endif
    }

    /// e.g. "15D21" or "13D20"
    public static func osVersion() throws -> String {
        try Sysctl.string(for: [CTL_KERN, KERN_OSVERSION])
    }

    public static func systemBootTime() throws -> TimeInterval {
        let bootTime = try Sysctl.data(for: [CTL_KERN, KERN_BOOTTIME])
        let uptime = bootTime.withUnsafeBufferPointer { buffer -> timeval? in
            buffer.baseAddress?.withMemoryRebound(to: timeval.self, capacity: 1) { $0.pointee }
        }
        guard let uptime = uptime else {
            throw Error.malformedData
        }
        return TimeInterval(uptime.tv_sec)
    }

    /// https://developer.apple.com/library/archive/qa/qa1361/_index.html
    public static func isBeingDebugged() -> Bool {
        var mib = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size

        let junk = sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0)
        assert(junk == 0)

        return (info.kp_proc.p_flag & P_TRACED) != 0
    }
}

extension Sysctl: SysctlProviding {
    public func osVersion() throws -> String {
        try Sysctl.osVersion()
    }

    public func systemBootTime() throws -> TimeInterval {
        try Sysctl.systemBootTime()
    }

    public func isDebugging() -> Bool {
        Sysctl.isBeingDebugged()
    }
}

/// A `SysctlProviding` implementation that uses `Darwin.sysctl` to access system information.
public protocol SysctlProviding {
    /// Returns operating system version.
    /// - Returns: Operating system version.
    func osVersion() throws -> String

    /// Returns system boot time since epoch.
    /// - Returns: System boot time.
    func systemBootTime() throws -> TimeInterval

    /// Returns `true` if the app is being debugged.
    /// - Returns: `true` if the app is being debugged.
    func isDebugging() -> Bool
}
