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
    private(set) var internalAttributes: [AttributeKey: AttributeValue] = [:]

    /// The last full view event sent through the mapper.
    /// - `nil`      → no event has been sent yet → next send writes a full `RUMViewEvent`.
    /// - non-`nil`  → at least one event was sent → next send projects a `RUMViewUpdateEvent`.
    ///
    /// Storing the mapper-transformed event allows the projection to honour any scrubbing
    /// applied by the user's `viewEventMapper` on the first event.
    private var viewEvent: RUMViewEvent?

    /// Current documentVersion, incremented before each send and reverted if the mapper drops the event.
    private var version: UInt = 0

    /// Placeholder for child resource scopes — always empty until child scope support is implemented.
    private(set) var resourceScopes: [String: RUMResourceScope] = [:]
    /// Placeholder for child user action scope — always nil until child scope support is implemented.
    private(set) var userActionScope: RUMUserActionScope?

    private(set) var isActiveView = true {
        didSet {
            if oldValue && !isActiveView {
                networkSettledMetric.trackViewWasStopped()
                interactionToNextViewMetric?.trackViewComplete(viewID: viewUUID)
            }
        }
    }
    private var didReceiveStartCommand = false
    private var needsViewUpdate = false

    private var hasReplay = false
    private var viewLoadingTime: TimeInterval?
    private var actionsCount: UInt = 0
    private var errorsCount: UInt = 0
    private var resourcesCount: UInt = 0
    private var longTasksCount: Int64 = 0
    private var frozenFramesCount: Int64 = 0
    private var frustrationCount: Int64 = 0

    private let networkSettledMetric: TNSMetricTracking
    private let interactionToNextViewMetric: INVMetricTracking?
    private let viewIndexInSession: Int
    private var accessibilityState: AccessibilityInfo?
    private var accessibilityReader: AccessibilityReading?

    init(
        isInitialView: Bool,
        parent: RUMContextProvider,
        dependencies: RUMScopeDependencies,
        identity: ViewIdentifier,
        path: String,
        name: String,
        customTimings: [String: Int64],
        startTime: Date,
        serverTimeOffset: TimeInterval,
        interactionToNextViewMetric: INVMetricTracking? = nil,
        viewIndexInSession: Int = 0
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
        self.interactionToNextViewMetric = interactionToNextViewMetric
        self.viewIndexInSession = viewIndexInSession
        self.networkSettledMetric = dependencies.networkSettledMetricFactory(startTime, name)
        self.accessibilityReader = dependencies.accessibilityReader
        interactionToNextViewMetric?.trackViewStart(at: startTime, name: name, viewID: viewUUID)
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
                internalAttributes.merge(command.attributes) { $1 }
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
            if viewLoadingTime == nil {
                viewLoadingTime = command.time.timeIntervalSince(viewStartTime)
                needsViewUpdate = true
            } else if command.overwrite {
                viewLoadingTime = command.time.timeIntervalSince(viewStartTime)
                needsViewUpdate = true
            }

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
        if let hasContextReplay = context.hasReplay {
            hasReplay = hasReplay || hasContextReplay
        }

        version += 1

        let effectiveAttributes: [AttributeKey: AttributeValue]
        if isActiveView {
            effectiveAttributes = command.globalAttributes.merging(self.attributes) { $1 }
        } else {
            effectiveAttributes = self.attributes
        }

        let isActive = isActiveView || !resourceScopes.isEmpty
        let timeSpent = max(RUMViewScope.Constants.minimumTimeSpent, command.time.timeIntervalSince(viewStartTime))
        let networkSettledTime = networkSettledMetric.value(with: context.applicationStateHistory)
        var interactionToNextViewTime = interactionToNextViewMetric?.value(for: viewUUID) ?? .failure(.disabled)
        if interactionToNextViewTime == .failure(.disabled),
           let customInvValue = internalAttributes[CrossPlatformAttributes.customINVValue] as? (any BinaryInteger),
           let customInvValue = Int64(exactly: customInvValue) {
            interactionToNextViewTime = .success(TimeInterval.ddFromNanoseconds(customInvValue))
        }

        let performance: RUMViewEvent.View.Performance?
        if let fbcMetric = internalAttributes[CrossPlatformAttributes.flutterFirstBuildComplete] as? (any BinaryInteger),
           let fbcValue = Int64(exactly: fbcMetric) {
            performance = .init(cls: nil, fbc: .init(timestamp: fbcValue), fcp: nil, fid: nil, inp: nil, lcp: nil)
        } else {
            performance = nil
        }

        let currentAccessibilityState = accessibilityReader?.state
        var accessibility: RUMViewEvent.View.Accessibility?
        if accessibilityState == nil {
            accessibility = currentAccessibilityState?.rumViewAccessibility
        } else if currentAccessibilityState != accessibilityState {
            accessibility = currentAccessibilityState?.differences(from: accessibilityState).rumViewAccessibility
        }
        accessibilityState = currentAccessibilityState

        let sessionReplayConfig = context.additionalContext(ofType: SessionReplayCoreContext.Configuration.self)

        let fullEvent = RUMViewEvent(
            dd: .init(
                browserSdkVersion: nil,
                cls: nil,
                configuration: .init(
                    profilingSampleRate: nil,
                    sessionReplaySampleRate: sessionReplayConfig.map { Double($0.sampleRate) },
                    sessionSampleRate: Double(dependencies.samplingRate),
                    startSessionReplayRecordingManually: sessionReplayConfig?.startRecordingManually,
                    traceSampleRate: dependencies.distributedTracingSampleRate.map(Double.init)
                ),
                documentVersion: version.toInt64,
                pageStates: nil,
                replayStats: .init(
                    recordsCount: context.recordsCountByViewID[viewUUID.toRUMDataFormat],
                    segmentsCount: nil,
                    segmentsTotalRawSize: nil
                ),
                session: .init(
                    plan: .plan1,
                    sessionPrecondition: self.context.sessionPrecondition
                )
            ),
            account: .init(context: context),
            application: .init(currentLocale: context.localeInfo.currentLocale, id: self.context.rumApplicationID),
            buildId: context.buildId,
            buildVersion: context.buildNumber,
            ciTest: dependencies.ciTest,
            connectivity: .init(context: context),
            container: nil,
            context: .init(contextInfo: effectiveAttributes),
            date: viewStartTime.addingTimeInterval(serverTimeOffset).timeIntervalSince1970.dd.toInt64Milliseconds,
            ddtags: context.ddTags,
            device: context.normalizedDevice(),
            display: nil,
            featureFlags: .init(featureFlagsInfo: featureFlags),
            os: context.os,
            privacy: nil,
            service: context.service,
            session: .init(
                hasReplay: hasReplay,
                id: self.context.sessionID.toRUMDataFormat,
                isActive: self.context.isSessionActive,
                sampledForReplay: nil,
                type: dependencies.sessionType
            ),
            source: .init(rawValue: context.source) ?? .ios,
            synthetics: dependencies.syntheticsTest,
            usr: .init(context: context),
            version: context.version,
            view: .init(
                accessibility: accessibility,
                action: .init(count: actionsCount.toInt64),
                cpuTicksCount: nil,
                cpuTicksPerSecond: nil,
                crash: .init(count: 0),
                cumulativeLayoutShift: nil,
                cumulativeLayoutShiftTargetSelector: nil,
                cumulativeLayoutShiftTime: nil,
                customTimings: .init(customTimingsInfo: customTimings.reduce(into: [:]) { acc, element in
                    acc[sanitizeCustomTimingName(customTiming: element.key)] = element.value
                }),
                domComplete: nil,
                domContentLoaded: nil,
                domInteractive: nil,
                error: .init(count: errorsCount.toInt64),
                firstByte: nil,
                firstContentfulPaint: nil,
                firstInputDelay: nil,
                firstInputTargetSelector: nil,
                firstInputTime: nil,
                flutterBuildTime: nil,
                flutterRasterTime: nil,
                freezeRate: nil,
                frozenFrame: .init(count: frozenFramesCount),
                frustration: .init(count: frustrationCount),
                id: viewUUID.toRUMDataFormat,
                inForegroundPeriods: nil,
                interactionToNextPaint: nil,
                interactionToNextPaintTargetSelector: nil,
                interactionToNextPaintTime: nil,
                interactionToNextViewTime: interactionToNextViewTime.value?.dd.toInt64Nanoseconds,
                isActive: isActive,
                isSlowRendered: false,
                jsRefreshRate: nil,
                largestContentfulPaint: nil,
                largestContentfulPaintTargetSelector: nil,
                loadEvent: nil,
                loadingTime: viewLoadingTime?.dd.toInt64Nanoseconds,
                loadingType: nil,
                longTask: .init(count: longTasksCount),
                memoryAverage: nil,
                memoryMax: nil,
                name: viewName,
                networkSettledTime: networkSettledTime.value?.dd.toInt64Nanoseconds,
                performance: performance,
                referrer: nil,
                refreshRateAverage: nil,
                refreshRateMin: nil,
                resource: .init(count: resourcesCount.toInt64),
                slowFrames: nil,
                slowFramesRate: nil,
                timeSpent: timeSpent.dd.toInt64Nanoseconds,
                url: viewPath
            )
        )

        guard let mappedEvent = dependencies.eventBuilder.build(from: fullEvent) else {
            version -= 1
            return
        }

        if let previousEvent = viewEvent {
            let update = previousEvent.update(from: mappedEvent)
            viewEvent = mappedEvent
            writer.write(value: update)
        } else {
            viewEvent = mappedEvent
            writer.write(value: mappedEvent, metadata: mappedEvent.metadata(viewIndexInSession: viewIndexInSession))
        }
        dependencies.fatalErrorContext.view = mappedEvent
    }

    private func sanitizeCustomTimingName(customTiming: String) -> String {
        let sanitized = customTiming.replacingOccurrences(of: "[^a-zA-Z0-9_.@$-]", with: "_", options: .regularExpression)
        if customTiming != sanitized {
            DD.logger.warn("Custom timing '\(customTiming)' was modified to '\(sanitized)' to match Datadog constraints.")
        }
        return sanitized
    }
}

private extension Result {
    var value: Success? {
        switch self {
        case .success(let success): return success
        case .failure: return nil
        }
    }
}
