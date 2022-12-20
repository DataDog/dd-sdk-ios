/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

internal class DefaultWebLogEventConsumer: WebEventConsumer {
    private struct Constants {
        static let logEventType = "log"
        static let internalLogEventType = "internal_log"

        static let applicationIDKey = "application_id"
        static let sessionIDKey = "session_id"
        static let ddTagsKey = "ddtags"
        static let dateKey = "date"
    }

    private let core: DatadogCoreProtocol
    private let dateCorrector: DateCorrector
    private let rumContextProvider: RUMContextProvider?
    private let applicationVersion: String
    private let environment: String

    private let jsonDecoder = JSONDecoder()

    private lazy var ddTags: String = {
        let versionKey = LogEventEncoder.StaticCodingKeys.applicationVersion.rawValue
        let versionValue = applicationVersion
        let envKey = LogEventEncoder.StaticCodingKeys.environment.rawValue
        let envValue = environment

        return "\(versionKey):\(versionValue),\(envKey):\(envValue)"
    }()

    init(
        core: DatadogCoreProtocol,
        dateCorrector: DateCorrector,
        rumContextProvider: RUMContextProvider?,
        applicationVersion: String,
        environment: String
    ) {
        self.core = core
        self.dateCorrector = dateCorrector
        self.rumContextProvider = rumContextProvider
        self.applicationVersion = applicationVersion
        self.environment = environment
    }

    func consume(event: JSON) throws {
        var mutableEvent = event

        if let existingTags = mutableEvent[Constants.ddTagsKey] as? String, !existingTags.isEmpty {
            mutableEvent[Constants.ddTagsKey] = "\(ddTags),\(existingTags)"
        } else {
            mutableEvent[Constants.ddTagsKey] = ddTags
        }

        if let timestampInMs = mutableEvent[Constants.dateKey] as? Int {
            let serverTimeOffsetInMs = dateCorrector.offset.toInt64Milliseconds
            let correctedTimestamp = Int64(timestampInMs) + serverTimeOffsetInMs
            mutableEvent[Constants.dateKey] = correctedTimestamp
        }

        if let context = rumContextProvider?.context {
            mutableEvent[Constants.applicationIDKey] = context.rumApplicationID
            mutableEvent[Constants.sessionIDKey] = context.sessionID.toRUMDataFormat
        }

        let jsonData = try JSONSerialization.data(withJSONObject: mutableEvent, options: [])
        let encodableEvent = try jsonDecoder.decode(AnyCodable.self, from: jsonData)

        core.send(message: .event(target: "log", event: .init(encodableEvent)), else: {
            DD.logger.warn("A WebView log is lost because Logging is disabled in the SDK")
        })
    }
}
