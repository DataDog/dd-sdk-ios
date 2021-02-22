/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

internal class RUMUserActionScope: RUMScope, RUMContextProvider {
    struct Constants {
        /// If no activity is observed within this period in a discrete (discontinous) User Action, it is condiered ended.
        /// The activity may be i.e. due to Resource started loading.
        static let discreteActionTimeoutDuration: TimeInterval = 0.1 // 100 milliseconds
        /// Maximum duration of a continuous User Action. If it gets exceeded, a new session is started.
        static let continuousActionMaxDuration: TimeInterval = 10 // 10 seconds
    }

    var state: RUMScopeState

    // MARK: - Initialization

    private unowned let parent: RUMContextProvider
    private let dependencies: RUMScopeDependencies

    /// The type of this User Action.
    internal let actionType: RUMUserActionType
    /// The name of this User Action.
    fileprivate(set) var name: String
    /// User Action attributes.
    private(set) var attributes: [AttributeKey: AttributeValue]

    /// This User Action's UUID.
    let actionUUID: RUMUUID
    /// The start time of this User Action.
    private let actionStartTime: Date
    /// Date correction to server time.
    private let dateCorrection: DateCorrection
    /// Tells if this action is continuous over time, like "scroll" (or discrete, like "tap").
    internal let isContinuous: Bool
    /// Time of the last RUM activity noticed by this User Action (i.e. Resource loading).
    fileprivate var lastActivityTime: Date

    /// Number of Resources started during this User Action's lifespan.
    fileprivate var resourcesCount: Int = 0
    /// Number of Errors occured during this User Action's lifespan.
    fileprivate var errorsCount: Int = 0
    /// Number of Resources that started but not yet ended during this User Action's lifespan.
    fileprivate var activeResourcesCount: Int = 0

    init(
        parent: RUMContextProvider,
        dependencies: RUMScopeDependencies,
        name: String,
        actionType: RUMUserActionType,
        attributes: [AttributeKey: AttributeValue],
        startTime: Date,
        dateCorrection: DateCorrection,
        isContinuous: Bool
    ) {
        self.state = .open
        self.parent = parent
        self.dependencies = dependencies
        self.name = name
        self.actionType = actionType
        self.attributes = attributes
        self.actionUUID = dependencies.rumUUIDGenerator.generateUnique()
        self.actionStartTime = startTime
        self.dateCorrection = dateCorrection
        self.isContinuous = isContinuous
        self.lastActivityTime = startTime
    }

    // MARK: - RUMContextProvider

    var context: RUMContext {
        // Per `RUMCurrentContext.activeViewContext`, we currently only get the context from the parent scope (`RUMViewScope`) when it's still active (`viewScopes.last`).
        // This might change at some point and the following context might then hold the wrong active view's properties at that point as this is not checked inside `RUMViewScope.context`.
        return parent.context
    }

    // MARK: - RUMScope

    func process(command: RUMCommand) -> RUMScopeState {
        if let state = command.apply(to: self) {
            return state
        }

        switch command {
        case let command as RUMStopViewCommand:
            return command.apply(to: self)
        case let command as RUMStopUserActionCommand:
            return command.apply(to: self)
        case let command as RUMStartResourceCommand:
            return command.apply(to: self)
        case let command as RUMStopResourceCommand:
            return command.apply(to: self)
        case let command as RUMStopResourceWithErrorCommand:
            return command.apply(to: self)
        case let command as RUMAddCurrentViewErrorCommand:
            return command.apply(to: self)
        case let command as RUMEventsMappingCompletionCommand<RUMResourceEvent>:
            return command.apply(to: self)
        case let command as RUMEventsMappingCompletionCommand<RUMErrorEvent>:
            return command.apply(to: self)
        case let command as RUMEventsMappingCompletionCommand<RUMActionEvent>:
            return command.apply(to: self)
        default:
            return state
        }
    }

    // MARK: - Sending RUM Events

