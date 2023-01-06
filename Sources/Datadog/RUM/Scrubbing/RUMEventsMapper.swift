/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// A protocol to asynchronously modify `RUMViewEvent`s before they are sent to Datadog.
///
/// This protocol is part of the internal interface for Datadog and not meant for public use.
public protocol RUMViewEventMapper {
    func map(event: RUMViewEvent, callback: @escaping (RUMViewEvent) -> Void)
}

internal class SyncRUMViewEventMapper: RUMViewEventMapper {
    let mapper: (RUMViewEvent) -> RUMViewEvent

    init(_ mapper: @escaping (RUMViewEvent) -> RUMViewEvent) {
        self.mapper = mapper
    }

    func map(event: RUMViewEvent, callback: @escaping (RUMViewEvent) -> Void) {
        callback(mapper(event))
    }
}

/// A protocol to asynchronously modify `RUMErrorEvent`s before they are sent to Datadog.
///
/// This protocol is part of the internal interface for Datadog and not meant for public use.
public protocol RUMErrorEventMapper {
    func map(event: RUMErrorEvent, callback: @escaping (RUMErrorEvent?) -> Void)
}

internal class SyncRUMErrorEventMapper: RUMErrorEventMapper {
    let mapper: (RUMErrorEvent) -> RUMErrorEvent?

    init(_ mapper: @escaping (RUMErrorEvent) -> RUMErrorEvent?) {
        self.mapper = mapper
    }

    func map(event: RUMErrorEvent, callback: @escaping (RUMErrorEvent?) -> Void) {
        callback(mapper(event))
    }
}

/// A protocol to asynchronously modify `RUMResourceEvent`s before they are sent to Datadog.
///
/// This protocol is part of the internal interface for Datadog and not meant for public use.
public protocol RUMResourceEventMapper {
    func map(event: RUMResourceEvent, callback: @escaping (RUMResourceEvent?) -> Void)
}

internal class SyncRUMResourceEventMapper: RUMResourceEventMapper {
    let mapper: (RUMResourceEvent) -> RUMResourceEvent?

    init(_ mapper: @escaping (RUMResourceEvent) -> RUMResourceEvent?) {
        self.mapper = mapper
    }

    func map(event: RUMResourceEvent, callback: @escaping (RUMResourceEvent?) -> Void) {
        callback(mapper(event))
    }
}

/// A protocol to asynchronously modify `RUMActionEvent`s before they are sent to Datadog.
///
/// This protocol is part of the internal interface for Datadog and not meant for public use.
public protocol RUMActionEventMapper {
    func map(event: RUMActionEvent, callback: @escaping (RUMActionEvent?) -> Void)
}

class SyncRUMActionEventMapper: RUMActionEventMapper {
    let mapper: (RUMActionEvent) -> RUMActionEvent?

    init(_ mapper: @escaping (RUMActionEvent) -> RUMActionEvent?) {
        self.mapper = mapper
    }

    func map(event: RUMActionEvent, callback: @escaping (RUMActionEvent?) -> Void) {
        callback(mapper(event))
    }
}

/// A protocol to asynchronously modify `RUMLongTaskEvent`s before they are sent to Datadog.
///
/// This protocol is part of the internal interface for Datadog and not meant for public use.
public protocol RUMLongTaskEventMapper {
    func map(event: RUMLongTaskEvent, callback: @escaping (RUMLongTaskEvent?) -> Void)
}

internal class SyncRUMLongTaskEventMapper: RUMLongTaskEventMapper {
    let mapper: (RUMLongTaskEvent) -> RUMLongTaskEvent?

    init(_ mapper: @escaping (RUMLongTaskEvent) -> RUMLongTaskEvent?) {
        self.mapper = mapper
    }

    func map(event: RUMLongTaskEvent, callback: @escaping (RUMLongTaskEvent?) -> Void) {
        callback(mapper(event))
    }
}

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
    func map<T>(event: T, callback: @escaping (T?) -> Void) {
        switch event {
        case let viewEvent as RUMViewEvent:
            guard let mapper = viewEventMapper else {
                return callback(event)
            }
            guard let callback = callback as? (RUMViewEvent?) -> Void else {
                DD.telemetry.error("Callback for `RUMViewEventMapper` is of wrong type: \(type(of: callback))")
                return callback(event)
            }
            mapper.map(event: viewEvent, callback: callback)
        case let errorEvent as RUMErrorEvent:
            guard let mapper = errorEventMapper else {
                return callback(event)
            }
            guard let callback = callback as? (RUMErrorEvent?) -> Void else {
                DD.telemetry.error("Callback for `RUMErrorEventMapper` is of wrong type: \(type(of: callback))")
                return callback(event)
            }
            mapper.map(event: errorEvent, callback: callback)
        case let crashEvent as RUMCrashEvent:
            guard let mapper = errorEventMapper else {
                return callback(event)
            }
            guard let callback = callback as? (RUMCrashEvent?) -> Void else {
                DD.telemetry.error("Callback for Crash mapper is of wrong type: \(type(of: callback))")
                return callback(event)
            }
            mapper.map(event: crashEvent.model) { model in
                guard let model = model else {
                    return callback(nil)
                }
                callback(RUMCrashEvent(error: model, additionalAttributes: crashEvent.additionalAttributes))
            }
        case let resourceEvent as RUMResourceEvent:
            guard let mapper = resourceEventMapper else {
                return callback(event)
            }
            guard let callback = callback as? (RUMResourceEvent?) -> Void else {
                DD.telemetry.error("Callback for `RUMResourceEventMapper` is of wrong type: \(type(of: callback))")
                return callback(event)
            }
            mapper.map(event: resourceEvent, callback: callback)
        case let actionEvent as RUMActionEvent:
            guard let mapper = actionEventMapper else {
                return callback(event)
            }
            guard let callback = callback as? (RUMActionEvent?) -> Void else {
                DD.telemetry.error("Callback for `RUMActionEventMapper` is of wrong type: \(type(of: callback))")
                return callback(event)
            }
            mapper.map(event: actionEvent, callback: callback)
        case let longTaskEvent as RUMLongTaskEvent:
            guard let mapper = longTaskEventMapper else {
                return callback(event)
            }
            guard let callback = callback as? (RUMLongTaskEvent?) -> Void else {
                DD.telemetry.error("Callback for `RUMLongTaskEventMapper` is of wrong type: \(type(of: callback))")
                return callback(event)
            }
            mapper.map(event: longTaskEvent, callback: callback)
        default:
            DD.telemetry.error("No `RUMEventMapper` is registered for \(type(of: event))")
            return callback(event)
        }
    }
}
