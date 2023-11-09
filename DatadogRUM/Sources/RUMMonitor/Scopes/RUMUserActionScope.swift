/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

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
    internal let actionType: RUMActionType
    /// The name of this User Action.
    private(set) var name: String
    /// User Action attributes.
    private(set) var attributes: [AttributeKey: AttributeValue]

    /// This User Action's UUID.
    let actionUUID: RUMUUID
    /// The start time of this User Action.
    private let actionStartTime: Date

    /// Server time offset for date correction.
    ///
    /// The offset should be applied to event's timestamp for synchronizing
    /// local time with server time. This time interval value can be added to
    /// any date that needs to be synced. e.g:
    ///
    ///     date.addingTimeInterval(serverTimeOffset)
    private let serverTimeOffset: TimeInterval

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
    private let onActionEventSent: (RUMActionEvent) -> Void

    init(
        parent: RUMContextProvider,
        dependencies: RUMScopeDependencies,
        name: String,
        actionType: RUMActionType,
        attributes: [AttributeKey: AttributeValue],
        startTime: Date,
        serverTimeOffset: TimeInterval,
        isContinuous: Bool,
        onActionEventSent: @escaping (RUMActionEvent) -> Void
    ) {
        self.parent = parent
        self.dependencies = dependencies
        self.name = name
        self.actionType = actionType
        self.attributes = attributes
        self.actionUUID = dependencies.rumUUIDGenerator.generateUnique()
        self.actionStartTime = startTime
        self.serverTimeOffset = serverTimeOffset
        self.isContinuous = isContinuous
        self.lastActivityTime = startTime
        self.onActionEventSent = onActionEventSent
    }

    // MARK: - RUMContextProvider

    var context: RUMContext {
        // We currently only get the context from the parent scope (`RUMViewScope`) when it's still active (`viewScopes.last`).
        // This might change at some point and the following context might then hold the wrong active view's properties at that point as this is not checked inside `RUMViewScope.context`.
        return parent.context
    }

    // MARK: - RUMScope

    func process(command: RUMCommand, context: DatadogContext, writer: Writer) -> Bool {
        if let expirationTime = possibleExpirationTime(currentTime: command.time), allResourcesCompletedLoading() {
            sendActionEvent(completionTime: expirationTime, on: nil, context: context, writer: writer)
            return false
        }

        lastActivityTime = command.time
        switch command {
        case is RUMStartViewCommand, is RUMStopViewCommand:
            sendActionEvent(completionTime: command.time, on: command, context: context, writer: writer)
            return false
        case let command as RUMStopUserActionCommand:
            name = command.name ?? name
            sendActionEvent(completionTime: command.time, on: command, context: context, writer: writer)
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

    private func sendActionEvent(completionTime: Date, on command: RUMCommand?, context: DatadogContext, writer: Writer) {
        attributes.merge(rumCommandAttributes: command?.attributes)

        var frustrations: [RUMActionEvent.Action.Frustration.FrustrationType]? = nil
        if dependencies.trackFrustrations, errorsCount > 0, actionType == .tap {
            frustrations = [.errorTap]
        }

        let actionEvent = RUMActionEvent(
            dd: .init(
                action: nil,
                browserSdkVersion: nil,
                configuration: .init(sessionReplaySampleRate: nil, sessionSampleRate: Double(dependencies.sessionSampler.samplingRate)),
                session: .init(
                    plan: .plan1,
                    sessionPrecondition: nil
                )
            ),
            action: .init(
                crash: .init(count: 0),
                error: .init(count: errorsCount.toInt64),
                frustration: frustrations.map { .init(type: $0) },
                id: actionUUID.toRUMDataFormat,
                loadingTime: completionTime.timeIntervalSince(actionStartTime).toInt64Nanoseconds,
                longTask: .init(count: longTasksCount),
                resource: .init(count: resourcesCount.toInt64),
                target: .init(name: name),
                type: actionType.toRUMDataFormat
            ),
            application: .init(id: self.context.rumApplicationID),
            buildVersion: context.buildNumber,
            ciTest: dependencies.ciTest,
            connectivity: .init(context: context),
            context: .init(contextInfo: attributes),
            date: actionStartTime.addingTimeInterval(serverTimeOffset).timeIntervalSince1970.toInt64Milliseconds,
            device: .init(context: context, telemetry: dependencies.telemetry),
            display: nil,
            os: .init(context: context),
            parentView: nil,
            service: context.service,
            session: .init(
                hasReplay: context.hasReplay,
                id: self.context.sessionID.toRUMDataFormat,
                type: dependencies.sessionType
            ),
            source: .init(rawValue: context.source) ?? .ios,
            synthetics: dependencies.syntheticsTest,
            usr: .init(context: context),
            version: context.version,
            view: .init(
                id: self.context.activeViewID.orNull.toRUMDataFormat,
                inForeground: nil,
                name: self.context.activeViewName,
                referrer: nil,
                url: self.context.activeViewPath ?? ""
            )
        )

        if let event = dependencies.eventBuilder.build(from: actionEvent) {
            writer.write(value: event)
            onActionEventSent(event)
        }
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
