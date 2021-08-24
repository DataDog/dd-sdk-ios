/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

internal class RUMViewScope: RUMScope, RUMContextProvider {
    struct Constants {
        static let backgroundViewURL = "com/datadog/background/view"
        static let backgroundViewName = "Background"
    }

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
    let viewStartTime: Date
    /// Date correction to server time.
    private let dateCorrection: DateCorrection
    /// Tells if this View is the active one.
    /// `true` for every new started View.
    /// `false` if the View was stopped or any other View was started.
    private(set) var isActiveView = true
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

    /// Whether or not the current call to `process(command:)` should trigger a `sendViewEvent()` with an update.
    /// It can be toggled from inside `RUMResourceScope`/`RUMUserActionScope` callbacks, as they are called from processing `RUMCommand`s inside `process()`.
    private var needsViewUpdate = false

    /// Integration with Crash Reporting. It updates the context of crash reporter with last `RUMViewEvent` information.
    /// `nil` if Crash Reporting feature is not enabled.
    private let crashContextIntegration: RUMWithCrashContextIntegration?

    private let vitalInfoSampler: VitalInfoSampler

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
        self.crashContextIntegration = RUMWithCrashContextIntegration()

        self.vitalInfoSampler = VitalInfoSampler(
            cpuReader: dependencies.vitalCPUReader,
            memoryReader: dependencies.vitalMemoryReader,
            refreshRateReader: dependencies.vitalRefreshRateReader
        )
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
        needsViewUpdate = false

        // Propagate to User Action scope
        userActionScope = manage(childScope: userActionScope, byPropagatingCommand: command)

        // Apply side effects
        switch command {
        // View commands
        case let command as RUMStartViewCommand where identity.equals(command.identity):
            if didReceiveStartCommand {
                // This is the case of duplicated "start" command. We know that the Session scope has created another instance of
                // the `RUMViewScope` for tracking this View, so we mark this one as inactive.
                isActiveView = false
            }
            didReceiveStartCommand = true
            if command.isInitialView {
                actionsCount += 1
                if !sendApplicationStartAction(on: command) {
                    actionsCount -= 1
                    break
                }
            }
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
            } else {
                reportActionDropped(type: command.actionType, name: command.name)
            }
        case let command as RUMAddUserActionCommand where isActiveView:
            if userActionScope == nil {
                addDiscreteUserAction(on: command)
            } else if command.actionType == .custom {
                // still let it go, just instantly without any dependencies
                sendDiscreteCustomUserAction(on: command)
            } else {
                reportActionDropped(type: command.actionType, name: command.name)
            }

        // Error command
        case let command as RUMAddCurrentViewErrorCommand where isActiveView:
            errorsCount += 1
            if sendErrorEvent(on: command) {
                needsViewUpdate = true
            } else {
                errorsCount -= 1
            }

