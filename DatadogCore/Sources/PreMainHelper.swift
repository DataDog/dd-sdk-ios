/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
//@objc(PreMainHelper)
//class PreMainHelper: NSObject {
//    @objc static func recordMainInitialization() {
//        let formatter = DateFormatter()
//        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
//        let timestamp = formatter.string(from: Date())
//        print("[\(timestamp)] 👉 recordMainInitialization called")
//    }
//}

@objc(PreMainHelper)
@objcMembers
public class PreMainHelper: NSObject {

    private static var processStart: Date {

        ProcessInfo.processStartTime()
    }

    private static var systemStart: Date {

        ProcessInfo.systemStartTime()
    }

    private static var loadExecution: Date?
    private static var firstAttribute: Date?
    private static var secondAttribute: Date?
    private static var mainExecution: Date?
    private static var postMainExecution: Date?
    private static var firstFrame: Date?
    private static var fullDisplay: Date?
}

public extension PreMainHelper {

    public static func recordLoadExecution() { Self.loadExecution = Date() }
    public static func recordFirstAttribute() { Self.firstAttribute = Date() }
    public static func recordSecondAttribute() { Self.secondAttribute = Date() }
    public static func recordMainExecution() { Self.mainExecution = Date() }
    public static func recordPostMainExecution() { Self.postMainExecution = Date() }
    public static func recordFirstFrame(_ date: Date? = nil) { Self.firstFrame = date }
    public static func recordFullDisplay(_ date: Date? = nil) {
        guard let firstFrame, let date else { return }

        Self.fullDisplay = firstFrame < date ? date : firstFrame
    }

    @nonobjc public  static var info: PreMainInfo? {

        guard let secondAttribute = Self.secondAttribute,
              let firstAttribute = Self.firstAttribute,
              let loadExecution = Self.loadExecution,
              let mainExecution = Self.mainExecution,
              let postMainExecution = Self.postMainExecution,
              let firstFrame = Self.firstFrame else {
            return nil }

        return PreMainInfo(processStart: Self.processStart,
                           systemStart: Self.systemStart,
                           loadExecution: loadExecution,
                           firstAttribute: firstAttribute,
                           secondAttribute: secondAttribute,
                           mainExecution: mainExecution,
                           postMainExecution: postMainExecution,
                           firstFrame: firstFrame,
                           fullDisplay: fullDisplay)
    }
}

/// Date formatter producing string representation of a given date for user-facing features (like console output).
let shortFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    return formatter
}()


public struct PreMainInfo: CustomDebugStringConvertible {

    let processStart: Date
    let systemStart: Date
    public let processToLoad: TimeInterval
    public let didFinishLaunching: TimeInterval
    public let processBootstrap: TimeInterval
    public let processBootstrap2: TimeInterval
    public let mainInitialization: TimeInterval
    public let mainDuration: TimeInterval
    public let preWarmingGapDuration: TimeInterval
    public let ttid: TimeInterval
    public let ttfd: TimeInterval?

    public init(processStart: Date,
         systemStart: Date,
         loadExecution: Date,
         firstAttribute: Date,
         secondAttribute: Date,
         mainExecution: Date,
         postMainExecution: Date,
         firstFrame: Date,
         fullDisplay: Date?) {

        self.processStart = processStart
        self.systemStart = systemStart
        self.processToLoad = loadExecution.timeIntervalSince1970 - processStart.timeIntervalSince1970
        self.processBootstrap = firstAttribute.timeIntervalSince1970 - processStart.timeIntervalSince1970
        self.processBootstrap2 = secondAttribute.timeIntervalSince1970 - processStart.timeIntervalSince1970
        self.mainInitialization = mainExecution.timeIntervalSince1970 - processStart.timeIntervalSince1970
        self.didFinishLaunching = postMainExecution.timeIntervalSince1970 - processStart.timeIntervalSince1970
        self.ttid = firstFrame.timeIntervalSince1970 - processStart.timeIntervalSince1970

        if let fullDisplay {
            self.ttfd = fullDisplay.timeIntervalSince1970 - processStart.timeIntervalSince1970
        } else {
            self.ttfd = nil
        }

        self.preWarmingGapDuration = postMainExecution.timeIntervalSince1970 - secondAttribute.timeIntervalSince1970
        self.mainDuration = postMainExecution.timeIntervalSince1970 - mainExecution.timeIntervalSince1970
    }

    private func format(_ interval: TimeInterval?) -> String {
        guard let interval else {
            return "N/A"
        }

        return String(format: "%.6f s", interval)
    }

    public var loadString: String { "+ (void)load        = \(format(processToLoad))" }
    public var attribute101String: String { "__attribute__ 101   = \(format(processBootstrap))" }
    public var attribute65000String: String { "__attribute__ 65000 = \(format(processBootstrap2))" }
    public var mainString: String { "main                = \(format(mainInitialization))" }
    public var didFinishLaunchingString: String { "didFinishLaunching  = \(format(didFinishLaunching))" }
    public var ttidString: String { "TTID                = \(format(ttid))" }
    public var ttfdString: String { "TTFD                = \(format(ttfd))" }

    public var displayDescription: String {
            """
            ⏱ System start: \(shortFormatter.string(from: systemStart))
            ⏱ App start:    \(shortFormatter.string(from: processStart))
            """
    }

    public var debugDescription: String {
            """
            ⏱ System start: \(systemStart)
            ⏱ App start:    \(processStart) {
                + (void)load        = \(format(processToLoad))
                __attribute__ 101   = \(format(processBootstrap))
                __attribute__ 65000 = \(format(processBootstrap2)) - preWarmingGap   \(format(preWarmingGapDuration))
                main                = \(format(mainInitialization)) - mainDapDuration \(format(mainDuration))
                didFinishLaunching  = \(format(didFinishLaunching))
                TTID                = \(format(ttid))
                TTFD                = \(format(ttfd))
            }
            """
    }
}


extension ProcessInfo {

    public static func processStartTime() -> Date {

        var size = MemoryLayout<kinfo_proc>.stride
        var kp = kinfo_proc()
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]

        _ = withUnsafeMutablePointer(to: &kp) {

            $0.withMemoryRebound(to: Int8.self, capacity: size) {

                sysctl(&mib, UInt32(mib.count), $0, &size, nil, 0)
            }
        }

        let startTime = kp.kp_proc.p_un.__p_starttime
        let timeInterval = TimeInterval(startTime.tv_sec) + TimeInterval(startTime.tv_usec) / 1E6

        return Date(timeIntervalSince1970: timeInterval)
    }
}

extension ProcessInfo {

    @inline(__always)
    public static func systemStartTime() -> Date {
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        let mibCount = u_int(mib.count)       // precompute; don't read mib in closure

        var tv = timeval()
        var size = MemoryLayout<timeval>.size

        let rc: Int32 = mib.withUnsafeMutableBufferPointer { mibPtr in
            // Use a local copy for size since it's inout for sysctl
            var localSize = size
            return sysctl(mibPtr.baseAddress, mibCount, &tv, &localSize, nil, 0)
        }

        if rc != 0 {
            let errStr = String(cString: strerror(errno))
            fputs("Could not get timeval value for : \(errStr)\n", stderr)
        }

        let timeInterval = TimeInterval(tv.tv_sec) + TimeInterval(tv.tv_usec) / 1E6
        return Date(timeIntervalSince1970: timeInterval)
    }
}
