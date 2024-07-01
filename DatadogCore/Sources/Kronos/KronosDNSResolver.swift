/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 *
 * This file includes software developed by MobileNativeFoundation, https://mobilenativefoundation.org and altered by Datadog.
 * Use of this source code is governed by Apache License 2.0 license: https://github.com/MobileNativeFoundation/Kronos/blob/main/LICENSE
 */

import Foundation

private let kCopyNoOperation = unsafeBitCast(0, to: CFAllocatorCopyDescriptionCallBack.self)
private let kDefaultTimeout = 8.0

internal final class KronosDNSResolver {
    private var completion: (([KronosInternetAddress]) -> Void)?
    private var timer: Timer?

    private init() {}

    /// Performs DNS lookups and calls the given completion with the answers that are returned from the name
    /// server(s) that were queried.
    ///
    /// - parameter host:       The host to be looked up.
    /// - parameter timeout:    The connection timeout.
    /// - parameter completion: A completion block that will be called both on failure and success with a list
    ///                         of IPs.
    static func resolve(
        host: String,
        timeout: TimeInterval = kDefaultTimeout,
        completion: @escaping ([KronosInternetAddress]) -> Void
    ) {
        #if os(watchOS)
        completion([])
        #else
        let callback: CFHostClientCallBack = { host, _, _, info in
            guard let info = info else {
                return
            }
            let retainedSelf = Unmanaged<KronosDNSResolver>.fromOpaque(info)
            let resolver = retainedSelf.takeUnretainedValue()
            resolver.timer?.invalidate()
            resolver.timer = nil

            var resolved: DarwinBoolean = false
            guard let addresses = CFHostGetAddressing(host, &resolved), resolved.boolValue else {
                resolver.completion?([])
                retainedSelf.release()
                return
            }

            let IPs = (addresses.takeUnretainedValue() as NSArray)
                .compactMap { $0 as? NSData }
                .compactMap(KronosInternetAddress.init)
                .filter { ip in !ip.isPrivate } // to avoid querying private IPs, see: https://github.com/DataDog/dd-sdk-ios/issues/647

            resolver.completion?(IPs)
            retainedSelf.release()
        }

        let resolver = KronosDNSResolver()
        resolver.completion = completion

        let retainedClosure = Unmanaged.passRetained(resolver).toOpaque()
        var clientContext = CFHostClientContext(
            version: 0,
            info: UnsafeMutableRawPointer(retainedClosure),
            retain: nil,
            release: nil,
            copyDescription: kCopyNoOperation
        )

        let hostReference = CFHostCreateWithName(kCFAllocatorDefault, host as CFString).takeUnretainedValue()
        resolver.timer = Timer.scheduledTimer(
            timeInterval: timeout,
            target: resolver,
            selector: #selector(KronosDNSResolver.onTimeout),
            userInfo: hostReference,
            repeats: false
        )

        CFHostSetClient(hostReference, callback, &clientContext)
        CFHostScheduleWithRunLoop(hostReference, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        CFHostStartInfoResolution(hostReference, .addresses, nil)
        #endif
    }

    #if !os(watchOS)
    @objc
    private func onTimeout() {
        defer {
            self.completion?([])

            // Manually release the previously retained self.
            Unmanaged.passUnretained(self).release()
        }

        guard let userInfo = self.timer?.userInfo else {
            return
        }

        let hostReference = unsafeBitCast(userInfo as AnyObject, to: CFHost.self)
        CFHostCancelInfoResolution(hostReference, .addresses)
        CFHostUnscheduleFromRunLoop(hostReference, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        CFHostSetClient(hostReference, nil, nil)
    }
    #endif
}
