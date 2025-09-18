/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

internal struct FlagsEndpointBuilder {
    /// Builds the complete endpoint URL for precompute-assignments API
    /// - Parameters:
    ///   - site: The Datadog site (e.g., "datadoghq.com", "datadoghq.eu")
    ///   - customerDomain: Optional customer-specific domain prefix
    /// - Returns: Complete URL string for the flags endpoint
    /// - Throws: FlagsError.invalidConfiguration if site is unsupported
    static func buildEndpointURL(site: String, customerDomain: String? = nil) throws -> String {
        let host = try buildEndpointHost(site: site, customerDomain: customerDomain)
        return "https://\(host)/precompute-assignments"
    }

    /// Builds the endpoint host for flags API based on site configuration
    /// - Parameters:
    ///   - site: The Datadog site (e.g., "datadoghq.com", "datadoghq.eu")
    ///   - customerDomain: Optional customer-specific domain prefix
    /// - Returns: Host string for the flags endpoint
    /// - Throws: FlagsError.invalidConfiguration if site is unsupported
    static func buildEndpointHost(site: String, customerDomain: String? = nil) throws -> String {
        let normalizedSite = site.lowercased()

        // Handle unsupported government site
        if normalizedSite == "ddog-gov.com" {
            throw FlagsError.unsupportedSite(normalizedSite)
        }

        // Map sites to their flag endpoint patterns
        let siteMapping: [String: String] = [
            "datadoghq.com": "ff-cdn.datadoghq.com",
            "datadoghq.eu": "ff-cdn.datadoghq.eu",
            "us3.datadoghq.com": "ff-cdn.us3.datadoghq.com",
            "us5.datadoghq.com": "ff-cdn.us5.datadoghq.com",
            "ap1.datadoghq.com": "ff-cdn.ap1.datadoghq.com",
            "ap2.datadoghq.com": "ff-cdn.ap2.datadoghq.com",
            "datad0g.com": "ff-cdn.datad0g.com" // Staging environment
        ]

        guard let baseHost = siteMapping[normalizedSite] else {
            throw FlagsError.unsupportedSite(normalizedSite)
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
