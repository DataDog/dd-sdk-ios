/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

internal protocol HostsSanitizing {
    func sanitized(hosts: Set<String>, warningMessage: String) -> Set<String>
}

internal struct HostsSanitizer: HostsSanitizing {
    func sanitized(hosts: Set<String>, warningMessage: String) -> Set<String> {
        let urlRegex = #"^(http|https)://(.*)"#
        let hostRegex = #"^(([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9-]*[a-zA-Z0-9])\.)+([A-Za-z]|[A-Za-z][A-Za-z0-9-]*[A-Za-z0-9])$"#
        let ipRegex = #"^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])$"#

        var warnings: [String] = []

        let array: [String] = hosts.compactMap { host in
            if host.range(of: urlRegex, options: .regularExpression) != nil {
                // if an URL is given instead of the host, take its `host` part
                if let sanitizedHost = URL(string: host)?.host {
                    warnings.append("'\(host)' is an url and will be sanitized to: '\(sanitizedHost)'.")
                    return sanitizedHost
                } else {
                    warnings.append("'\(host)' is not a valid host name and will be dropped.")
                    return nil
                }
            } else if host.range(of: hostRegex, options: .regularExpression) != nil {
                // if a valid host name is given, accept it
                return host
            } else if host.range(of: ipRegex, options: .regularExpression) != nil {
                // if a valid IP address is given, accept it
                return host
            } else if host == "localhost" {
                // if "localhost" given, accept it
                return host
            } else {
                // otherwise, drop
                warnings.append("'\(host)' is not a valid host name and will be dropped.")
                return nil
            }
        }

        warnings.forEach { warning in
            consolePrint(
                    """
                    ⚠️ \(warningMessage): \(warning)
                    """
            )
        }

        return Set(array)
    }
}
