/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

// TODO: RUMM-517 Replace with auto-generated RUM data model
internal struct RUMErrorEvent: Codable, RUMDataModel {
    let date: UInt64
    let application: Application
    let session: Session
    let type = "error"
    let view: View
    let error: Error
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

    struct Error: Codable {
        let message: String
        let source: String
        let resource: Resource?

        struct Resource: Codable {
            enum CodingKeys: String, CodingKey {
                case method
                case statusCode = "status_coded"
                case url
            }

            let method: String
            let statusCode: Int
            let url: String
        }
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
