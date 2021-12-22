/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

// TODO: RUMM-1786 implement mappers
internal class WebRUMEventMapper { }

internal class WebRUMEventConsumer: WebEventConsumer {
    private let dataWriter: Writer
    private let dateCorrector: DateCorrectorType
    private let webRUMEventMapper: WebRUMEventMapper?
    private let contextProvider: RUMContextProvider?

    init(
        dataWriter: Writer,
        dateCorrector: DateCorrectorType,
        webRUMEventMapper: WebRUMEventMapper?,
        contextProvider: RUMContextProvider?
    ) {
        self.dataWriter = dataWriter
        self.dateCorrector = dateCorrector
        self.webRUMEventMapper = webRUMEventMapper
        self.contextProvider = contextProvider
    }

    func consume(event: JSON, eventType: String) throws {
        let eventData = try JSONSerialization.data(withJSONObject: event, options: [])
        let jsonDecoder = JSONDecoder()
        let rumContext = contextProvider?.context

        switch eventType {
        case "view":
            let viewEvent = try jsonDecoder.decode(RUMViewEvent.self, from: eventData)
            let mappedViewEvent = mapIfNeeded(dataModel: viewEvent, context: rumContext, offset: getOffset(viewID: viewEvent.view.id))
            write(mappedViewEvent)
        case "action":
            let actionEvent = try jsonDecoder.decode(RUMActionEvent.self, from: eventData)
            let mappedActionEvent = mapIfNeeded(dataModel: actionEvent, context: rumContext, offset: getOffset(viewID: actionEvent.view.id))
            write(mappedActionEvent)
        case "resource":
            let resourceEvent = try jsonDecoder.decode(RUMResourceEvent.self, from: eventData)
            let mappedResourceEvent = mapIfNeeded(dataModel: resourceEvent, context: rumContext, offset: getOffset(viewID: resourceEvent.view.id))
            write(mappedResourceEvent)
        case "error":
            let errorEvent = try jsonDecoder.decode(RUMErrorEvent.self, from: eventData)
            let mappedErrorEvent = mapIfNeeded(dataModel: errorEvent, context: rumContext, offset: getOffset(viewID: errorEvent.view.id))
            write(mappedErrorEvent)
        case "long_task":
            let longTaskEvent = try jsonDecoder.decode(RUMLongTaskEvent.self, from: eventData)
            let mappedLongTaskEvent = mapIfNeeded(dataModel: longTaskEvent, context: rumContext, offset: getOffset(viewID: longTaskEvent.view.id))
            write(mappedLongTaskEvent)
        default:
            userLogger.error("🔥 Web RUM Event Error - Unknown event type: \(eventType)")
        }
    }

    private func mapIfNeeded<T: RUMDataModel>(dataModel: T, context: RUMContext?, offset: Offset) -> T {
        guard let context = context else {
            return dataModel
        }
        // TODO: RUMM-1786 implement mappers
        let mappedDataModel = dataModel
        return mappedDataModel
    }

    private func write<T: RUMDataModel>(_ model: T) {
        dataWriter.write(value: model)
    }

    // MARK: - Time offsets

    private typealias Offset = TimeInterval
    private typealias ViewIDOffsetPair = (viewID: String, offset: Offset)
    private var viewIDOffsetPairs = [ViewIDOffsetPair]()

    private func getOffset(viewID: String) -> Offset {
        purgeOffsets()

        let found = viewIDOffsetPairs.first { $0.viewID == viewID }
        if let found = found {
            return found.offset
        }
        let offset = dateCorrector.currentCorrection.serverTimeOffset
        viewIDOffsetPairs.insert((viewID: viewID, offset: offset), at: 0)
        return offset
    }

    private func purgeOffsets() {
        while viewIDOffsetPairs.count > 3 {
            _ = viewIDOffsetPairs.popLast()
        }
    }
}
