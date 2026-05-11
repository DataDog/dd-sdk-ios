/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

public enum DatadogSite: String {
    /// US based servers.
    /// Sends data to [app.datadoghq.com](https://app.datadoghq.com/).
    case us1
    /// US based servers.
    /// Sends data to [app.datadoghq.com](https://us3.datadoghq.com/).
    case us3
    /// US based servers.
    /// Sends data to [app.datadoghq.com](https://us5.datadoghq.com/).
    case us5
    /// Europe based servers.
    /// Sends data to [app.datadoghq.eu](https://app.datadoghq.eu/).
    case eu1
    /// Asia based servers.
    /// Sends data to [ap1.datadoghq.com](https://ap1.datadoghq.com/).
    case ap1
    /// Asia based servers.
    /// Sends data to [ap2.datadoghq.com](https://ap2.datadoghq.com/).
    case ap2
    /// US based servers, FedRAMP compatible.
    /// Sends data to [app.ddog-gov.com](https://app.ddog-gov.com/).
    case us1_fed
    /// US based servers, FedRAMP compatible.
    /// Sends data to [us2.ddog-gov.com](https://us2.ddog-gov.com/).
    case us2_fed
}

extension DatadogSite {
    public var endpoint: URL {
        switch self {
        // swiftlint:disable force_unwrapping
        case .us1: return URL(string: "https://browser-intake-datadoghq.com/")!
        case .us3: return URL(string: "https://browser-intake-us3-datadoghq.com/")!
        case .us5: return URL(string: "https://browser-intake-us5-datadoghq.com/")!
        case .eu1: return URL(string: "https://browser-intake-datadoghq.eu/")!
        case .ap1: return URL(string: "https://browser-intake-ap1-datadoghq.com/")!
        case .ap2: return URL(string: "https://browser-intake-ap2-datadoghq.com/")!
        case .us1_fed: return URL(string: "https://browser-intake-ddog-gov.com/")!
        case .us2_fed: return URL(string: "https://browser-intake-us2-ddog-gov.com/")!
        // swiftlint:enable force_unwrapping
        }
    }

    /// Constructs the CDN URL for fetching the remote configuration document.
    /// - Parameter id: The value of `Datadog.Configuration.remoteConfigurationID`.
    /// - Returns: URL to GET the config JSON from, or `nil` if `id` cannot be percent-encoded.
    public func remoteConfigurationURL(for id: String) -> URL? {
        // Format: https://sdk-configuration.browser-intake-{site}/v1/{id}.json
        // `.urlPathAllowed` leaves `/` unencoded (it is legal in a path).
        // Subtract it so a slash in the ID doesn't produce extra path segments.
        let pathSegmentAllowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))
        guard let encoded = id.addingPercentEncoding(withAllowedCharacters: pathSegmentAllowed) else {
            return nil
        }
        // swiftlint:disable:next force_unwrapping
        return URL(string: "https://sdk-configuration.\(endpoint.host!)/v1/\(encoded).json")
    }
}
