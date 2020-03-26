/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Network

@available(iOS 12, *)
extension NWPathMonitor {
    var current: NetworkConnectionInfo {
        let info = currentPath

        let isCurrentPathConstrained: Bool? = {
            if #available(iOS 13.0, *) {
                return info.isConstrained
            } else {
                return nil
            }
        }()

        return NetworkConnectionInfo(
            reachability: NetworkConnectionInfo.Reachability(from: info.status),
            availableInterfaces: Array(fromInterfaceTypes: info.availableInterfaces.map { $0.type }),
            supportsIPv4: info.supportsIPv4,
            supportsIPv6: info.supportsIPv6,
            isExpensive: info.isExpensive,
            isConstrained: isCurrentPathConstrained
        )
    }
}

// MARK: - iOS 11 Network Path Monitor

import SystemConfiguration

internal class iOS11PathMonitor {
    private let reachability: SCNetworkReachability = {
        var zero = sockaddr()
        zero.sa_len = UInt8(MemoryLayout<sockaddr>.size)
        zero.sa_family = sa_family_t(AF_INET)

        return SCNetworkReachabilityCreateWithAddress(nil, &zero)! // swiftlint:disable:this force_unwrapping
    }()

    var current: NetworkConnectionInfo {
        var retrieval = SCNetworkReachabilityFlags()
        let flags = (SCNetworkReachabilityGetFlags(reachability, &retrieval)) ? retrieval : nil
        return NetworkConnectionInfo(
            reachability: NetworkConnectionInfo.Reachability(from: flags),
            availableInterfaces: Array(fromReachabilityFlags: flags),
            supportsIPv4: nil,
            supportsIPv6: nil,
            isExpensive: nil,
            isConstrained: nil
        )
    }
}

// MARK: Conversion helpers

extension NetworkConnectionInfo.Reachability {
    @available(iOS 12, *)
    init(from status: NWPath.Status) {
        switch status {
        case .satisfied: self = .yes
        case .requiresConnection: self = .maybe
        case .unsatisfied: self = .no
        @unknown default: self = .maybe
        }
    }

    init(from flags: SCNetworkReachabilityFlags?) {
        switch flags?.contains(.reachable) {
        case .none: self = .maybe
        case .some(true): self = .yes
        case .some(false): self = .no
        }
    }
}

extension Array where Element == NetworkConnectionInfo.Interface {
    @available(iOS 12, *)
    init(fromInterfaceTypes interfaceTypes: [NWInterface.InterfaceType]) {
        self = interfaceTypes.map { interface in
            switch interface {
            case .wifi: return .wifi
            case .wiredEthernet: return .wiredEthernet
            case .cellular: return .cellular
            case .loopback: return .loopback
            case .other: return .other
            @unknown default: return .other
            }
        }
    }

    @available(iOS 2.0, macCatalyst 13.0, *)
    init?(fromReachabilityFlags flags: SCNetworkReachabilityFlags?) {
        if let flags = flags,
            flags.contains(.isWWAN) {
            self = [.cellular]
        } else {
            return nil
        }
    }
}
