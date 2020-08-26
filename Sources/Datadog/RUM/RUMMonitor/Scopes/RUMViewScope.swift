/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

internal class RUMViewScope: RUMScope, RUMContextProvider {
    // MARK: - Child Scopes

    /// Active Resource scopes, keyed by the Resource name.
    private(set) var resourceScopes: [String: RUMResourceScope] = [:]
    /// Active User Action scope. There can be only one active user action at a time.
    private(set) var userActionScope: RUMUserActionScope?

    // MARK: - Initialization

    private unowned let parent: RUMContextProvider
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
    /// Tells if this View is the active one.
    /// `true` for every new started View.
    /// `false` if the View was stopped or any other View was started.
    private(set) var isActiveView: Bool = true
    /// Tells if this scope has received the "start" command.
    /// If `didReceiveStartCommand == true` and another "start" command is received for this View this scope is marked as inactive.
    private var didReceiveStartCommand = false

    /// Number of Actions happened on this View.
    private var actionsCount: UInt = 0
    /// Number of Resources tracked by this View.
    private var resourcesCount: UInt = 0
    /// Number of Errors tracked by this View.
    private var errorsCount: UInt = 0

    /// Current version of this View to use for RUM `documentVersion`.
    private var version: UInt = 0

    init(
        parent: RUMContextProvider,
        dependencies: RUMScopeDependencies,
        identity: AnyObject,
        uri: String,
        attributes: [AttributeKey: AttributeValue],
        startTime: Date
    ) {
        self.parent = parent
        self.dependencies = dependencies
        self.identity = identity
        self.attributes = attributes
        self.viewUUID = dependencies.rumUUIDGenerator.generateUnique()
        self.viewURI = uri
        self.viewStartTime = startTime
    }

    // MARK: - RUMContextProvider

    var context: RUMContext {
        var context = parent.context
        context.activeViewID = viewUUID
        context.activeViewURI = viewURI
        context.activeUserActionID = userActionScope?.actionUUID
        return context
    }

    // MARK: - RUMScope

    func process(command: RUMCommand) -> Bool {
        // Tells if the View did change and an update event should be send.
        var needsViewUpdate = false

        // Propagate to User Action scope
        let beforeHadUserAction = userActionScope != nil
        userActionScope = manage(childScope: userActionScope, byPropagatingCommand: command)
        let afterHasUserAction = userActionScope != nil

        if beforeHadUserAction && !afterHasUserAction { // if User Action was tracked
            actionsCount += 1
            needsViewUpdate = true
        }

        // Apply side effects
        switch command {
        // View commands
        case let command as RUMStartViewCommand where command.identity === identity:
            if didReceiveStartCommand {
                // This is the case of duplicated "start" command. We know that the Session scope has created another instance of
                // the `RUMViewScope` for tracking this View, so we mark this one as inactive.
                isActiveView = false
            }
            if command.isInitialView {
                actionsCount += 1
                sendApplicationStartAction()
            }
            didReceiveStartCommand = true
            needsViewUpdate = true
        case let command as RUMStartViewCommand where command.identity !== identity:
            isActiveView = false
            needsViewUpdate = true // sanity update (in case if the user forgets to end this View)
        case let command as RUMStopViewCommand where command.identity === identity:
            isActiveView = false
            needsViewUpdate = true

        // Resource commands
        case let command as RUMStartResourceCommand where isActiveView:
            startResource(on: command)

        // User Action commands
        case let command as RUMStartUserActionCommand where isActiveView:
            if userActionScope == nil {
                startContinuousUserAction(on: command)
            }
        case let command as RUMAddUserActionCommand where isActiveView:
            if userActionScope == nil {
                addDiscreteUserAction(on: command)
            }

        // Error command
        case let command as RUMAddCurrentViewErrorCommand where isActiveView:
            errorsCount += 1
            sendErrorEvent(on: command)
            needsViewUpdate = true

        default:
            break
        }

        // Propagate to Resource scopes
        let beforeResourcesCount = resourceScopes.count
        if let resourceCommand = command as? RUMResourceCommand {
            resourceScopes[resourceCommand.resourceName] = manage(
                childScope: resourceScopes[resourceCommand.resourceName],
                byPropagatingCommand: resourceCommand
            )
        }
        let afterResourcesCount = resourceScopes.count

        if beforeResourcesCount != afterResourcesCount { // if Resource was tracked
            if command is RUMStopResourceWithErrorCommand { // if Resource completed with error
                errorsCount += 1
            } else {
                resourcesCount += 1
            }
            needsViewUpdate = true
        }

        // Consider scope state and completion
        if needsViewUpdate {
            sendViewUpdateEvent(on: command)
        }

        let hasNoPendingResources = resourceScopes.isEmpty
        let shouldComplete = !isActiveView && hasNoPendingResources

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
            name: command.name,
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
            name: command.name,
            actionType: command.actionType,
            attributes: command.attributes,
            startTime: command.time,
            isContinuous: false
        )
    }

    // MARK: - Sending RUM Events

    private func sendApplicationStartAction() {
        let eventData = RUMAction(
            date: viewStartTime.timeIntervalSince1970.toInt64Milliseconds,
            application: .init(id: context.rumApplicationID),
            session: .init(id: context.sessionID.toRUMDataFormat, type: .user),
            view: .init(
                id: viewUUID.toRUMDataFormat,
                referrer: nil,
                url: viewURI
            ),
            usr: dependencies.userInfoProvider.current,
            connectivity: dependencies.connectivityInfoProvider.current,
            dd: .init(),
            action: .init(
                type: .applicationStart,
                id: dependencies.rumUUIDGenerator.generateUnique().toRUMDataFormat,
                loadingTime: nil,
                target: nil,
                error: nil,
                crash: nil,
                longTask: nil,
                resource: nil
            )
        )

        let event = dependencies.eventBuilder.createRUMEvent(with: eventData, attributes: [:])
        dependencies.eventOutput.write(rumEvent: event)
    }

    private func sendViewUpdateEvent(on command: RUMCommand) {
        version += 1
        attributes.merge(rumCommandAttributes: command.attributes)

        let eventData = RUMView(
            date: viewStartTime.timeIntervalSince1970.toInt64Milliseconds,
            application: .init(id: context.rumApplicationID),
            session: .init(id: context.sessionID.toRUMDataFormat, type: .user),
            view: .init(
                id: viewUUID.toRUMDataFormat,
                referrer: nil,
                url: viewURI,
                loadingTime: nil,
                loadingType: nil,
                timeSpent: command.time.timeIntervalSince(viewStartTime).toInt64Nanoseconds,
                firstContentfulPaint: nil,
                domComplete: nil,
                domContentLoaded: nil,
                domInteractive: nil,
                loadEvent: nil,
                action: .init(count: actionsCount.toInt64),
                error: .init(count: errorsCount.toInt64),
                crash: nil,
                longTask: nil,
                resource: .init(count: resourcesCount.toInt64)
            ),
            usr: dependencies.userInfoProvider.current,
            connectivity: dependencies.connectivityInfoProvider.current,
            dd: .init(documentVersion: version.toInt64)
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
            usr: dependencies.userInfoProvider.current,
            connectivity: dependencies.connectivityInfoProvider.current,
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
}
