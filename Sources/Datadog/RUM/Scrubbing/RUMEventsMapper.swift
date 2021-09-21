/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

internal typealias RUMViewEventMapper = (RUMViewEvent) -> RUMViewEvent
internal typealias RUMErrorEventMapper = (RUMErrorEvent) -> RUMErrorEvent?
internal typealias RUMResourceEventMapper = (RUMResourceEvent) -> RUMResourceEvent?
internal typealias RUMActionEventMapper = (RUMActionEvent) -> RUMActionEvent?
internal typealias RUMLongTaskEventMapper = (RUMLongTaskEvent) -> RUMLongTaskEvent?

/// The `EventMapper` for RUM events.
internal struct RUMEventsMapper {
    let viewEventMapper: RUMViewEventMapper?
    let errorEventMapper: RUMErrorEventMapper?
    let resourceEventMapper: RUMResourceEventMapper?
    let actionEventMapper: RUMActionEventMapper?
    let longTaskEventMapper: RUMLongTaskEventMapper?
    var internalMonitor: InternalMonitor? = nil

    // MARK: - EventMapper

    /// Data scrubbing interface.
    /// It takes an `event` and returns its modified representation or `nil` (for dropping the event).
    func map<T>(event: T) -> T? {
        switch event {
        case let viewEvent as RUMEvent<RUMViewEvent>:
            return map(rumEvent: viewEvent, using: viewEventMapper) as? T
        case let errorEvent as RUMEvent<RUMErrorEvent>:
            return map(rumEvent: errorEvent, using: errorEventMapper) as? T
        case let resourceEvent as RUMEvent<RUMResourceEvent>:
            return map(rumEvent: resourceEvent, using: resourceEventMapper) as? T
        case let actionEvent as RUMEvent<RUMActionEvent>:
            return map(rumEvent: actionEvent, using: actionEventMapper) as? T
        case let longTaskEvent as RUMEvent<RUMLongTaskEvent>:
            return map(rumEvent: longTaskEvent, using: longTaskEventMapper) as? T
        default:
            internalMonitor?.sdkLogger.critical("No `RUMEventMapper` is registered for \(type(of: event))")
            return event
        }
    }

    // MARK: - Private

    private func map<DM: RUMDataModel>(rumEvent: RUMEvent<DM>, using mapper: ((DM) -> DM?)?) -> RUMEvent<DM>? {
        guard let mapper = mapper else {
            return rumEvent // if no mapper is provided, do not modify the `rumEvent`
        }

        if let mappedModel = mapper(rumEvent.model) {
            var mutableRUMEvent = rumEvent
            mutableRUMEvent.model = mappedModel
            return mutableRUMEvent
        } else {
            return nil
        }
    }
}
