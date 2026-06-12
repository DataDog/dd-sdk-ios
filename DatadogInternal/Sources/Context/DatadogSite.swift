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
    /// The intake hostname for this site (e.g. `browser-intake-datadoghq.com`).
    public var host: String {
        switch self {
        case .us1: return "browser-intake-datadoghq.com"
        case .us3: return "browser-intake-us3-datadoghq.com"
        case .us5: return "browser-intake-us5-datadoghq.com"
        case .eu1: return "browser-intake-datadoghq.eu"
        case .ap1: return "browser-intake-ap1-datadoghq.com"
        case .ap2: return "browser-intake-ap2-datadoghq.com"
        case .us1_fed: return "browser-intake-ddog-gov.com"
        case .us2_fed: return "browser-intake-us2-ddog-gov.com"
        }
    }

    public var endpoint: URL {
        // swiftlint:disable:next force_unwrapping
        URL(string: "https://\(host)/")!
    }

    /// The base CDN URL for fetching remote configuration documents.
    /// The full URL (with API version path and ID) is constructed by DatadogCore.
    public var remoteConfigurationEndpoint: URL {
        // swiftlint:disable:next force_unwrapping
        URL(string: "https://sdk-configuration.\(host)/")!
    }
}
