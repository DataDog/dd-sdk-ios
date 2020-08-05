/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

internal class RUMUserActionScope: RUMScope {
    struct Constants {
        /// If no activity is observed within this period in a discrete (discontinous) User Action, it is condiered ended.
        /// The activity may be i.e. due to Resource started loading.
        static let discreteActionTimeoutDuration: TimeInterval = 0.1 // 100 milliseconds
        /// Maximum duration of a continuous User Action. If it gets exceeded, a new session is started.
        static let continuousActionMaxDuration: TimeInterval = 10 // 10 seconds
    }

    // MARK: - Initialization

    // TODO: RUMM-597: Consider using `parent: RUMContextProvider`
    private unowned let parent: RUMScope
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
        parent: RUMScope,
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

    // MARK: - RUMScope

    var context: RUMContext {
        return parent.context
    }

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
            willStopUserAction(on: command)
            return false

        case let command as RUMResourceCommand:
            if command is  RUMStartResourceCommand {
                startTrackingResource()
            } else if command is RUMStopResourceCommand {
                stopTrackingResource()
            } else if command is RUMStopResourceWithErrorCommand {
                trackResourceError()
            }

        case _ as RUMAddCurrentViewErrorCommand:
            trackViewError()

        default:
            break
        }
        return true
    }

    // MARK: - RUMCommands Processing

    private func willStopUserAction(on command: RUMStopUserActionCommand) {
        sendActionEvent(completionTime: command.time, on: command)
    }

    private func startTrackingResource() {
        resourcesCount += 1
        activeResourcesCount += 1
    }

    private func stopTrackingResource() {
        activeResourcesCount -= 1
    }

    private func trackResourceError() {
        activeResourcesCount -= 1
        errorsCount += 1
    }

    private func trackViewError() {
        errorsCount += 1
    }

    // MARK: - Sending RUM Events

    private func sendActionEvent(completionTime: Date, on command: RUMCommand? = nil) {
        if let commandAttributes = command?.attributes {
            attributes.merge(rumCommandAttributes: commandAttributes)
        }

        let eventData = RUMActionEvent(
            date: actionStartTime.timeIntervalSince1970.toMilliseconds,
            application: .init(id: context.rumApplicationID),
            session: .init(id: context.sessionID.toString, type: "user"),
            view: .init(
                id: context.activeViewID.orNull.toString,
                url: context.activeViewURI ?? ""
            ),
            action: .init(
                id: actionUUID.toString,
                type: rawActionType(for: actionType),
                loadingTime: completionTime.timeIntervalSince(actionStartTime).toNanoseconds,
                resource: .init(count: resourcesCount),
                error: .init(count: errorsCount)
            ),
            dd: .init()
        )

        let event = dependencies.eventBuilder.createRUMEvent(with: eventData, attributes: attributes)
        dependencies.eventOutput.write(rumEvent: event)
    }

    // TODO: RUMM-517 Map `RUMUserActionType` to enum cases from generated models
    private func rawActionType(for actionType: RUMUserActionType) -> String {
        switch actionType {
        case .tap: return "tap"
        case .scroll: return "scroll"
        case .swipe: return "swipe"
        case .custom: return "custom"
        }
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
