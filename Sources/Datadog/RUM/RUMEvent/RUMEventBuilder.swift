/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

internal class RUMEventBuilder {
    let userInfoProvider: UserInfoProvider
    let eventsMapper: RUMEventsMapper

    init(
        userInfoProvider: UserInfoProvider,
        eventsMapper: RUMEventsMapper
    ) {
        self.userInfoProvider = userInfoProvider
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

        if !userInfoProvider.value.extraInfo.isEmpty {
            model.usr = RUMUser(email: model.usr?.email, id: model.usr?.id, name: model.usr?.name, usrInfo: userInfoProvider.value.extraInfo)
        }

        let event = RUMEvent(model: model)
        let mappedEvent = eventsMapper.map(event: event)
        return mappedEvent
    }
}