        default:
            break
        }

        // Propagate to Resource scopes
        if let resourceCommand = command as? RUMResourceCommand {
            resourceScopes[resourceCommand.resourceKey] = manage(
                childScope: resourceScopes[resourceCommand.resourceKey],
                byPropagatingCommand: resourceCommand
            )
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
            spanContext: command.spanContext,
            onResourceEventSent: { [weak self] in
                self?.resourcesCount += 1
                self?.needsViewUpdate = true
            },
            onErrorEventSent: { [weak self] in
                self?.errorsCount += 1
                self?.needsViewUpdate = true
            }
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
            isContinuous: true,
            onActionEventSent: { [weak self] in
                self?.actionsCount += 1
                self?.needsViewUpdate = true
            }
        )
    }

    private func createDiscreteUserActionScope(on command: RUMAddUserActionCommand) -> RUMUserActionScope {
        return RUMUserActionScope(
            parent: self,
            dependencies: dependencies,
            name: command.name,
            actionType: command.actionType,
            attributes: command.attributes,
            startTime: command.time,
            dateCorrection: dateCorrection,
            isContinuous: false,
            onActionEventSent: { [weak self] in
                self?.actionsCount += 1
                self?.needsViewUpdate = true
            }
        )
    }

    private func addDiscreteUserAction(on command: RUMAddUserActionCommand) {
        userActionScope = createDiscreteUserActionScope(on: command)
    }

    private func sendDiscreteCustomUserAction(on command: RUMAddUserActionCommand) {
        let customActionScope = createDiscreteUserActionScope(on: command)
        _ = customActionScope.process(
            command: RUMStopUserActionCommand(
                                    time: command.time,
                                    attributes: [:],
                                    actionType: .custom,
                                    name: nil
            )
        )
    }

    private func reportActionDropped(type: RUMUserActionType, name: String) {
        userLogger.warn(
            """
            RUM Action '\(type)' on '\(name)' was dropped, because another action is still active for the same view.
            """
        )
    }

    // MARK: - Sending RUM Events

    private func sendApplicationStartAction(on command: RUMCommand) -> Bool {
        let eventData = RUMActionEvent(
            dd: .init(
                session: .init(plan: .plan1)
            ),
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
            context: nil,
            date: dateCorrection.applying(to: viewStartTime).timeIntervalSince1970.toInt64Milliseconds,
            service: nil,
            session: .init(hasReplay: nil, id: context.sessionID.toRUMDataFormat, type: .user),
            usr: dependencies.userInfoProvider.current,
            view: .init(
                id: viewUUID.toRUMDataFormat,
                inForeground: nil,
                name: viewName,
                referrer: nil,
                url: viewPath
            )
        )

        if let event = dependencies.eventBuilder.createRUMEvent(with: eventData, attributes: command.attributes) {
            dependencies.eventOutput.write(rumEvent: event)
            return true
        }
        return false
    }

    private func sendViewUpdateEvent(on command: RUMCommand) {
        version += 1
        attributes.merge(rumCommandAttributes: command.attributes)

        let timeSpent = command.time.timeIntervalSince(viewStartTime)

        let cpuInfo = vitalInfoSampler.cpu
        let memoryInfo = vitalInfoSampler.memory
        let refreshRateInfo = vitalInfoSampler.refreshRate

        let eventData = RUMViewEvent(
            dd: .init(
                documentVersion: version.toInt64,
                session: .init(plan: .plan1)
            ),
            application: .init(id: context.rumApplicationID),
            connectivity: dependencies.connectivityInfoProvider.current,
            context: nil,
            date: dateCorrection.applying(to: viewStartTime).timeIntervalSince1970.toInt64Milliseconds,
            service: nil,
            session: .init(hasReplay: nil, id: context.sessionID.toRUMDataFormat, type: .user),
            usr: dependencies.userInfoProvider.current,
            view: .init(
                action: .init(count: actionsCount.toInt64),
                cpuTicksCount: cpuInfo.greatestDiff,
                cpuTicksPerSecond: cpuInfo.greatestDiff?.divideIfNotZero(by: Double(timeSpent)),
                crash: nil,
                cumulativeLayoutShift: nil,
                customTimings: customTimings.reduce(into: [:]) { acc, element in
                    acc[sanitizeCustomTimingName(customTiming: element.key)] = element.value
                },
                domComplete: nil,
                domContentLoaded: nil,
                domInteractive: nil,
                error: .init(count: errorsCount.toInt64),
                firstContentfulPaint: nil,
                firstInputDelay: nil,
                firstInputTime: nil,
                id: viewUUID.toRUMDataFormat,
                inForegroundPeriods: nil,
                isActive: isActiveView,
                largestContentfulPaint: nil,
                loadEvent: nil,
                loadingTime: nil,
                loadingType: nil,
                longTask: nil,
                memoryAverage: memoryInfo.meanValue,
                memoryMax: memoryInfo.maxValue,
                name: viewName,
                referrer: nil,
                refreshRateAverage: refreshRateInfo.meanValue,
                refreshRateMin: refreshRateInfo.minValue,
                resource: .init(count: resourcesCount.toInt64),
                timeSpent: timeSpent.toInt64Nanoseconds,
                url: viewPath
            )
        )

        if let event = dependencies.eventBuilder.createRUMEvent(with: eventData, attributes: attributes) {
            dependencies.eventOutput.write(rumEvent: event)
            crashContextIntegration?.update(lastRUMViewEvent: event)
        } else {
            version -= 1
        }
    }

    private func sendErrorEvent(on command: RUMAddCurrentViewErrorCommand) -> Bool {
        attributes.merge(rumCommandAttributes: command.attributes)

        let eventData = RUMErrorEvent(
            dd: .init(
                session: .init(plan: .plan1)
            ),
            action: context.activeUserActionID.flatMap { rumUUID in
                .init(id: rumUUID.toRUMDataFormat)
            },
            application: .init(id: context.rumApplicationID),
            connectivity: dependencies.connectivityInfoProvider.current,
            context: nil,
            date: dateCorrection.applying(to: command.time).timeIntervalSince1970.toInt64Milliseconds,
            error: .init(
                handling: nil,
                handlingStack: nil,
                id: nil,
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
                inForeground: nil,
                name: context.activeViewName,
                referrer: nil,
                url: context.activeViewPath ?? ""
            )
        )

        if let event = dependencies.eventBuilder.createRUMEvent(with: eventData, attributes: attributes) {
            dependencies.eventOutput.write(rumEvent: event)
            return true
        }
        return false
    }

    private func sanitizeCustomTimingName(customTiming: String) -> String {
        let sanitized = customTiming.replacingOccurrences(of: "[^a-zA-Z0-9_.@$-]", with: "_", options: .regularExpression)

        if customTiming != sanitized {
            userLogger.warn(
                """
                Custom timing '\(customTiming)' was modified to '\(sanitized)' to match Datadog constraints.
                """
            )
        }

        return sanitized
    }
}
