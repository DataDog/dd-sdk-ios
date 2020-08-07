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
    /// Active User Action scope. There can be only one active user action at a time.
    private(set) var userActionScope: RUMUserActionScope?

    // MARK: - Initialization

    // TODO: RUMM-597: Consider using `parent: RUMContextProvider`
    private unowned let parent: RUMScope
    private let dependencies: RUMScopeDependencies

    /// Weak reference to corresponding `UIViewController`, used to identify this View.
    private(set) weak var identity: AnyObject?
    /// View attributes.
    private(set) var attributes: [AttributeKey: AttributeValue]

    /// This View's UUID.
    let viewUUID: RUMUUID
    /// The URI of this View, used as the `view.url` in RUM Explorer.
    let viewURI: String
    /// The start time of this View.
    private let viewStartTime: Date

    /// Number of Actions happened on this View.
    private var actionsCount: UInt = 0
    /// Number of Resources tracked by this View.
    private var resourcesCount: UInt = 0
    /// Number of Errors tracked by this View.
    private var errorsCount: UInt = 0

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
        context.activeUserActionID = userActionScope?.actionUUID
        return context
    }

    func process(command: RUMCommand) -> Bool {
        // Tells if the View did change and an update event should be send
        var needsViewUpdate = false
        // Tells if this scope should complete after processing the `command`
        var shouldComplete = false

        // Apply side effects
        switch command {
        // View commands
        case let command as RUMStartViewCommand where command.identity === identity:
            if command.isInitialView {
                actionsCount += 1
                sendApplicationStartAction()
            }
            needsViewUpdate = true
        case let command as RUMStopViewCommand where command.identity === identity:
            shouldComplete = true

        // Resource commands
        case let command as RUMStartResourceCommand:
            startResource(on: command)
        case _ as RUMStopResourceCommand:
            resourcesCount += 1
            needsViewUpdate = true
        case _ as RUMStopResourceWithErrorCommand:
            errorsCount += 1
            needsViewUpdate = true

        // User Action commands
        case let command as RUMStartUserActionCommand:
            startContinuousUserAction(on: command)
        case let command as RUMAddUserActionCommand:
            addDiscreteUserAction(on: command)

        // Error command
        case let command as RUMAddCurrentViewErrorCommand:
            errorsCount += 1
            sendErrorEvent(on: command)
            needsViewUpdate = true

        default:
            break
        }

        // Propagate to Resource scopes
        if let resourceCommand = command as? RUMResourceCommand {
            resourceScopes[resourceCommand.resourceName] = manage(
                childScope: resourceScopes[resourceCommand.resourceName],
                byPropagatingCommand: resourceCommand
            )
        }

        // Propagate to User Action scope
        let beforeHadUserAction = userActionScope != nil
        userActionScope = manage(childScope: userActionScope, byPropagatingCommand: command)
        let afterHasUserAction = userActionScope != nil

        if beforeHadUserAction && !afterHasUserAction { // if User Action was tracked
            actionsCount += 1
            needsViewUpdate = true
        }

        if shouldComplete || needsViewUpdate {
            sendViewUpdateEvent(on: command)
        }

        return !shouldComplete
    }

    // MARK: - RUMCommands Processing

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

    private func startContinuousUserAction(on command: RUMStartUserActionCommand) {
        userActionScope = RUMUserActionScope(
            parent: self,
            dependencies: dependencies,
            actionType: command.actionType,
            attributes: command.attributes,
            startTime: command.time,
            isContinuous: true
        )
    }

    private func addDiscreteUserAction(on command: RUMAddUserActionCommand) {
        userActionScope = RUMUserActionScope(
            parent: self,
            dependencies: dependencies,
            actionType: command.actionType,
            attributes: command.attributes,
            startTime: command.time,
            isContinuous: false
        )
    }

    // MARK: - Sending RUM Events

    private func sendApplicationStartAction() {
        let eventData = RUMActionEvent(
            date: viewStartTime.timeIntervalSince1970.toMilliseconds,
            application: .init(id: context.rumApplicationID),
            session: .init(id: context.sessionID.toRUMDataFormat, type: "user"),
            view: .init(
                id: viewUUID.toRUMDataFormat,
                url: viewURI
            ),
            action: .init(
                id: dependencies.rumUUIDGenerator.generateUnique().toRUMDataFormat,
                type: "application_start",
                loadingTime: nil,
                resource: nil,
                error: nil
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
            session: .init(id: context.sessionID.toRUMDataFormat, type: "user"),
            view: .init(
                id: viewUUID.toRUMDataFormat,
                url: viewURI,
                timeSpent: command.time.timeIntervalSince(viewStartTime).toNanoseconds,
                action: .init(count: actionsCount),
                error: .init(count: errorsCount),
                resource: .init(count: resourcesCount)
            ),
            dd: .init(documentVersion: version)
        )

        let event = dependencies.eventBuilder.createRUMEvent(with: eventData, attributes: attributes)
        dependencies.eventOutput.write(rumEvent: event)
    }

    private func sendErrorEvent(on command: RUMAddCurrentViewErrorCommand) {
        attributes.merge(rumCommandAttributes: command.attributes)

        let eventData = RUMError(
            date: command.time.timeIntervalSince1970.toInt64Milliseconds,
            application: .init(id: context.rumApplicationID),
            session: .init(id: context.sessionID.toRUMDataFormat, type: .user),
            view: .init(
                id: context.activeViewID.orNull.toRUMDataFormat,
                referrer: nil,
                url: context.activeViewURI ?? ""
            ),
            usr: nil,
            connectivity: nil,
            dd: .init(),
            error: .init(
                message: command.message,
                source: command.source.toRUMDataFormat,
                stack: command.stack,
                isCrash: nil,
                resource: nil
            ),
            action: context.activeUserActionID.flatMap { rumUUID in
                .init(id: rumUUID.toRUMDataFormat)
            }
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
