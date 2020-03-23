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

        let availableInterfaces: [NetworkConnectionInfo.Interface] = {
            info.availableInterfaces.map { interface in
                switch interface.type {
                case .wifi: return .wifi
                case .wiredEthernet: return .wiredEthernet
                case .cellular: return .cellular
                case .loopback: return .loopback
                case .other: return .other
                @unknown default: return .other
                }
            }
        }()

        let reachability: NetworkConnectionInfo.Reachability = {
            switch info.status {
            case .satisfied: return .yes
            case .requiresConnection: return .maybe
            case .unsatisfied: return .no
            @unknown default: return .maybe
            }
        }()

        let isCurrentPathConstrained: Bool? = {
            if #available(iOS 13.0, macOS 10.15, *) {
                return info.isConstrained
            } else {
                return nil
            }
        }()

        return NetworkConnectionInfo(
            reachability: reachability,
            availableInterfaces: availableInterfaces,
            supportsIPv4: info.supportsIPv4,
            supportsIPv6: info.supportsIPv6,
            isExpensive: info.isExpensive,
            isConstrained: isCurrentPathConstrained
        )
    }
}

// MARK: - Legacy Network Path Monitor

import SystemConfiguration

internal class iOS11PathMonitor {
    private let reachability: SCNetworkReachability = {
        var zero = sockaddr()
        zero.sa_len = UInt8(MemoryLayout<sockaddr>.size)
        zero.sa_family = sa_family_t(AF_INET)

        return SCNetworkReachabilityCreateWithAddress(nil, &zero)! // swiftlint:disable:this force_unwrapping
    }()

    var current: NetworkConnectionInfo {
        var flags: SCNetworkReachabilityFlags?
        var retrieval = SCNetworkReachabilityFlags()
        flags = (SCNetworkReachabilityGetFlags(reachability, &retrieval)) ? retrieval : nil

        let reachableFlag = flags?.contains(.reachable)
        let reachable: NetworkConnectionInfo.Reachability = {
            switch reachableFlag {
            case .none:
                return .maybe
            case .some(true):
                return .yes
            case .some(false):
                return .no
            }
        }()
        let cellular = flags?.contains(.isWWAN) ?? false

        // TODO: RUMM-312 what to do with unknowns?
        return NetworkConnectionInfo(
            reachability: reachable,
            availableInterfaces: cellular ? [.cellular] : [],
            supportsIPv4: false,
            supportsIPv6: false,
            isExpensive: false,
            isConstrained: false
        )
    }
}
