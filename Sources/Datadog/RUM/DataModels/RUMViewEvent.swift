/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

// TODO: RUMM-517 Replace with auto-generated RUM data model
internal struct RUMViewEvent: Encodable {
    enum CodingKeys: String, CodingKey {
        case date
        case application
        case session
        case type
        case view
        case dd  = "_dd"
    }

    let date: UInt64
    let application: Application
    let session: Session
    let type = "view"
    let view: View
    let dd: DD

    struct Application: Encodable {
        let id: String
    }

    struct Session: Encodable {
        let id: String
        let type: String
    }

    struct View: Encodable {
        enum CodingKeys: String, CodingKey {
            case id
            case url
            case timeSpent = "time_spent"
            case action
            case error
            case resource
        }

        let id: String
        let url: String
        let timeSpent: UInt64
        let action: Action
        let error: Error
        let resource: Resource

        struct Action: Encodable {
            let count: UInt
        }
        struct Error: Encodable {
            let count: UInt
        }
        struct Resource: Encodable {
            let count: UInt
        }
    }

    struct DD: Encodable {
        enum CodingKeys: String, CodingKey {
            case documentVersion = "document_version"
            case formatVersion  = "format_version"
        }

        let documentVersion: UInt
        let formatVersion = 2
    }
}
