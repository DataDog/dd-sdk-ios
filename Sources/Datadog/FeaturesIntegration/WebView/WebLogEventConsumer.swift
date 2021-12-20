/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

internal class WebLogEventConsumer: WebEventConsumer {
    private struct Constants {
        static let logEventType = "log"
        static let internalLogEventType = "internal_log"

        static let applicationIDKey = "application_id"
        static let sessionIDKey = "session_id"
        static let ddTagsKey = "ddtags"
        static let dateKey = "date"
    }

    private let userLogsWriter: Writer
    private let internalLogsWriter: Writer?
    private let dateCorrector: DateCorrectorType
    private let rumContextProvider: RUMContextProvider?
    private let jsonDecoder = JSONDecoder()

    private lazy var ddTags: String = {
        let versionKey = LogEventEncoder.StaticCodingKeys.applicationVersion.rawValue
        let versionValue = LoggingFeature.instance?.configuration.common.applicationVersion ?? ""
        let envKey = LogEventEncoder.StaticCodingKeys.environment.rawValue
        let envValue = LoggingFeature.instance?.configuration.common.environment ?? ""

        return "\(versionKey):\(versionValue),\(envKey):\(envValue)"
    }()

    init(
        userLogsWriter: Writer,
        internalLogsWriter: Writer?,
        dateCorrector: DateCorrectorType,
        rumContextProvider: RUMContextProvider?
    ) {
        self.userLogsWriter = userLogsWriter
        self.internalLogsWriter = internalLogsWriter
        self.dateCorrector = dateCorrector
        self.rumContextProvider = rumContextProvider
    }

    func consume(event: JSON, eventType: String) throws {
        var mutableEvent = event

        if let existingTags = mutableEvent[Constants.ddTagsKey] as? String, !existingTags.isEmpty {
            mutableEvent[Constants.ddTagsKey] = "\(ddTags),\(existingTags)"
        } else {
            mutableEvent[Constants.ddTagsKey] = ddTags
        }

        if let date = mutableEvent[Constants.dateKey] as? Int {
            let serverTimeOffsetInNs = dateCorrector.currentCorrection.serverTimeOffset.toInt64Nanoseconds
            let correctedDate = Int64(date) + serverTimeOffsetInNs
            mutableEvent[Constants.dateKey] = correctedDate
        }

        if let context = rumContextProvider?.context {
            mutableEvent[Constants.applicationIDKey] = context.rumApplicationID
            mutableEvent[Constants.sessionIDKey] = context.sessionID.toRUMDataFormat
        }

        let jsonData = try JSONSerialization.data(withJSONObject: mutableEvent, options: [])
        let encodableEvent = try jsonDecoder.decode(CodableValue.self, from: jsonData)

        if eventType == Constants.logEventType {
            userLogsWriter.write(value: encodableEvent)
        } else if eventType == Constants.internalLogEventType {
            internalLogsWriter?.write(value: encodableEvent)
        }
    }
}
