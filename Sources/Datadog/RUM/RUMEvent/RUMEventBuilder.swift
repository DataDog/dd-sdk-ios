/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

internal class RUMEventBuilder {
    let eventsMapper: RUMEventsMapper

    init(eventsMapper: RUMEventsMapper) {
        self.eventsMapper = eventsMapper
    }

    func createRUMEvent<DM: RUMDataModel>(
        with model: DM,
        attributes: [String: Encodable]
    ) -> RUMEvent<DM>? {
        var model = model

        if !attributes.isEmpty {
            model.context = RUMEventAttributes(contextInfo: attributes)
        }

        let event = RUMEvent(model: model)
        let mappedEvent = eventsMapper.map(event: event)
        return mappedEvent
    }
}
