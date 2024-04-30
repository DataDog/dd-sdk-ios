/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal
import DatadogCore

struct TestInfo: Decodable {
    let mobileIntegrationOrg: OrgInfo
    let sessionReplayOrg: OrgInfo

    enum CodingKeys: String, CodingKey {
        case mobileIntegrationOrg = "MobileIntegration"
        case sessionReplayOrg = "SessionReplayIntegration"
    }
}

extension TestInfo {
    init(bundle: Bundle = .main) throws {
        let decoder = AnyDecoder()
        let obj = bundle.object(forInfoDictionaryKey: "DatadogConfiguration")
        self = try decoder.decode(from: obj)
    }
}

struct OrgInfo: Decodable {
    let clientToken: String
    let applicationID: String
    let site: DatadogSite?
    let env: String?

    enum CodingKeys: String, CodingKey {
        case clientToken = "ClientToken"
        case applicationID = "ApplicationID"
        case site = "Site"
        case env = "Environment"
    }
}

extension DatadogSite: Decodable {}

extension Datadog.Configuration {
    static func e2e(org: OrgInfo) -> Self {
        .init(
            clientToken: org.clientToken,
            env: org.env ?? "e2e",
            site: org.site ?? .us1
        )
    }
}
