/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import DatadogInternal
import Foundation

internal class RUMViewScope_: RUMScope, RUMContextProvider {
    // MARK: - Initialization

    private unowned let parent: RUMContextProvider
    let dependencies: RUMScopeDependencies

    private let isInitialView: Bool

    let identity: ViewIdentifier
    let viewUUID: RUMUUID
    let viewPath: String
    let viewName: String
    let viewStartTime: Date
    let serverTimeOffset: TimeInterval

    private(set) var attributes: [AttributeKey: AttributeValue] = [:]
    private(set) var customTimings: [String: Int64] = [:]
    private(set) var featureFlags: [String: Encodable] = [:]

    /// Current version of this View, used for routing and `documentVersion`.
    /// Starts at 0; incremented in `process` before each send.
    /// version == 1 → send full RUMViewEvent; version > 1 → send RUMViewUpdateEvent.
    private var version: UInt = 0

    /// Placeholder for child resource scopes — always empty until child scope support is implemented.
    private(set) var resourceScopes: [String: RUMResourceScope] = [:]
    /// Placeholder for child user action scope — always nil until child scope support is implemented.
    private(set) var userActionScope: RUMUserActionScope?
    /// Internal view attributes (cross-platform) — storage placeholder until sendViewEvent is implemented.
    private(set) var internalAttributes: [AttributeKey: AttributeValue] = [:]

    private(set) var isActiveView = true
    private var didReceiveStartCommand = false
    private var needsViewUpdate = false

    init(
        isInitialView: Bool,
        parent: RUMContextProvider,
        dependencies: RUMScopeDependencies,
        identity: ViewIdentifier,
        path: String,
        name: String,
        customTimings: [String: Int64],
        startTime: Date,
        serverTimeOffset: TimeInterval
    ) {
        self.isInitialView = isInitialView
        self.parent = parent
        self.dependencies = dependencies
        self.identity = identity
        self.viewUUID = dependencies.rumUUIDGenerator.generateUnique()
        self.viewPath = path
        self.viewName = name
        self.customTimings = customTimings
        self.viewStartTime = startTime
        self.serverTimeOffset = serverTimeOffset
    }

    // MARK: - RUMContextProvider

    var context: RUMContext {
        var context = parent.context
        context.activeViewID = viewUUID
        context.activeViewPath = viewPath
        context.activeViewName = viewName
        context.activeUserActionID = userActionScope?.actionUUID
        return context
    }
}

// MARK: - RUMCommands Processing

extension RUMViewScope_ {
    func process(command: RUMCommand, context: DatadogContext, writer: Writer) -> Bool {
        needsViewUpdate = false

        let hasSentNoViewUpdatesYet = version == 0
        if isInitialView, hasSentNoViewUpdatesYet {
            needsViewUpdate = true
        }

        switch command {
        case is RUMApplicationStartCommand:
            didReceiveStartCommand = true

        case let command as RUMHandleAppLifecycleEventCommand:
            if command.event == .didEnterBackground && viewPath == RUMOffViewEventsHandlingRule.Constants.applicationLaunchViewURL {
                isActiveView = false
                needsViewUpdate = true
            } else if command.event == .willEnterForeground && viewPath == RUMOffViewEventsHandlingRule.Constants.backgroundViewURL {
                isActiveView = false
                needsViewUpdate = false
            }

        case is RUMStopSessionCommand:
            isActiveView = false
            needsViewUpdate = true

        case let command as RUMAddViewAttributesCommand where isActiveView:
            if command.areInternalAttributes {
                // TODO: RUM-16486 store in internalAttributes dict (prerequisite for sendViewEvent —
                // needed for CrossPlatformAttributes.customINVValue and Flutter FBC metric)
                break
            } else {
                attributes.merge(command.attributes) { $1 }
            }

        case let command as RUMRemoveViewAttributesCommand where isActiveView:
            command.keysToRemove.forEach { attributes.removeValue(forKey: $0) }

        case let command as RUMStartViewCommand where identity == command.identity:
            if didReceiveStartCommand {
                isActiveView = false
            }
            attributes.merge(command.attributes) { $1 }
            didReceiveStartCommand = true
            needsViewUpdate = true

        case let command as RUMStartViewCommand where identity != command.identity && isActiveView:
            isActiveView = false
            needsViewUpdate = true
            attributes = command.globalAttributes.merging(self.attributes) { $1 }

        case let command as RUMStopViewCommand where identity == command.identity:
            isActiveView = false
            needsViewUpdate = true
            attributes = command.globalAttributes.merging(self.attributes) { $1 }.merging(command.attributes) { $1 }

        case let command as RUMAddViewLoadingTime where isActiveView:
            attributes.merge(command.attributes) { $1 }
            needsViewUpdate = true // TODO: RUM-16486 honour command.overwrite like RUMViewScope

        case let command as RUMAddViewTimingCommand where isActiveView:
            attributes.merge(command.attributes) { $1 }
            customTimings[command.timingName] = command.time.timeIntervalSince(viewStartTime).dd.toInt64Nanoseconds
            needsViewUpdate = true

        case is RUMStartResourceCommand where isActiveView:
            break // TODO: RUM-16486 child resource scopes

        case is RUMStartUserActionCommand where isActiveView:
            break // TODO: RUM-16486 child action scopes

        case is RUMAddUserActionCommand where isActiveView:
            break // TODO: RUM-16486 child action scopes

        case is RUMErrorCommand where isActiveView:
            break // TODO: RUM-16486 error events

        case is RUMAddLongTaskCommand where isActiveView:
            break // TODO: RUM-16486 long task events

        case let command as RUMAddFeatureFlagEvaluationCommand where isActiveView:
            featureFlags[command.name] = command.value
            needsViewUpdate = true

        case is RUMUpdatePerformanceMetric where isActiveView:
            break // TODO: RUM-16486 performance metrics

        case _ as RUMOperationStepVitalCommand where isActiveView:
            needsViewUpdate = true

        default:
            break
        }

        if needsViewUpdate {
            version += 1
            if version == 1 {
                sendViewEvent(on: command, context: context, writer: writer)
            } else {
                sendViewUpdateEvent(on: command, context: context, writer: writer)
            }
        }

        // TODO: RUM-16486 change to `return !(!isActiveView && resourceScopes.isEmpty)` when child resource scopes are added
        return isActiveView
    }

    private func sendViewEvent(on command: RUMCommand, context: DatadogContext, writer: Writer) {
        // TODO: RUM-16486 build and write RUMViewEvent (full snapshot, same as RUMViewScope.sendViewUpdateEvent)
        // Prerequisite: add viewIndexInSession parameter to init (needed for event metadata)
        // Prerequisite: add internalAttributes storage (Fix 1 above)
    }

    private func sendViewUpdateEvent(on command: RUMCommand, context: DatadogContext, writer: Writer) {
        // TODO: RUM-16486 build and write RUMViewUpdateEvent
        // Prerequisite: add RUMSanitizableEvent conformance to RUMViewUpdateEvent
        // Prerequisite: add RUMViewUpdateEvent entry to RUMEventsMapper
    }
}
