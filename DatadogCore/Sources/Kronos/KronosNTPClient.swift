/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 *
 * This file includes software developed by MobileNativeFoundation, https://mobilenativefoundation.org and altered by Datadog.
 * Use of this source code is governed by Apache License 2.0 license: https://github.com/MobileNativeFoundation/Kronos/blob/main/LICENSE
 */

import Foundation

internal let kronosDefaultTimeout = 6.0
private let kDefaultSamples = 4
private let kMaximumNTPServers = 5
private let kMaximumResultDispersion = 10.0

private typealias ObjCCompletionType = @convention(block) (Data?, TimeInterval) -> Void

/// Exception raised while sending / receiving NTP packets.
internal enum KronosNTPNetworkError: Error {
    case noValidNTPPacketFound
}

/// NTP client session.
internal final class KronosNTPClient {
    /// Query the all ips that resolve from the given pool.
    ///
    /// - parameter pool:            NTP pool that will be resolved into multiple NTP servers.
    /// - parameter port:            Server NTP port (default 123).
    /// - parameter version:         NTP version to use (default 3).
    /// - parameter numberOfSamples: The number of samples to be acquired from each server (default 4).
    /// - parameter maximumServers:  The maximum number of servers to be queried (default 5).
    /// - parameter timeout:         The individual timeout for each of the NTP operations.
    /// - parameter completion:      A closure that will be response PDU on success or nil on error.
    func query(
        pool: String = "time.apple.com",
        version: Int8 = 3,
        port: Int = 123,
        numberOfSamples: Int = kDefaultSamples,
        maximumServers: Int = kMaximumNTPServers,
        timeout: CFTimeInterval = kronosDefaultTimeout,
        progress: @escaping (TimeInterval?, Int, Int) -> Void
    ) {
        var servers: [KronosInternetAddress: [KronosNTPPacket]] = [:]
        var completed: Int = 0

        let queryIPAndStoreResult = { (address: KronosInternetAddress, totalQueries: Int) -> Void in
            self.query(ip: address, port: port, version: version, timeout: timeout, numberOfSamples: numberOfSamples) { packet in
                defer {
                    completed += 1

                    let responses = Array(servers.values)
                    progress(try? self.offset(from: responses), completed, totalQueries)
                }

                guard let PDU = packet else {
                    return
                }

                if servers[address] == nil {
                    servers[address] = []
                }

                servers[address]?.append(PDU)
            }
        }

        KronosDNSResolver.resolve(host: pool) { addresses in
            if addresses.count == 0 {
                return progress(nil, 0, 0)
            }

            let totalServers = min(addresses.count, maximumServers)
            let addressesToQuery = Array(addresses[0 ..< totalServers])

            for address in addressesToQuery {
                queryIPAndStoreResult(address, totalServers * numberOfSamples)
            }
        }
    }

    /// Query the given NTP server for the time exchange.
    ///
    /// - parameter ip:              Server socket address.
    /// - parameter port:            Server NTP port (default 123).
    /// - parameter version:         NTP version to use (default 3).
    /// - parameter timeout:         Timeout on socket operations.
    /// - parameter numberOfSamples: The number of samples to be acquired from the server (default 4).
    /// - parameter completion:      A closure that will be response PDU on success or nil on error.
    func query(
        ip: KronosInternetAddress,
        port: Int = 123,
        version: Int8 = 3,
        timeout: CFTimeInterval = kronosDefaultTimeout,
        numberOfSamples: Int = kDefaultSamples,
        completion: @escaping (KronosNTPPacket?) -> Void
    ) {
        var timer: Timer?
        let bridgeCallback: ObjCCompletionType = { data, destinationTime in
            defer {
                // If we still have samples left; we'll keep querying the same server
                if numberOfSamples > 1 {
                    self.query(ip: ip, port: port, version: version, timeout: timeout, numberOfSamples: numberOfSamples - 1, completion: completion)
                }
            }
            timer?.invalidate()
            guard
                let data = data, let PDU = try? KronosNTPPacket(data: data, destinationTime: destinationTime),
                PDU.isValidResponse() else
            {
                completion(nil)
                return
            }

            completion(PDU)
        }

        let callback = unsafeBitCast(bridgeCallback, to: AnyObject.self)
        let retainedCallback = Unmanaged.passRetained(callback)
        let sourceAndSocket = self.sendAsyncUDPQuery(
            to: ip, port: port, timeout: timeout, completion: UnsafeMutableRawPointer(retainedCallback.toOpaque())
        )

        timer = KronosBlockTimer.scheduledTimer(withTimeInterval: timeout, repeated: true) { _ in
            bridgeCallback(nil, TimeInterval.infinity)
            retainedCallback.release()

            if let (source, socket) = sourceAndSocket {
                CFSocketInvalidate(socket)
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, CFRunLoopMode.commonModes)
            }
        }
    }

    // MARK: - Private helpers (NTP Calculation)

    private func offset(from responses: [[KronosNTPPacket]]) throws -> TimeInterval {
        let now = kronosCurrentTime()
        var bestResponses: [KronosNTPPacket] = []
        for serverResponses in responses {
            let filtered = serverResponses
                .filter { abs($0.originTime - now) < kMaximumResultDispersion }
                .min { $0.delay < $1.delay }

            if let filtered = filtered {
                bestResponses.append(filtered)
            }
        }

        if bestResponses.count == 0 {
            throw KronosNTPNetworkError.noValidNTPPacketFound
        }

        bestResponses.sort { $0.offset < $1.offset }
        return bestResponses[bestResponses.count / 2].offset
    }

    // MARK: - Private helpers (CFSocket)

    private func sendAsyncUDPQuery(
        to ip: KronosInternetAddress,
        port: Int,
        timeout: TimeInterval,
        completion: UnsafeMutableRawPointer
    ) -> (CFRunLoopSource, CFSocket)? {
        signal(SIGPIPE, SIG_IGN)

        let callback: CFSocketCallBack = { socket, callbackType, _, data, info in
            if callbackType == .writeCallBack {
                var packet = KronosNTPPacket()
                let PDU = packet.prepareToSend() as CFData
                CFSocketSendData(socket, nil, PDU, kronosDefaultTimeout)
                return
            }

            guard let info = info else {
                return
            }

            CFSocketInvalidate(socket)

            let destinationTime = kronosCurrentTime()
            let retainedClosure = Unmanaged<AnyObject>.fromOpaque(info)
            let completion = unsafeBitCast(retainedClosure.takeUnretainedValue(), to: ObjCCompletionType.self)

            let data = unsafeBitCast(data, to: CFData.self) as Data?
            completion(data, destinationTime)
            retainedClosure.release()
        }

        let types = CFSocketCallBackType.dataCallBack.rawValue | CFSocketCallBackType.writeCallBack.rawValue
        var context = CFSocketContext(version: 0, info: completion, retain: nil, release: nil, copyDescription: nil)
        guard let socket = CFSocketCreate(nil, ip.family, SOCK_DGRAM, IPPROTO_UDP, types, callback, &context),
                CFSocketIsValid(socket) else {
            return nil
        }

        let runLoopSource = CFSocketCreateRunLoopSource(kCFAllocatorDefault, socket, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, CFRunLoopMode.commonModes)
        CFSocketConnectToAddress(socket, ip.addressData(withPort: port), timeout)
        return (runLoopSource!, socket) // swiftlint:disable:this force_unwrapping
    }
}
