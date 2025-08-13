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
    public static func recordFirstFrame() { Self.firstFrame = Date() }
    public static func recordFullDisplay() { Self.fullDisplay = Date() }

    @nonobjc public  static var info: PreMainInfo? {

        guard let secondAttribute = Self.secondAttribute,
              let firstAttribute = Self.firstAttribute,
              let loadExecution = Self.loadExecution,
              let mainExecution = Self.mainExecution,
              let postMainExecution = Self.postMainExecution,
              let firstFrame = Self.firstFrame,
              let fullDisplay = Self.fullDisplay else {

            print(
                """
            failed to have
            \(Self.secondAttribute)
            \(Self.firstAttribute)
            \(Self.loadExecution)
            \(Self.mainExecution)
            \(Self.postMainExecution)
            \(Self.firstFrame)
            \(Self.fullDisplay)
            """
            )
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

public struct PreMainInfo: CustomDebugStringConvertible {

    let processStart: Date
    let systemStart: Date
    let processToLoad: TimeInterval
    let didFinishLaunching: TimeInterval
    let processBootstrap: TimeInterval
    let processBootstrap2: TimeInterval
    let mainInitialization: TimeInterval
    let mainDuration: TimeInterval
    let preWarmingGapDuration: TimeInterval
    let ttid: TimeInterval
    let ttfd: TimeInterval

    public init(processStart: Date,
         systemStart: Date,
         loadExecution: Date,
         firstAttribute: Date,
         secondAttribute: Date,
         mainExecution: Date,
         postMainExecution: Date,
         firstFrame: Date,
         fullDisplay: Date) {

        self.processStart = processStart
        self.systemStart = systemStart
        self.processBootstrap = firstAttribute.timeIntervalSince1970 - processStart.timeIntervalSince1970
        self.processBootstrap2 = secondAttribute.timeIntervalSince1970 - processStart.timeIntervalSince1970
        self.processToLoad = loadExecution.timeIntervalSince1970 - processStart.timeIntervalSince1970
        self.mainInitialization = mainExecution.timeIntervalSince1970 - processStart.timeIntervalSince1970
        self.didFinishLaunching = postMainExecution.timeIntervalSince1970 - processStart.timeIntervalSince1970
        self.ttid = firstFrame.timeIntervalSince1970 - processStart.timeIntervalSince1970
        self.ttfd = fullDisplay.timeIntervalSince1970 - processStart.timeIntervalSince1970

        self.preWarmingGapDuration = postMainExecution.timeIntervalSince1970 - secondAttribute.timeIntervalSince1970
        self.mainDuration = postMainExecution.timeIntervalSince1970 - mainExecution.timeIntervalSince1970
    }

    private func format(_ interval: TimeInterval) -> String {
            String(format: "%.6f s", interval)
        }

    public var debugDescription: String {
            """
            ⏱ System start: \(systemStart)
            ⏱ App start: \(processStart) {
                processToLoad       = \(format(processToLoad))
                attribute101        = \(format(processBootstrap))
                attribute65000      = \(format(processBootstrap2)) - preWarmingGap   \(format(preWarmingGapDuration))
                main                = \(format(mainInitialization)) - mainDapDuration \(format(mainDuration))
                didFinishLaunching  = \(format(didFinishLaunching))
                ttid                = \(format(ttid))
                ttfd                = \(format(ttfd))
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
