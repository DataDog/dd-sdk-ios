/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

internal class RUMViewScope: RUMScope, RUMContextProvider {
    // MARK: - Child Scopes

    /// Active Resource scopes, keyed by .resourceKey.
    private(set) var resourceScopes: [String: RUMResourceScope] = [:]
    /// Active User Action scope. There can be only one active user action at a time.
    private(set) var userActionScope: RUMUserActionScope?

    // MARK: - Initialization

    private unowned let parent: RUMContextProvider
    private let dependencies: RUMScopeDependencies

    /// The value holding stable identity of this RUM View.
    let identity: RUMViewIdentity
    /// View attributes.
    private(set) var attributes: [AttributeKey: AttributeValue]
    /// View custom timings, keyed by name. The value of timing is given in nanoseconds.
    private(set) var customTimings: [String: Int64] = [:]

    /// This View's UUID.
    let viewUUID: RUMUUID
    /// The path of this View, used as the `VIEW URL` in RUM Explorer.
    let viewPath: String
    /// The name of this View, used as the `VIEW NAME` in RUM Explorer.
    let viewName: String
    /// The start time of this View.
    private let viewStartTime: Date
    /// Date correction to server time.
    private let dateCorrection: DateCorrection
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
        identity: RUMViewIdentifiable,
        path: String,
        name: String,
        attributes: [AttributeKey: AttributeValue],
        customTimings: [String: Int64],
        startTime: Date
    ) {
        self.parent = parent
        self.dependencies = dependencies
        self.identity = identity.asRUMViewIdentity()
        self.attributes = attributes
        self.customTimings = customTimings
        self.viewUUID = dependencies.rumUUIDGenerator.generateUnique()
        self.viewPath = path
        self.viewName = name
        self.viewStartTime = startTime
        self.dateCorrection = dependencies.dateCorrector.currentCorrection
    }

    // MARK: - RUMContextProvider

    var context: RUMContext {
        var context = parent.context
        context.activeViewID = viewUUID
        context.activeViewPath = viewPath
        context.activeUserActionID = userActionScope?.actionUUID
        context.activeViewName = viewName
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
        case let command as RUMStartViewCommand where identity.equals(command.identity):
            if didReceiveStartCommand {
                // This is the case of duplicated "start" command. We know that the Session scope has created another instance of
                // the `RUMViewScope` for tracking this View, so we mark this one as inactive.
                isActiveView = false
            }
            if command.isInitialView {
                actionsCount += 1
                sendApplicationStartAction(on: command)
            }
            didReceiveStartCommand = true
            needsViewUpdate = true
        case let command as RUMStartViewCommand where !identity.equals(command.identity):
            isActiveView = false
            needsViewUpdate = true // sanity update (in case if the user forgets to end this View)
        case let command as RUMStopViewCommand where identity.equals(command.identity):
            isActiveView = false
            needsViewUpdate = true

        case let command as RUMAddViewTimingCommand where isActiveView:
            customTimings[command.timingName] = command.time.timeIntervalSince(viewStartTime).toInt64Nanoseconds
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
            resourceScopes[resourceCommand.resourceKey] = manage(
                childScope: resourceScopes[resourceCommand.resourceKey],
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
        resourceScopes[command.resourceKey] = RUMResourceScope(
            context: context,
            dependencies: dependencies,
            resourceKey: command.resourceKey,
            attributes: command.attributes,
            startTime: command.time,
            dateCorrection: dateCorrection,
            url: command.url,
            httpMethod: command.httpMethod,
            isFirstPartyResource: command.isFirstPartyRequest,
            resourceKindBasedOnRequest: command.kind,
            spanContext: command.spanContext
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
            dateCorrection: dateCorrection,
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
            dateCorrection: dateCorrection,
            isContinuous: false
        )
    }

    // MARK: - Sending RUM Events

    private func sendApplicationStartAction(on command: RUMCommand) {
        let eventData = RUMActionEvent(
            dd: .init(),
            action: .init(
                crash: nil,
                error: nil,
                id: dependencies.rumUUIDGenerator.generateUnique().toRUMDataFormat,
                loadingTime: dependencies.launchTimeProvider.launchTime?.toInt64Nanoseconds,
                longTask: nil,
                resource: nil,
                target: nil,
                type: .applicationStart
            ),
            application: .init(id: context.rumApplicationID),
            connectivity: dependencies.connectivityInfoProvider.current,
            date: dateCorrection.applying(to: viewStartTime).timeIntervalSince1970.toInt64Milliseconds,
            service: nil,
            session: .init(hasReplay: nil, id: context.sessionID.toRUMDataFormat, type: .user),
            usr: dependencies.userInfoProvider.current,
            view: .init(
                id: viewUUID.toRUMDataFormat,
                name: viewName,
                referrer: nil,
                url: viewPath
            )
        )

        let event = dependencies.eventBuilder.createRUMEvent(with: eventData, attributes: command.attributes)
        dependencies.eventOutput.write(rumEvent: event)
    }

    private func sendViewUpdateEvent(on command: RUMCommand) {
        version += 1
        attributes.merge(rumCommandAttributes: command.attributes)

        let eventData = RUMViewEvent(
            dd: .init(documentVersion: version.toInt64),
            application: .init(id: context.rumApplicationID),
            connectivity: dependencies.connectivityInfoProvider.current,
            date: dateCorrection.applying(to: viewStartTime).timeIntervalSince1970.toInt64Milliseconds,
            service: nil,
            session: .init(hasReplay: nil, id: context.sessionID.toRUMDataFormat, type: .user),
            usr: dependencies.userInfoProvider.current,
            view: .init(
                action: .init(count: actionsCount.toInt64),
                crash: nil,
                cumulativeLayoutShift: nil,
                customTimings: customTimings,
                domComplete: nil,
                domContentLoaded: nil,
                domInteractive: nil,
                error: .init(count: errorsCount.toInt64),
                firstContentfulPaint: nil,
                firstInputDelay: nil,
                firstInputTime: nil,
                id: viewUUID.toRUMDataFormat,
                isActive: isActiveView,
                largestContentfulPaint: nil,
                loadEvent: nil,
                loadingTime: nil,
                loadingType: nil,
                longTask: nil,
                name: viewName,
                referrer: nil,
                resource: .init(count: resourcesCount.toInt64),
                timeSpent: command.time.timeIntervalSince(viewStartTime).toInt64Nanoseconds,
                url: viewPath
            )
        )

        let event = dependencies.eventBuilder.createRUMEvent(with: eventData, attributes: attributes)
        dependencies.eventOutput.write(rumEvent: event)
    }

    private func sendErrorEvent(on command: RUMAddCurrentViewErrorCommand) {
        attributes.merge(rumCommandAttributes: command.attributes)

        let eventData = RUMErrorEvent(
            dd: .init(),
            action: context.activeUserActionID.flatMap { rumUUID in
                .init(id: rumUUID.toRUMDataFormat)
            },
            application: .init(id: context.rumApplicationID),
            connectivity: dependencies.connectivityInfoProvider.current,
            date: dateCorrection.applying(to: command.time).timeIntervalSince1970.toInt64Milliseconds,
            error: .init(
                isCrash: nil,
                message: command.message,
                resource: nil,
                source: command.source.toRUMDataFormat,
                stack: command.stack,
                type: command.type
            ),
            service: nil,
            session: .init(hasReplay: nil, id: context.sessionID.toRUMDataFormat, type: .user),
            usr: dependencies.userInfoProvider.current,
            view: .init(
                id: context.activeViewID.orNull.toRUMDataFormat,
                name: context.activeViewName,
                referrer: nil,
                url: context.activeViewPath ?? ""
            )
        )

        let event = dependencies.eventBuilder.createRUMEvent(with: eventData, attributes: attributes)
        dependencies.eventOutput.write(rumEvent: event)
    }
}
