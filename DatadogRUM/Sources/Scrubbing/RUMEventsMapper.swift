/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// The `EventMapper` for RUM events.
internal struct RUMEventsMapper {
    let viewEventMapper: RUM.ViewEventMapper?
    let errorEventMapper: RUM.ErrorEventMapper?
    let resourceEventMapper: RUM.ResourceEventMapper?
    let actionEventMapper: RUM.ActionEventMapper?
    let longTaskEventMapper: RUM.LongTaskEventMapper?
    /// Telemetry interface.
    let telemetry: Telemetry

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
            telemetry.error("No `RUMEventMapper` is registered for \(type(of: event))")
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
