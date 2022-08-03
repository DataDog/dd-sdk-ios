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

    // MARK: - EventMapper

    /// Data scrubbing interface.
    /// It takes an `event` and returns its modified representation or `nil` (for dropping the event).
    func map<T>(event: T) -> T? {
        switch event {
        case let event as RUMViewEvent:
            return map(event: event, using: viewEventMapper) as? T
        case let event as RUMErrorEvent:
            return map(event: event, using: errorEventMapper) as? T
        case let event as RUMCrashEvent:
            guard let model = map(event: event.model, using: errorEventMapper) else {
                return nil
            }
            return RUMCrashEvent(error: model, additionalAttributes: event.additionalAttributes) as? T
        case let event as RUMResourceEvent:
            return map(event: event, using: resourceEventMapper) as? T
        case let event as RUMActionEvent:
            return map(event: event, using: actionEventMapper) as? T
        case let event as RUMLongTaskEvent:
            return map(event: event, using: longTaskEventMapper) as? T
        default:
            DD.telemetry.error("No `RUMEventMapper` is registered for \(type(of: event))")
            return event
        }
    }

    // MARK: - Private

    private func map<Event>(event: Event, using mapper: ((Event) -> Event?)?) -> Event? {
        guard let mapper = mapper else {
            return event // if no mapper is provided, do not modify the `rumEvent`
        }

        return mapper(event)
    }
}
