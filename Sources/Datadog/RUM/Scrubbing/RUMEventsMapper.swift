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

/// The `EventMapper` for RUM events.
internal class RUMEventsMapper: EventMapper {
    weak var commandSubscriber: RUMCommandSubscriber?

    let dateProvider: DateProvider
    let viewEventMapper: RUMViewEventMapper?
    let errorEventMapper: RUMErrorEventMapper?
    let resourceEventMapper: RUMResourceEventMapper?
    let actionEventMapper: RUMActionEventMapper?

    init(
        dateProvider: DateProvider,
        viewEventMapper: RUMViewEventMapper? = nil,
        errorEventMapper: RUMErrorEventMapper? = nil,
        resourceEventMapper: RUMResourceEventMapper? = nil,
        actionEventMapper: RUMActionEventMapper? = nil
    ) {
        self.dateProvider = dateProvider
        self.viewEventMapper = viewEventMapper
        self.errorEventMapper = errorEventMapper
        self.resourceEventMapper = resourceEventMapper
        self.actionEventMapper = actionEventMapper
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

    private func map<DM: RUMDataModel>(rumEvent: RUMEvent<DM>, using mapper: ((DM) -> DM?)?) -> RUMEvent<DM>? {
        let change: RUMEventsMappingCompletionCommand<DM>.Change
        defer {
            commandSubscriber?.process(
                command: RUMEventsMappingCompletionCommand(
                    time: dateProvider.currentDate(),
                    attributes: [:],
                    change: change,
                    model: rumEvent.model
                )
            )
        }

        guard let mapper = mapper else {
            change = .none
            return rumEvent // if no mapper is provided, do not modify the `rumEvent`
        }

        if let mappedModel = mapper(rumEvent.model) {
            var mutableRUMEvent = rumEvent
            mutableRUMEvent.model = mappedModel
            change = .mapped
            return mutableRUMEvent
        } else {
            change = .discarded
            return nil
        }
    }
}
