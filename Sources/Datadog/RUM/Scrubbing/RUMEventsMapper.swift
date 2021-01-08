/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

internal typealias RUMViewEventMapper = (RUMViewEvent) -> RUMViewEvent?
internal typealias RUMErrorEventMapper = (RUMErrorEvent) -> RUMErrorEvent?
internal typealias RUMResourceEventMapper = (RUMResourceEvent) -> RUMResourceEvent?
internal typealias RUMActionEventMapper = (RUMActionEvent) -> RUMActionEvent?

/// The `EventMapper` for RUM events.
internal struct RUMEventsMapper: EventMapper {
    private let viewEventMapper: RUMViewEventMapper
    private let errorEventMapper: RUMErrorEventMapper
    private let resourceEventMapper: RUMResourceEventMapper
    private let actionEventMapper: RUMActionEventMapper

    init(
        viewEventMapper: RUMViewEventMapper?,
        errorEventMapper: RUMErrorEventMapper?,
        resourceEventMapper: RUMResourceEventMapper?,
        actionEventMapper: RUMActionEventMapper?
    ) {
        self.viewEventMapper = viewEventMapper ?? RUMEventsMapper.noOpMapper(_:)
        self.errorEventMapper = errorEventMapper ?? RUMEventsMapper.noOpMapper(_:)
        self.resourceEventMapper = resourceEventMapper ?? RUMEventsMapper.noOpMapper(_:)
        self.actionEventMapper = actionEventMapper ?? RUMEventsMapper.noOpMapper(_:)
    }

    // MARK: - EventMapper

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
        default:
            developerLogger?.warn("No `RUMEventsMapper` is registered for \(type(of: event))")
            return event
        }
    }

    private func map<DM: RUMDataModel>(rumEvent: RUMEvent<DM>, using mapper: (DM) -> DM?) -> RUMEvent<DM>? {
        if let mappedModel = mapper(rumEvent.model) {
            var mutableRUMEvent = rumEvent
            mutableRUMEvent.model = mappedModel
            return mutableRUMEvent
        } else {
            return nil
        }
    }

    // MARK: - Private

    /// Generic mapping function which returns the `event` with no change.
    private static func noOpMapper<T: Encodable>(_ event: T) -> T { event }
}
