/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal struct FlagsEndpointBuilder {
    /// Builds the complete endpoint URL for precompute-assignments API
    /// - Parameters:
    ///   - site: The Datadog site enum value
    ///   - customerDomain: Optional customer-specific domain prefix
    /// - Returns: Complete URL string for the flags endpoint
    /// - Throws: FlagsError.unsupportedSite if site is not supported for feature flags
    static func buildEndpointURL(site: DatadogSite, customerDomain: String? = nil) throws -> String {
        let host = try buildEndpointHost(site: site, customerDomain: customerDomain)
        return "https://\(host)/precompute-assignments"
    }

    /// Builds the endpoint host for flags API based on site configuration
    /// - Parameters:
    ///   - site: The Datadog site enum value
    ///   - customerDomain: Optional customer-specific domain prefix
    /// - Returns: Host string for the flags endpoint
    /// - Throws: FlagsError.unsupportedSite if site is not supported for feature flags
    static func buildEndpointHost(site: DatadogSite, customerDomain: String? = nil) throws -> String {
        // Map DatadogSite enum to flags-specific CDN endpoints (exhaustive switch)
        let baseHost: String
        switch site {
        case .us1:
            baseHost = "ff-cdn.datadoghq.com"
        case .us3:
            baseHost = "ff-cdn.us3.datadoghq.com"
        case .us5:
            baseHost = "ff-cdn.us5.datadoghq.com"
        case .eu1:
            baseHost = "ff-cdn.datadoghq.eu"
        case .ap1:
            baseHost = "ff-cdn.ap1.datadoghq.com"
        case .ap2:
            baseHost = "ff-cdn.ap2.datadoghq.com"
        case .us1_fed:
            // Government sites are not supported for feature flags
            throw FlagsError.unsupportedSite(site.rawValue)
        }

        // If customer domain is provided, prepend it to the base host
        if let customerDomain = customerDomain, !customerDomain.isEmpty {
            return "\(customerDomain).\(baseHost)"
        }

        return baseHost
    }

    /// Extracts customer domain from a client token
    /// - Parameter clientToken: The Datadog client token
    /// - Returns: Customer domain if extractable, nil otherwise
    static func extractCustomerDomain(from clientToken: String) -> String? {
        // This is a simplified implementation - in a real scenario,
        // the client token format would be documented and parsed accordingly
        // For now, return nil to use default endpoints
        return nil
    }
}
