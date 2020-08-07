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
    /// User Action attributes.
    private(set) var attributes: [AttributeKey: AttributeValue]

    /// This User Action's UUID.
    internal let actionUUID: RUMUUID
    /// The start time of this User Action.
    private var actionStartTime: Date
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
        actionType: RUMUserActionType,
        attributes: [AttributeKey: AttributeValue],
        startTime: Date,
        isContinuous: Bool
    ) {
        self.parent = parent
        self.dependencies = dependencies
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
        if isContinuous { // e.g. "scroll"
            if expired(currentTime: command.time) {
                sendActionEvent(completionTime: command.time)
                return false
            }
        } else { // e.g. "tap"
            if timedOut(currentTime: command.time) && allResourcesCompletedLoading() {
                sendActionEvent(completionTime: lastActivityTime)
                return false
            }
        }

        lastActivityTime = command.time

        switch command {
        case let command as RUMStopUserActionCommand:
            sendActionEvent(completionTime: command.time, on: command)
            return false

        case let command as RUMResourceCommand:
            if command is  RUMStartResourceCommand {
                activeResourcesCount += 1
            } else if command is RUMStopResourceCommand {
                activeResourcesCount -= 1
                resourcesCount += 1
            } else if command is RUMStopResourceWithErrorCommand {
                activeResourcesCount -= 1
                errorsCount += 1
            }

        case _ as RUMAddCurrentViewErrorCommand:
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
            usr: nil,
            connectivity: nil,
            dd: .init(),
            action: .init(
                type: actionType.toRUMDataFormat,
                id: actionUUID.toRUMDataFormat,
                loadingTime: completionTime.timeIntervalSince(actionStartTime).toInt64Nanoseconds,
                target: nil,
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

    private func timedOut(currentTime: Date) -> Bool {
        let timeElapsedSinceLastActivity = currentTime.timeIntervalSince(lastActivityTime)
        let timedOut = timeElapsedSinceLastActivity >= Constants.discreteActionTimeoutDuration
        return timedOut
    }

    private func expired(currentTime: Date) -> Bool {
        let actionDuration = currentTime.timeIntervalSince(actionStartTime)
        let expired = actionDuration >= Constants.continuousActionMaxDuration
        return expired
    }

    private func allResourcesCompletedLoading() -> Bool {
        return activeResourcesCount <= 0
    }
}
