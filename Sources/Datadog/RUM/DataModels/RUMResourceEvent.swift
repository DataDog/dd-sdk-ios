/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

// TODO: RUMM-517 Replace with auto-generated RUM data model
internal struct RUMResourceEvent: Codable, RUMDataModel {
    enum CodingKeys: String, CodingKey {
        case date
        case application
        case session
        case type
        case view
        case resource
        case action
        case dd  = "_dd"
    }

    let date: UInt64
    let application: Application
    let session: Session
    let type = "resource"
    let view: View
    let resource: Resource
    let action: Action?
    let dd: DD

    struct Application: Codable {
        let id: String
    }

    struct Session: Codable {
        let id: String
        let type: String
    }

    struct View: Codable {
        enum CodingKeys: String, CodingKey {
            case id
            case url
        }

        let id: String
        let url: String
    }

    struct Resource: Codable {
        enum CodingKeys: String, CodingKey {
            case type
            case url
            case method
            case statusCode = "status_code"
            case duration
            case size
        }

        let type: String
        let url: String
        let method: String?
        let statusCode: Int?
        let duration: UInt64
        let size: UInt64?
    }

    struct Action: Codable {
        let id: String
    }

    struct DD: Codable {
        enum CodingKeys: String, CodingKey {
            case formatVersion  = "format_version"
        }

        let formatVersion = 2
    }
}
