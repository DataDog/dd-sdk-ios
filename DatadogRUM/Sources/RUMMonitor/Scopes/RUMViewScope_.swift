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

    /// The last full view event sent through the mapper.
    /// - `nil`      → no event has been sent yet → next send writes a full `RUMViewEvent`.
    /// - non-`nil`  → at least one event was sent → next send projects a `RUMViewUpdateEvent`.
    ///
    /// Storing the mapper-transformed event allows the projection to honour any scrubbing
    /// applied by the user's `viewEventMapper` on the first event.
    private var viewEvent: RUMViewEvent?

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

        if isInitialView, viewEvent == nil {
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
            sendViewEvent(on: command, context: context, writer: writer)
        }

        // TODO: RUM-16486 change to `return !(!isActiveView && resourceScopes.isEmpty)` when child resource scopes are added
        return isActiveView
    }

    /// Builds a full `RUMViewEvent`, runs it through the view mapper, then:
    /// - writes it directly as `RUMViewEvent`  when `viewEvent == nil` (first send), or
    /// - projects it to `RUMViewUpdateEvent`   when `viewEvent != nil` (subsequent sends).
    ///
    /// In both cases the mapped event is stored in `viewEvent` for future projections.
    private func sendViewEvent(on command: RUMCommand, context: DatadogContext, writer: Writer) {
        // TODO: RUM-16486 build RUMViewEvent from current scope state (port from RUMViewScope.sendViewUpdateEvent)
        // Prerequisite: add viewIndexInSession parameter to init (needed for event metadata)
        // Prerequisite: populate internalAttributes via RUMAddViewAttributesCommand

        // --- Pseudocode for when the build is implemented ---
        //
        // let fullEvent = buildRUMViewEvent(on: command, context: context)
        //
        // guard let mappedEvent = dependencies.eventBuilder.build(from: fullEvent) else {
        //     return  // mapper dropped it; viewEvent unchanged so documentVersion doesn't advance
        // }
        //
        // let isFirstEvent = (viewEvent == nil)  // capture before updating stored state
        //
        // if isFirstEvent {
        //     viewEvent = mappedEvent
        //     writer.write(value: mappedEvent, ...)                   // full RUMViewEvent (documentVersion = 1)
        // } else {
        //     let update = viewEvent!.update(from: mappedEvent)       // self provides documentVersion (+1), event wins all fields
        //     viewEvent = mappedEvent
        //     writer.write(value: update, ...)                        // RUMViewUpdateEvent
        // }
    }
}

// RUMViewEvent.update(from:) is implemented in RUMViewEvent+ViewUpdateProjection.swift
