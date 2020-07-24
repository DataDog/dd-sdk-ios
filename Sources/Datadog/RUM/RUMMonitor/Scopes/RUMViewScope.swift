/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import UIKit

internal class RUMViewScope: RUMScope {
    // MARK: - Child Scopes

    /// Active Resource scopes, keyed by the Resource name.
    private(set) var resourceScopes: [String: RUMResourceScope] = [:]

    // MARK: - Initialization

    // TODO: RUMM-597: Consider using `parent: RUMContextProvider`
    private unowned let parent: RUMScope
    private let dependencies: RUMScopeDependencies

    /// Weak reference to corresponding `UIViewController`, used to identify this View.
    private(set) weak var identity: AnyObject?
    /// View attributes.
    private(set) var attributes: [AttributeKey: AttributeValue]

    /// This View UUID.
    let viewUUID: RUMUUID
    /// The URI of this View, used as the `view.url` in RUM Explorer.
    let viewURI: String
    /// The start time of this View.
    private var viewStartTime: Date

    /// Number of Actions happened on this View.
    private var actionsCount: UInt = 0
    /// Number of Resources tracked by this View.
    private var resourcesCount: UInt = 0
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
        var context = parent.context
        context.activeViewID = viewUUID
        context.activeViewURI = viewURI
        return context
    }

    func process(command: RUMCommand) -> Bool {
        // Apply side effects
        switch command {
        case let command as RUMStartViewCommand where command.identity === identity:
            startView(on: command)
        case let command as RUMStopViewCommand where command.identity === identity:
            stopView(on: command)
            return false
        case let command as RUMStartResourceCommand:
            startResource(on: command)
        case let command as RUMResourceCommand where command is RUMStopResourceCommand || command is RUMStopResourceWithErrorCommand:
            stopResource(on: command)
        default:
            break
        }

        // Propagate command
        if let resourceCommand = command as? RUMResourceCommand {
            manage(childScope: &resourceScopes[resourceCommand.resourceName], byPropagatingCommand: resourceCommand)
        }

        return true
    }

    // MARK: - RUMCommands Processing

    private func startView(on command: RUMStartViewCommand) {
        if command.isInitialView {
            actionsCount += 1
            sendApplicationStartAction()
            sendViewUpdateEvent(on: command)
        } else {
            sendViewUpdateEvent(on: command)
        }
    }

    private func stopView(on command: RUMStopViewCommand) {
        sendViewUpdateEvent(on: command)
    }

    private func startResource(on command: RUMStartResourceCommand) {
        resourceScopes[command.resourceName] = RUMResourceScope(
            parent: self,
            dependencies: dependencies,
            resourceName: command.resourceName,
            attributes: command.attributes,
            startTime: command.time,
            url: command.url,
            httpMethod: command.httpMethod
        )
    }

    private func stopResource(on command: RUMResourceCommand) {
        resourcesCount += 1
        sendViewUpdateEvent(on: command)
    }

    // MARK: - Sending RUM Events

    private func sendApplicationStartAction() {
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
            date: viewStartTime.timeIntervalSince1970.toMilliseconds,
            application: .init(id: context.rumApplicationID),
            session: .init(id: context.sessionID.toString, type: "user"),
            view: .init(
                id: viewUUID.toString,
                url: viewURI,
                timeSpent: command.time.timeIntervalSince(viewStartTime).toNanoseconds,
                action: .init(count: actionsCount),
                error: .init(count: 0),
                resource: .init(count: resourcesCount)
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
