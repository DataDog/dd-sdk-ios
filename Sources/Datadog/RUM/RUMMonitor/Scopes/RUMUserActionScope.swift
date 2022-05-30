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

    // MARK: - Initialization

    private unowned let parent: RUMContextProvider
    private let dependencies: RUMScopeDependencies

    /// The type of this User Action.
    internal let actionType: RUMUserActionType
    /// The name of this User Action.
    private(set) var name: String
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
    private var lastActivityTime: Date

    /// Number of Resources started during this User Action's lifespan.
    private var resourcesCount: UInt = 0
    /// Number of Errors occured during this User Action's lifespan.
    private var errorsCount: UInt = 0
    /// Number of Long Tasks occured during this User Action's lifespan.
    private var longTasksCount: Int64 = 0
    /// Number of Resources that started but not yet ended during this User Action's lifespan.
    private var activeResourcesCount: Int = 0

    /// Callback called when a `RUMActionEvent` is submitted for storage.
    private let onActionEventSent: () -> Void

    init(
        parent: RUMContextProvider,
        dependencies: RUMScopeDependencies,
        name: String,
        actionType: RUMUserActionType,
        attributes: [AttributeKey: AttributeValue],
        startTime: Date,
        dateCorrection: DateCorrection,
        isContinuous: Bool,
        onActionEventSent: @escaping () -> Void
    ) {
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
        self.onActionEventSent = onActionEventSent
    }

    // MARK: - RUMContextProvider

    var context: RUMContext {
        // Per `RUMCurrentContext.activeViewContext`, we currently only get the context from the parent scope (`RUMViewScope`) when it's still active (`viewScopes.last`).
        // This might change at some point and the following context might then hold the wrong active view's properties at that point as this is not checked inside `RUMViewScope.context`.
        return parent.context
    }

    // MARK: - RUMScope

    func process(command: RUMCommand) -> Bool {
        if let expirationTime = possibleExpirationTime(currentTime: command.time),
           allResourcesCompletedLoading() {
            if sendActionEvent(completionTime: expirationTime) {
                onActionEventSent()
            }
            return false
        }

        lastActivityTime = command.time
        switch command {
        case is RUMStopViewCommand:
            if sendActionEvent(completionTime: command.time) {
                onActionEventSent()
            }
            return false
        case let command as RUMStopUserActionCommand:
            name = command.name ?? name
            if sendActionEvent(completionTime: command.time, on: command) {
                onActionEventSent()
            }
            return false
        case is RUMStartResourceCommand:
            activeResourcesCount += 1
        case is RUMStopResourceCommand:
            activeResourcesCount -= 1
            resourcesCount += 1
        case is RUMStopResourceWithErrorCommand:
            activeResourcesCount -= 1
            errorsCount += 1
        case is RUMAddCurrentViewErrorCommand:
            errorsCount += 1
        case is RUMAddLongTaskCommand:
            // TODO: RUMM-1616 this command is ignored if arrived after 100ms
            longTasksCount += 1
        default:
            break
        }
        return true
    }

    // MARK: - Sending RUM Events

    private func sendActionEvent(completionTime: Date, on command: RUMCommand? = nil) -> Bool {
        if let commandAttributes = command?.attributes {
            attributes.merge(rumCommandAttributes: commandAttributes)
        }

        let eventData = RUMActionEvent(
            dd: .init(
                browserSdkVersion: nil,
                session: .init(plan: .plan1)
            ),
            action: .init(
                crash: nil,
                error: .init(count: errorsCount.toInt64),
                frustrationType: nil,
                id: actionUUID.toRUMDataFormat,
                loadingTime: completionTime.timeIntervalSince(actionStartTime).toInt64Nanoseconds,
                longTask: .init(count: longTasksCount),
                resource: .init(count: resourcesCount.toInt64),
                target: .init(name: name),
                type: actionType.toRUMDataFormat
            ),
            application: .init(id: context.rumApplicationID),
            ciTest: dependencies.ciTest,
            connectivity: dependencies.connectivityInfoProvider.current,
            context: .init(contextInfo: attributes),
            date: dateCorrection.applying(to: actionStartTime).timeIntervalSince1970.toInt64Milliseconds,
            service: dependencies.serviceName,
            session: .init(
                hasReplay: nil,
                id: context.sessionID.toRUMDataFormat,
                type: dependencies.ciTest != nil ? .ciTest : .user
            ),
            source: RUMActionEvent.Source(rawValue: dependencies.source) ?? .ios,
            synthetics: nil,
            usr: dependencies.userInfoProvider.current,
            version: dependencies.applicationVersion,
            view: .init(
                id: context.activeViewID.orNull.toRUMDataFormat,
                inForeground: nil,
                name: context.activeViewName,
                referrer: nil,
                url: context.activeViewPath ?? ""
            )
        )

        if let event = dependencies.eventBuilder.build(from: eventData) {
            dependencies.eventOutput.write(event: event)
            return true
        }
        return false
    }

    // MARK: - Private

    private func possibleExpirationTime(currentTime: Date) -> Date? {
        var expirationDate: Date? = nil
        let elapsedTime = currentTime.timeIntervalSince(actionStartTime)
        let maxInterval = isContinuous ? Constants.continuousActionMaxDuration : Constants.discreteActionTimeoutDuration
        if elapsedTime >= maxInterval {
            expirationDate = actionStartTime + maxInterval
        }
        return expirationDate
    }

    private func allResourcesCompletedLoading() -> Bool {
        return activeResourcesCount <= 0
    }
}
