/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

internal class DefaultWebRUMEventConsumer: WebRUMEventConsumer {
    private let dataWriter: Writer
    private let dateCorrector: DateCorrector
    private let contextProvider: RUMContextProvider?
    private let rumCommandSubscriber: RUMCommandSubscriber?
    private let dateProvider: DateProvider

    private let jsonDecoder = JSONDecoder()

    init(
        dataWriter: Writer,
        dateCorrector: DateCorrector,
        contextProvider: RUMContextProvider?,
        rumCommandSubscriber: RUMCommandSubscriber?,
        dateProvider: DateProvider
    ) {
        self.dataWriter = dataWriter
        self.dateCorrector = dateCorrector
        self.contextProvider = contextProvider
        self.rumCommandSubscriber = rumCommandSubscriber
        self.dateProvider = dateProvider
    }

    func consume(event: JSON) throws {
        rumCommandSubscriber?.process(
            command: RUMKeepSessionAliveCommand(
                time: dateProvider.now,
                attributes: [:]
            )
        )
        let rumContext = contextProvider?.context
        let mappedEvent = map(event: event, with: rumContext)

        let jsonData = try JSONSerialization.data(withJSONObject: mappedEvent, options: [])
        let encodableEvent = try jsonDecoder.decode(CodableValue.self, from: jsonData)

        dataWriter.write(value: encodableEvent)
    }

    private func map(event: JSON, with context: RUMContext?) -> JSON {
        guard let context = context,
              context.sessionID != .nullUUID else {
            return event
        }

        var mutableEvent = event

        if let date = mutableEvent["date"] as? Int {
            let viewID = (mutableEvent["view"] as? JSON)?["id"] as? String
            let serverTimeOffsetInMs = getOffsetInMs(viewID: viewID)
            let correctedDate = Int64(date) + serverTimeOffsetInMs
            mutableEvent["date"] = correctedDate
        }

        if let context = contextProvider?.context {
            if var application = mutableEvent["application"] as? JSON {
                application["id"] = context.rumApplicationID
                mutableEvent["application"] = application
            }
            if var session = mutableEvent["session"] as? JSON {
                session["id"] = context.sessionID.toRUMDataFormat
                mutableEvent["session"] = session
            }
        }

        if var dd = mutableEvent["_dd"] as? JSON,
           var dd_sesion = dd["session"] as? [String: Int] {
            dd_sesion["plan"] = 1
            dd["session"] = dd_sesion
            mutableEvent["_dd"] = dd
        }

        return mutableEvent
    }

    // MARK: - Time offsets

    private typealias Offset = Int64
    private typealias ViewIDOffsetPair = (viewID: String, offset: Offset)
    private var viewIDOffsetPairs = [ViewIDOffsetPair]()

    private func getOffsetInMs(viewID: String?) -> Offset {
        guard let viewID = viewID else {
            return 0
        }

        purgeOffsets()
        let found = viewIDOffsetPairs.first { $0.viewID == viewID }
        if let found = found {
            return found.offset
        }
        let offset = dateCorrector.offset.toInt64Milliseconds
        viewIDOffsetPairs.insert((viewID: viewID, offset: offset), at: 0)
        return offset
    }

    private func purgeOffsets() {
        while viewIDOffsetPairs.count > 3 {
            _ = viewIDOffsetPairs.popLast()
        }
    }
}
