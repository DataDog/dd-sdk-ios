/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

internal class WebRUMEventConsumer: WebEventConsumer {
    private let dataWriter: Writer
    private let dateCorrector: DateCorrectorType
    private let contextProvider: RUMContextProvider?

    init(
        dataWriter: Writer,
        dateCorrector: DateCorrectorType,
        contextProvider: RUMContextProvider?
    ) {
        self.dataWriter = dataWriter
        self.dateCorrector = dateCorrector
        self.contextProvider = contextProvider
    }

    func consume(event: JSON, eventType: String) throws {
        let eventData = try JSONSerialization.data(withJSONObject: event, options: [])
        let jsonDecoder = JSONDecoder()
        let rumContext = contextProvider?.context

        switch eventType {
        case "view":
            let viewEvent = try jsonDecoder.decode(RUMViewEvent.self, from: eventData)
            let mappedViewEvent = mapIfNeeded_RUMViewEvent(dataModel: viewEvent, context: rumContext, offset: getOffset(viewID: viewEvent.view.id))
            write(mappedViewEvent)
        case "action":
            let actionEvent = try jsonDecoder.decode(RUMActionEvent.self, from: eventData)
            let mappedActionEvent = mapIfNeeded_RUMActionEvent(dataModel: actionEvent, context: rumContext, offset: getOffset(viewID: actionEvent.view.id))
            write(mappedActionEvent)
        case "resource":
            let resourceEvent = try jsonDecoder.decode(RUMResourceEvent.self, from: eventData)
            let mappedResourceEvent = mapIfNeeded_RUMResourceEvent(dataModel: resourceEvent, context: rumContext, offset: getOffset(viewID: resourceEvent.view.id))
            write(mappedResourceEvent)
        case "error":
            let errorEvent = try jsonDecoder.decode(RUMErrorEvent.self, from: eventData)
            let mappedErrorEvent = mapIfNeeded_RUMErrorEvent(dataModel: errorEvent, context: rumContext, offset: getOffset(viewID: errorEvent.view.id))
            write(mappedErrorEvent)
        case "long_task":
            let longTaskEvent = try jsonDecoder.decode(RUMLongTaskEvent.self, from: eventData)
            let mappedLongTaskEvent = mapIfNeeded_RUMLongTaskEvent(dataModel: longTaskEvent, context: rumContext, offset: getOffset(viewID: longTaskEvent.view.id))
            write(mappedLongTaskEvent)
        default:
            userLogger.error("🔥 Web RUM Event Error - Unknown event type: \(eventType)")
        }
    }

    private func mapIfNeeded_RUMViewEvent(dataModel: RUMViewEvent, context: RUMContext?, offset: Offset) -> RUMViewEvent {
        guard let context = context,
              context.sessionID != .nullUUID else {
            return dataModel
        }
        var mappedDataModel = dataModel
        mappedDataModel.application.id = context.rumApplicationID
        mappedDataModel.session.id = context.sessionID.toRUMDataFormat
        mappedDataModel.date = mappedDataModel.date + getOffset(viewID: mappedDataModel.view.id)
        mappedDataModel.dd.session?.plan = .plan1
        return mappedDataModel
    }

    private func mapIfNeeded_RUMActionEvent(dataModel: RUMActionEvent, context: RUMContext?, offset: Offset) -> RUMActionEvent {
        guard let context = context,
              context.sessionID != .nullUUID else {
            return dataModel
        }
        var mappedDataModel = dataModel
        mappedDataModel.application.id = context.rumApplicationID
        mappedDataModel.session.id = context.sessionID.toRUMDataFormat
        mappedDataModel.date = mappedDataModel.date + getOffset(viewID: mappedDataModel.view.id)
        mappedDataModel.dd.session?.plan = .plan1
        return mappedDataModel
    }

    private func mapIfNeeded_RUMResourceEvent(dataModel: RUMResourceEvent, context: RUMContext?, offset: Offset) -> RUMResourceEvent {
        guard let context = context,
              context.sessionID != .nullUUID else {
            return dataModel
        }
        var mappedDataModel = dataModel
        mappedDataModel.application.id = context.rumApplicationID
        mappedDataModel.session.id = context.sessionID.toRUMDataFormat
        mappedDataModel.date = mappedDataModel.date + getOffset(viewID: mappedDataModel.view.id)
        mappedDataModel.dd.session?.plan = .plan1
        return mappedDataModel
    }

    private func mapIfNeeded_RUMErrorEvent(dataModel: RUMErrorEvent, context: RUMContext?, offset: Offset) -> RUMErrorEvent {
        guard let context = context,
              context.sessionID != .nullUUID else {
            return dataModel
        }
        var mappedDataModel = dataModel
        mappedDataModel.application.id = context.rumApplicationID
        mappedDataModel.session.id = context.sessionID.toRUMDataFormat
        mappedDataModel.date = mappedDataModel.date + getOffset(viewID: mappedDataModel.view.id)
        mappedDataModel.dd.session?.plan = .plan1
        return mappedDataModel
    }

    private func mapIfNeeded_RUMLongTaskEvent(dataModel: RUMLongTaskEvent, context: RUMContext?, offset: Offset) -> RUMLongTaskEvent {
        guard let context = context,
              context.sessionID != .nullUUID else {
            return dataModel
        }
        var mappedDataModel = dataModel
        mappedDataModel.application.id = context.rumApplicationID
        mappedDataModel.session.id = context.sessionID.toRUMDataFormat
        mappedDataModel.date = mappedDataModel.date + getOffset(viewID: mappedDataModel.view.id)
        mappedDataModel.dd.session?.plan = .plan1
        return mappedDataModel
    }

    private func write<T: RUMDataModel>(_ model: T) {
        dataWriter.write(value: model)
    }

    // MARK: - Time offsets

    private typealias Offset = Int64
    private typealias ViewIDOffsetPair = (viewID: String, offset: Offset)
    private var viewIDOffsetPairs = [ViewIDOffsetPair]()

    private func getOffset(viewID: String) -> Offset {
        purgeOffsets()

        let found = viewIDOffsetPairs.first { $0.viewID == viewID }
        if let found = found {
            return found.offset
        }
        let offset = dateCorrector.currentCorrection.serverTimeOffset.toInt64Nanoseconds
        viewIDOffsetPairs.insert((viewID: viewID, offset: offset), at: 0)
        return offset
    }

    private func purgeOffsets() {
        while viewIDOffsetPairs.count > 3 {
            _ = viewIDOffsetPairs.popLast()
        }
    }
}
