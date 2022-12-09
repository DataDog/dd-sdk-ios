/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import Datadog

internal struct RUMConstants {
    static let customAttribute_String = "custom_attribute.string"
    static let customAttribute_Int = "custom_attribute.int"

    static let actionInactivityThreshold = 0.1
    static let writeDelay = 0.1

    static let timingName = "custom timing"
}

internal extension RUMMonitor {
    func sendRandomRUMEvent() {
        let viewKey = String.mockRandom()
        let viewName = String.mockRandom()

        // swiftlint:disable opening_brace
        let RUMEvents: [() -> Void] = [
            {
                self.startView(key: viewKey, name: viewName, attributes: [:])
                self.stopView(key: viewKey, attributes: [:])
            },
            {
                let resourceKey = String.mockRandom()
                self.startView(key: viewKey, name: viewName, attributes: [:])
                self.startResourceLoading(resourceKey: resourceKey, httpMethod: .get, urlString: String.mockRandom(), attributes: [:])
                self.stopResourceLoading(resourceKey: resourceKey, statusCode: (200...500).randomElement()!, kind: .other)
                self.stopView(key: viewKey, attributes: [:])
            },
            {
                self.startView(key: viewKey, name: viewName, attributes: [:])
                self.addError(message: String.mockRandom(), source: .custom, stack: String.mockRandom(), attributes: [:], file: nil, line: nil)
                self.stopView(key: viewKey, attributes: [:])
            },
            {
                let actionName = String.mockRandom()
                self.startView(key: viewKey, name: viewName, attributes: [:])
                self.addUserAction(type: [RUMUserActionType.swipe, .scroll, .tap, .custom].randomElement()!, name: actionName, attributes: [:])
                self.sendRandomActionOutcomeEvent()
                self.stopView(key: viewKey, attributes: [:])
            }
        ]
        // swiftlint:enable opening_brace
        let randomEvent = RUMEvents.randomElement()!
        randomEvent()
    }

    func sendRandomActionOutcomeEvent() {
        if Bool.random() {
            let key = String.mockRandom()
            self.startResourceLoading(resourceKey: key, httpMethod: .get, urlString: key)
            self.stopResourceLoading(resourceKey: key, statusCode: (200...500).randomElement()!, kind: .other)
        } else {
            self.addError(message: String.mockRandom(), source: .custom, stack: nil, attributes: [:], file: nil, line: nil)
        }
    }
}
