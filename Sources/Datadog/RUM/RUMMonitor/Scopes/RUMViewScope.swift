/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import UIKit

internal class RUMViewScope: RUMScope {
    // MARK: - Initialization

    private unowned let parent: RUMScope
    private let dependencies: RUMScopeDependencies

    /// Weak reference to the `UIViewController` which issued this scope.
    private(set) weak var identity: AnyObject?
    /// View attributes.
    private(set) var attributes: [AttributeKey: AttributeValue]

    /// This View UUID.
    private let viewUUID: UUID
    /// The URI of this View, used as the `view.url` in RUM Explorer.
    private let viewURI: String
    /// The start time of this View.
    private var viewStartTime: Date

    /// Number of actions happened on this View.
    private var actionsCount: UInt = 0

    init(
        parent: RUMScope,
        dependencies: RUMScopeDependencies,
        identity: AnyObject,
        attributes: [AttributeKey: AttributeValue],
        startTime: Date
    ) {
        self.parent = parent
        self.dependencies = dependencies
        self.identity = identity
        self.attributes = attributes
        self.viewUUID = UUID()
        self.viewURI = RUMViewScope.viewURI(from: identity)
        self.viewStartTime = startTime
    }

    // MARK: - RUMScope

    var context: RUMContext {
        return parent.context
    }

    func process(command: RUMCommand) -> Bool {
        // Apply side effects
        switch command {
        case .startInitialView(let id, _, let time) where id === identity:
            sendApplicationStartAction()
            actionsCount += 1
            sendViewUpdateEvent(updateTime: time)
        default:
            break
        }

        // Create child scopes

        return true
    }

    // MARK: - Sending RUM Events

    private func sendApplicationStartAction() {
        let eventData = RUMActionEvent(
            date: viewStartTime.timeIntervalSince1970.toMilliseconds,
            application: .init(id: context.rumApplicationID),
            session: .init(id: context.sessionID.uuidString.lowercased(), type: "user"),
            view: .init(
                id: viewUUID.uuidString.lowercased(),
                url: viewURI
            ),
            action: .init(
                id: UUID().uuidString.lowercased(),
                type: "application_start"
            ),
            dd: .init()
        )

        let event = dependencies.eventBuilder.createRUMEvent(with: eventData, attributes: nil)
        dependencies.eventOutput.write(rumEvent: event)
    }

    private func sendViewUpdateEvent(updateTime: Date) {
        let eventData = RUMViewEvent(
            date: updateTime.timeIntervalSince1970.toMilliseconds,
            application: .init(id: context.rumApplicationID),
            session: .init(id: context.sessionID.uuidString.lowercased(), type: "user"),
            view: .init(
                id: viewUUID.uuidString.lowercased(),
                url: viewURI,
                timeSpent: updateTime.timeIntervalSince(viewStartTime).toNanoseconds,
                action: .init(count: actionsCount),
                error: .init(count: 0),
                resource: .init(count: 0)
            ),
            dd: .init(documentVersion: 1)
        )

        let event = dependencies.eventBuilder.createRUMEvent(with: eventData, attributes: attributes)
        dependencies.eventOutput.write(rumEvent: event)
    }

    // MARK: - Private

    private static func viewURI(from id: AnyObject) -> String {
        guard let viewController = id as? UIViewController else {
            return ""
        }

        return "\(type(of: viewController))"
    }
}