    fileprivate func sendActionEvent(completionTime: Date, on command: RUMCommand? = nil) {
        if let commandAttributes = command?.attributes {
            attributes.merge(rumCommandAttributes: commandAttributes)
        }

        let eventData = RUMActionEvent(
            dd: .init(),
            action: .init(
                crash: nil,
                error: .init(count: max(0, errorsCount).toInt64),
                id: actionUUID.toRUMDataFormat,
                loadingTime: completionTime.timeIntervalSince(actionStartTime).toInt64Nanoseconds,
                longTask: nil,
                resource: .init(count: max(0, resourcesCount).toInt64),
                target: .init(name: name),
                type: actionType.toRUMDataFormat
            ),
            application: .init(id: context.rumApplicationID),
            connectivity: dependencies.connectivityInfoProvider.current,
            date: dateCorrection.applying(to: actionStartTime).timeIntervalSince1970.toInt64Milliseconds,
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

    // MARK: - Private

    fileprivate func possibleExpirationTime(currentTime: Date) -> Date? {
        var expirationDate: Date? = nil
        let elapsedTime = currentTime.timeIntervalSince(actionStartTime)
        let maxInterval = isContinuous ? Constants.continuousActionMaxDuration : Constants.discreteActionTimeoutDuration
        if elapsedTime >= maxInterval {
            expirationDate = actionStartTime + maxInterval
        }
        return expirationDate
    }

    fileprivate func allResourcesCompletedLoading() -> Bool {
        return activeResourcesCount <= 0
    }
}

extension RUMCommand {
    func apply(to scope: RUMUserActionScope) -> RUMScopeState? {
        if let expirationTime = scope.possibleExpirationTime(currentTime: time),
           scope.allResourcesCompletedLoading(),
           scope.state == .open {
            scope.sendActionEvent(completionTime: expirationTime)
            return .closing
        }
        return nil
    }
}

extension RUMStopViewCommand {
    func apply(to scope: RUMUserActionScope) -> RUMScopeState {
        if scope.state == .open {
            scope.lastActivityTime = time
            scope.sendActionEvent(completionTime: time)
            return .closing
        }
        return scope.state
    }
}

extension RUMStopUserActionCommand {
    func apply(to scope: RUMUserActionScope) -> RUMScopeState {
        if scope.state == .open {
            scope.lastActivityTime = time
            scope.name = name ?? scope.name
            scope.sendActionEvent(completionTime: time, on: self)
            return .closing
        }
        return scope.state
    }
}

extension RUMStartResourceCommand {
    func apply(to scope: RUMUserActionScope) -> RUMScopeState {
        if scope.state == .open {
            scope.lastActivityTime = time
            scope.activeResourcesCount += 1
        }
        return scope.state
    }
}

extension RUMStopResourceCommand {
    func apply(to scope: RUMUserActionScope) -> RUMScopeState {
        if scope.state == .open {
            scope.lastActivityTime = time
            scope.activeResourcesCount -= 1
            scope.resourcesCount += 1
        }
        return scope.state
    }
}

extension RUMStopResourceWithErrorCommand {
    func apply(to scope: RUMUserActionScope) -> RUMScopeState {
        if scope.state == .open {
            scope.lastActivityTime = time
            scope.activeResourcesCount -= 1
            scope.errorsCount += 1
        }
        return scope.state
    }
}

extension RUMAddCurrentViewErrorCommand {
    func apply(to scope: RUMUserActionScope) -> RUMScopeState {
        if scope.state == .open {
            scope.lastActivityTime = time
            scope.errorsCount += 1
        }
        return scope.state
    }
}
extension RUMEventsMappingCompletionCommand where DM == RUMResourceEvent {
    func apply(to scope: RUMUserActionScope) -> RUMScopeState {
        if scope.state == .open && change == .discarded {
            scope.resourcesCount -= 1
        }
        return scope.state
    }
}

extension RUMEventsMappingCompletionCommand where DM == RUMErrorEvent {
    func apply(to scope: RUMUserActionScope) -> RUMScopeState {
        if scope.state == .open && change == .discarded {
            scope.errorsCount -= 1
        }
        return scope.state
    }
}

extension RUMEventsMappingCompletionCommand where DM == RUMActionEvent {
    func apply(to scope: RUMUserActionScope) -> RUMScopeState {
        if model.action.id == scope.actionUUID.toRUMDataFormat {
            return change == .discarded ? .discarded : .closed
        }
        return scope.state
    }
}
