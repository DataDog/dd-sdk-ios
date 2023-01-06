/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

internal class RUMEventBuilder {
    let eventsMapper: RUMEventsMapper
    let sanitizer = RUMEventSanitizer()

    init(eventsMapper: RUMEventsMapper) {
        self.eventsMapper = eventsMapper
    }

    func build<Event>(from event: Event, callback: @escaping (Event?) -> Void) where Event: RUMSanitizableEvent {
        eventsMapper.map(event: event) { transformedEvent in
            guard let transformedEvent = transformedEvent else {
                return callback(nil)
            }
            callback(self.sanitizer.sanitize(event: transformedEvent))
        }
    }
}
