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
    private let viewUUID: RUMUUID
    /// The URI of this View, used as the `view.url` in RUM Explorer.
    private let viewURI: String
    /// The start time of this View.
    private var viewStartTime: Date

    /// Number of actions happened on this View.
    private var actionsCount: UInt = 0
    /// Current version of this View to use for RUM `documentVersion`.
    private var version: UInt = 0

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
        self.viewUUID = dependencies.rumUUIDGenerator.generateUnique()
        self.viewURI = RUMViewScope.viewURI(from: identity)
        self.viewStartTime = startTime
    }

    // MARK: - RUMScope

    var context: RUMContext {
        return parent.context
    }

    func process(command: RUMCommand) -> Bool {
        switch command {
        case .startInitialView(let id, _, _) where id === identity:
            startAsInitialView(on: command)
        case .startView(let id, _, _) where id === identity:
            startView(on: command)
        case .stopView(let id, _, _) where id === identity:
            stopView(on: command)
            return false
        default:
            break
        }

        return true
    }

    // MARK: - RUMCommands Processing

    private func startAsInitialView(on command: RUMCommand) {
        sendApplicationStartAction()
        sendViewUpdateEvent(on: command)
    }

    private func startView(on command: RUMCommand) {
        sendViewUpdateEvent(on: command)
    }

    private func stopView(on command: RUMCommand) {
        sendViewUpdateEvent(on: command)
    }

    // MARK: - Sending RUM Events

    private func sendApplicationStartAction() {
        actionsCount += 1

        let eventData = RUMActionEvent(
            date: viewStartTime.timeIntervalSince1970.toMilliseconds,
            application: .init(id: context.rumApplicationID),
            session: .init(id: context.sessionID.toString, type: "user"),
            view: .init(
                id: viewUUID.toString,
                url: viewURI
            ),
            action: .init(
                id: dependencies.rumUUIDGenerator.generateUnique().toString,
                type: "application_start"
            ),
            dd: .init()
        )

        let event = dependencies.eventBuilder.createRUMEvent(with: eventData, attributes: [:])
        dependencies.eventOutput.write(rumEvent: event)
    }

    private func sendViewUpdateEvent(on command: RUMCommand) {
        version += 1
        attributes.merge(rumCommandAttributes: command.attributes)

        let eventData = RUMViewEvent(
            date: command.time.timeIntervalSince1970.toMilliseconds,
            application: .init(id: context.rumApplicationID),
            session: .init(id: context.sessionID.toString, type: "user"),
            view: .init(
                id: viewUUID.toString,
                url: viewURI,
                timeSpent: command.time.timeIntervalSince(viewStartTime).toNanoseconds,
                action: .init(count: actionsCount),
                error: .init(count: 0),
                resource: .init(count: 0)
            ),
            dd: .init(documentVersion: version)
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
