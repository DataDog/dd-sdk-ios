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

    func createRUMEvent<DM: RUMDataModel>(with model: DM) -> RUMEvent<DM>? {
        let event = RUMEvent(model: model)
        return eventsMapper.map(event: event)
    }
}
