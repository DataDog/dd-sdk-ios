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
    /// Tells if this action is continuous over time, like "scroll" (or discrete, like "tap").
    internal let isContinuous: Bool
    /// Time of the last RUM activity noticed by this User Action (i.e. Resource loading).
    private var lastActivityTime: Date

    /// Number of Resources started during this User Action's lifespan.
    private var resourcesCount: UInt = 0
    /// Number of Errors occured during this User Action's lifespan.
    private var errorsCount: UInt = 0
    /// Number of Resources that started but not yet ended during this User Action's lifespan.
    private var activeResourcesCount: Int = 0

    init(
        parent: RUMContextProvider,
        dependencies: RUMScopeDependencies,
        name: String,
        actionType: RUMUserActionType,
        attributes: [AttributeKey: AttributeValue],
        startTime: Date,
        isContinuous: Bool
    ) {
        self.parent = parent
        self.dependencies = dependencies
        self.name = name
        self.actionType = actionType
        self.attributes = attributes
        self.actionUUID = dependencies.rumUUIDGenerator.generateUnique()
        self.actionStartTime = startTime
        self.isContinuous = isContinuous
        self.lastActivityTime = startTime
    }

    // MARK: - RUMContextProvider

    var context: RUMContext {
        return parent.context
    }

    // MARK: - RUMScope

    func process(command: RUMCommand) -> Bool {
        if let expirationTime = possibleExpirationTime(currentTime: command.time),
           allResourcesCompletedLoading() {
            sendActionEvent(completionTime: expirationTime)
            return false
        }

        lastActivityTime = command.time
        switch command {
        case is RUMStopViewCommand:
            sendActionEvent(completionTime: command.time)
            return false
        case let command as RUMStopUserActionCommand:
            name = command.name ?? name
            sendActionEvent(completionTime: command.time, on: command)
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
        default:
            break
        }
        return true
    }

    // MARK: - Sending RUM Events

    private func sendActionEvent(completionTime: Date, on command: RUMCommand? = nil) {
        if let commandAttributes = command?.attributes {
            attributes.merge(rumCommandAttributes: commandAttributes)
        }

        let eventData = RUMAction(
            date: actionStartTime.timeIntervalSince1970.toInt64Milliseconds,
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
            action: .init(
                type: actionType.toRUMDataFormat,
                id: actionUUID.toRUMDataFormat,
                loadingTime: completionTime.timeIntervalSince(actionStartTime).toInt64Nanoseconds,
                target: RUMTarget(name: name),
                error: .init(count: errorsCount.toInt64),
                crash: nil,
                longTask: nil,
                resource: .init(count: resourcesCount.toInt64)
            )
        )

        let event = dependencies.eventBuilder.createRUMEvent(with: eventData, attributes: attributes)
        dependencies.eventOutput.write(rumEvent: event)
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
