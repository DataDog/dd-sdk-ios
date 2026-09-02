/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import DatadogInternal
import Foundation

// MARK: - RUMViewEvent → RUMViewUpdateEvent Delta Projection

extension RUMViewEvent {
    /// Produces a `RUMViewUpdateEvent` that contains only the fields that changed.
    ///
    /// - `self` is the previously sent `RUMViewEvent` (stored in `RUMViewScope.lastSentViewEvent`).
    /// - `event` is the newly built `RUMViewEvent` (post-mapper). Its values win.
    /// - Fields equal between `self` and `event` are set to `nil` (meaning "unchanged").
    ///   `dd` is always forwarded wholesale from `event`.
    ///
    func update(from event: RUMViewEvent) -> RUMViewUpdateEvent {
        RUMViewUpdateEvent(
            dd: .init(event.dd),
            account: diff(account, event.account),
            application: .init(event.application),
            buildId: diff(buildId, event.buildId),
            buildVersion: diff(buildVersion, event.buildVersion),
            ciTest: diff(ciTest, event.ciTest),
            connectivity: diff(connectivity, event.connectivity),
            container: diffMap(container, event.container, RUMViewUpdateEvent.Container.init),
            context: diff(context, event.context),
            date: event.date,
            ddtags: diff(ddtags, event.ddtags),
            device: diff(device, event.device),
            display: diffMap(display, event.display, RUMViewUpdateEvent.Display.init),
            featureFlags: diffMap(featureFlags, event.featureFlags, RUMViewUpdateEvent.FeatureFlags.init),
            os: diff(os, event.os),
            privacy: diffMap(privacy, event.privacy, RUMViewUpdateEvent.Privacy.init),
            service: diff(service, event.service),
            session: .init(event.session),
            source: diff(source, event.source).map { .init($0) },
            stream: diffMap(stream, event.stream, RUMViewUpdateEvent.Stream.init),
            synthetics: diff(synthetics, event.synthetics),
            tab: diffMap(tab, event.tab, RUMViewUpdateEvent.TAB.init),
            usr: diff(usr, event.usr),
            version: diff(version, event.version),
            view: .init(old: view, new: event.view)
        )
    }
}

// MARK: - Diff helpers

private func diff<T: Equatable>(_ old: T?, _ new: T?) -> T? { old == new ? nil : new }
private func diffMap<T: Equatable, U>(_ old: T?, _ new: T?, _ transform: (T) -> U) -> U? {
    diff(old, new).map(transform)
}

private func diffMap<T: Equatable, U>(_ old: T?, _ new: T?, _ transform: (T?, T) -> U) -> U? {
    diff(old, new).map { transform(old, $0) }
}

// MARK: - Enum init extensions (safe conversion, no force-unwrap)

private extension RUMViewUpdateEvent.Source {
    init(_ s: RUMViewEvent.Source) {
        switch s {
        case .android: self = .android
        case .ios: self = .ios
        case .browser: self = .browser
        case .flutter: self = .flutter
        case .reactNative: self = .reactNative
        case .roku: self = .roku
        case .unity: self = .unity
        case .kotlinMultiplatform: self = .kotlinMultiplatform
        case .electron: self = .electron
        case .cpp: self = .cpp
        case .maui: self = .maui
        }
    }
}

private extension RUMViewUpdateEvent.Container.Source {
    init(_ s: RUMViewEvent.Container.Source) {
        switch s {
        case .android: self = .android
        case .ios: self = .ios
        case .browser: self = .browser
        case .flutter: self = .flutter
        case .reactNative: self = .reactNative
        case .roku: self = .roku
        case .unity: self = .unity
        case .kotlinMultiplatform: self = .kotlinMultiplatform
        case .electron: self = .electron
        case .cpp: self = .cpp
        case .maui: self = .maui
        }
    }
}

private extension RUMViewUpdateEvent.Privacy.ReplayLevel {
    init(_ s: RUMViewEvent.Privacy.ReplayLevel) {
        switch s {
        case .allow: self = .allow
        case .mask: self = .mask
        case .maskUserInput: self = .maskUserInput
        }
    }
}

private extension RUMViewUpdateEvent.DD.Session.Plan {
    init(_ s: RUMViewEvent.DD.Session.Plan) {
        switch s {
        case .plan1: self = .plan1
        case .plan2: self = .plan2
        }
    }
}

private extension RUMViewUpdateEvent.View.LoadingType {
    init(_ s: RUMViewEvent.View.LoadingType) {
        switch s {
        case .initialLoad: self = .initialLoad
        case .routeChange: self = .routeChange
        case .activityDisplay: self = .activityDisplay
        case .activityRedisplay: self = .activityRedisplay
        case .fragmentDisplay: self = .fragmentDisplay
        case .fragmentRedisplay: self = .fragmentRedisplay
        case .viewControllerDisplay: self = .viewControllerDisplay
        case .viewControllerRedisplay: self = .viewControllerRedisplay
        case .sessionRenewal: self = .sessionRenewal
        case .bfCache: self = .bfCache
        }
    }
}

// MARK: - DD projection

private extension RUMViewUpdateEvent.DD {
    init(_ s: RUMViewEvent.DD) {
        self.init(
            browserSdkVersion: s.browserSdkVersion,
            cls: s.cls.map { .init($0) },
            configuration: s.configuration.map { .init($0) },
            documentVersion: s.documentVersion,
            pageStates: s.pageStates.map { $0.map { .init($0) } },
            profiling: s.profiling,
            replayStats: s.replayStats.map { .init($0) },
            sdkName: s.sdkName,
            session: s.session.map { .init($0) }
        )
    }
}

private extension RUMViewUpdateEvent.DD.CLS {
    init(_ s: RUMViewEvent.DD.CLS) {
        self.init(devicePixelRatio: s.devicePixelRatio)
    }
}

private extension RUMViewUpdateEvent.DD.Configuration {
    init(_ s: RUMViewEvent.DD.Configuration) {
        self.init(
            profilingSampleRate: s.profilingSampleRate,
            remoteConfigurationId: s.remoteConfigurationId,
            sessionReplayExperimentalFeatures: s.sessionReplayExperimentalFeatures,
            sessionReplaySampleRate: s.sessionReplaySampleRate,
            sessionSampleRate: s.sessionSampleRate,
            startSessionReplayRecordingManually: s.startSessionReplayRecordingManually,
            traceSampleRate: s.traceSampleRate
        )
    }
}

private extension RUMViewUpdateEvent.DD.PageStates {
    init(_ s: RUMViewEvent.DD.PageStates) {
        self.init(start: s.start, state: .init(s.state))
    }
}

private extension RUMViewUpdateEvent.DD.PageStates.State {
    init(_ s: RUMViewEvent.DD.PageStates.State) {
        switch s {
        case .active: self = .active
        case .passive: self = .passive
        case .hidden: self = .hidden
        case .frozen: self = .frozen
        case .terminated: self = .terminated
        }
    }
}

private extension RUMViewUpdateEvent.DD.ReplayStats {
    init(_ s: RUMViewEvent.DD.ReplayStats) {
        self.init(
            recordsCount: s.recordsCount,
            segmentsCount: s.segmentsCount,
            segmentsTotalRawSize: s.segmentsTotalRawSize
        )
    }
}

private extension RUMViewUpdateEvent.DD.Session {
    init(_ s: RUMViewEvent.DD.Session) {
        self.init(
            plan: s.plan.map { .init($0) },
            sessionPrecondition: s.sessionPrecondition
        )
    }
}

// MARK: - Top-level type projections

private extension RUMViewUpdateEvent.Application {
    init(_ s: RUMViewEvent.Application) {
        self.init(currentLocale: s.currentLocale, id: s.id)
    }
}

private extension RUMViewUpdateEvent.Container {
    init(_ s: RUMViewEvent.Container) {
        self.init(source: .init(s.source), view: .init(s.view))
    }
}

private extension RUMViewUpdateEvent.Container.View {
    init(_ s: RUMViewEvent.Container.View) { self.init(id: s.id) }
}

private extension RUMViewUpdateEvent.Display {
    init(_ s: RUMViewEvent.Display) {
        self.init(scroll: s.scroll.map { .init($0) }, viewport: s.viewport.map { .init($0) })
    }
}

private extension RUMViewUpdateEvent.Display.Scroll {
    init(_ s: RUMViewEvent.Display.Scroll) {
        self.init(
            maxDepth: s.maxDepth,
            maxDepthScrollTop: s.maxDepthScrollTop,
            maxScrollHeight: s.maxScrollHeight,
            maxScrollHeightTime: s.maxScrollHeightTime
        )
    }
}

private extension RUMViewUpdateEvent.Display.Viewport {
    init(_ s: RUMViewEvent.Display.Viewport) { self.init(height: s.height, width: s.width) }
}

private extension RUMViewUpdateEvent.FeatureFlags {
    init(_ s: RUMViewEvent.FeatureFlags) { self.init(featureFlagsInfo: s.featureFlagsInfo) }
}

private extension RUMViewUpdateEvent.Privacy {
    init(_ s: RUMViewEvent.Privacy) { self.init(replayLevel: .init(s.replayLevel)) }
}

private extension RUMViewUpdateEvent.Session {
    init(_ s: RUMViewEvent.Session) {
        self.init(
            hasReplay: s.hasReplay,
            id: s.id,
            isActive: s.isActive,
            sampledForReplay: s.sampledForReplay,
            type: s.type
        )
    }
}

private extension RUMViewUpdateEvent.Stream {
    init(_ s: RUMViewEvent.Stream) {
        self.init(
            bitrate: s.bitrate,
            completionPercent: s.completionPercent,
            duration: s.duration,
            format: s.format,
            fps: s.fps,
            id: s.id,
            resolution: s.resolution,
            timestamp: s.timestamp,
            watchTime: s.watchTime
        )
    }
}

private extension RUMViewUpdateEvent.TAB {
    init(_ s: RUMViewEvent.TAB) { self.init(id: s.id) }
}

// MARK: - View delta projection

private extension RUMViewUpdateEvent.View {
    init(old: RUMViewEvent.View, new: RUMViewEvent.View) {
        self.init(
            accessibility: diffMap(old.accessibility, new.accessibility, RUMViewUpdateEvent.View.Accessibility.init),
            action: diff(old.action, new.action).map { .init($0) },
            cpuTicksCount: diff(old.cpuTicksCount, new.cpuTicksCount),
            cpuTicksPerSecond: diff(old.cpuTicksPerSecond, new.cpuTicksPerSecond),
            crash: diff(old.crash, new.crash).map { .init($0) },
            cumulativeLayoutShift: diff(old.cumulativeLayoutShift, new.cumulativeLayoutShift),
            cumulativeLayoutShiftTargetSelector: diff(old.cumulativeLayoutShiftTargetSelector, new.cumulativeLayoutShiftTargetSelector),
            cumulativeLayoutShiftTime: diff(old.cumulativeLayoutShiftTime, new.cumulativeLayoutShiftTime),
            customTimings: diff(old.customTimings, new.customTimings).map { .init($0) },
            domComplete: diff(old.domComplete, new.domComplete),
            domContentLoaded: diff(old.domContentLoaded, new.domContentLoaded),
            domInteractive: diff(old.domInteractive, new.domInteractive),
            error: diff(old.error, new.error).map { .init($0) },
            firstByte: diff(old.firstByte, new.firstByte),
            firstContentfulPaint: diff(old.firstContentfulPaint, new.firstContentfulPaint),
            firstInputDelay: diff(old.firstInputDelay, new.firstInputDelay),
            firstInputTargetSelector: diff(old.firstInputTargetSelector, new.firstInputTargetSelector),
            firstInputTime: diff(old.firstInputTime, new.firstInputTime),
            flutterBuildTime: diff(old.flutterBuildTime, new.flutterBuildTime).map { .init($0) },
            flutterRasterTime: diff(old.flutterRasterTime, new.flutterRasterTime).map { .init($0) },
            freezeRate: diff(old.freezeRate, new.freezeRate),
            frozenFrame: diff(old.frozenFrame, new.frozenFrame).map { .init($0) },
            frustration: diff(old.frustration, new.frustration).map { .init($0) },
            id: new.id,
            inForegroundPeriods: diff(old.inForegroundPeriods, new.inForegroundPeriods).map { $0.map { .init($0) } },
            interactionToNextPaint: diff(old.interactionToNextPaint, new.interactionToNextPaint),
            interactionToNextPaintTargetSelector: diff(old.interactionToNextPaintTargetSelector, new.interactionToNextPaintTargetSelector),
            interactionToNextPaintTime: diff(old.interactionToNextPaintTime, new.interactionToNextPaintTime),
            interactionToNextViewTime: diff(old.interactionToNextViewTime, new.interactionToNextViewTime),
            isActive: diff(old.isActive, new.isActive),
            isSlowRendered: diff(old.isSlowRendered, new.isSlowRendered),
            jsRefreshRate: diff(old.jsRefreshRate, new.jsRefreshRate).map { .init($0) },
            largestContentfulPaint: diff(old.largestContentfulPaint, new.largestContentfulPaint),
            largestContentfulPaintTargetSelector: diff(old.largestContentfulPaintTargetSelector, new.largestContentfulPaintTargetSelector),
            loadEvent: diff(old.loadEvent, new.loadEvent),
            loadingTime: diff(old.loadingTime, new.loadingTime),
            loadingType: diff(old.loadingType, new.loadingType).map { .init($0) },
            longTask: diff(old.longTask, new.longTask).map { .init($0) },
            memoryAverage: diff(old.memoryAverage, new.memoryAverage),
            memoryMax: diff(old.memoryMax, new.memoryMax),
            name: diff(old.name, new.name),
            networkSettledTime: diff(old.networkSettledTime, new.networkSettledTime),
            performance: diff(old.performance, new.performance).map { .init($0) },
            referrer: diff(old.referrer, new.referrer),
            refreshRateAverage: diff(old.refreshRateAverage, new.refreshRateAverage),
            refreshRateMin: diff(old.refreshRateMin, new.refreshRateMin),
            resource: diff(old.resource, new.resource).map { .init($0) },
            slowFrames: diff(old.slowFrames, new.slowFrames).map { $0.map { .init($0) } },
            slowFramesRate: diff(old.slowFramesRate, new.slowFramesRate),
            timeSpent: diff(old.timeSpent, new.timeSpent),
            url: new.url
        )
    }
}

// MARK: - View sub-struct projections

private extension RUMViewUpdateEvent.View.Accessibility {
    init(old: RUMViewEvent.View.Accessibility?, new: RUMViewEvent.View.Accessibility) {
        self.init(
            assistiveSwitchEnabled: diff(old?.assistiveSwitchEnabled, new.assistiveSwitchEnabled),
            assistiveTouchEnabled: diff(old?.assistiveTouchEnabled, new.assistiveTouchEnabled),
            boldTextEnabled: diff(old?.boldTextEnabled, new.boldTextEnabled),
            buttonShapesEnabled: diff(old?.buttonShapesEnabled, new.buttonShapesEnabled),
            closedCaptioningEnabled: diff(old?.closedCaptioningEnabled, new.closedCaptioningEnabled),
            grayscaleEnabled: diff(old?.grayscaleEnabled, new.grayscaleEnabled),
            increaseContrastEnabled: diff(old?.increaseContrastEnabled, new.increaseContrastEnabled),
            invertColorsEnabled: diff(old?.invertColorsEnabled, new.invertColorsEnabled),
            monoAudioEnabled: diff(old?.monoAudioEnabled, new.monoAudioEnabled),
            onOffSwitchLabelsEnabled: diff(old?.onOffSwitchLabelsEnabled, new.onOffSwitchLabelsEnabled),
            reduceMotionEnabled: diff(old?.reduceMotionEnabled, new.reduceMotionEnabled),
            reduceTransparencyEnabled: diff(old?.reduceTransparencyEnabled, new.reduceTransparencyEnabled),
            reducedAnimationsEnabled: diff(old?.reducedAnimationsEnabled, new.reducedAnimationsEnabled),
            rtlEnabled: diff(old?.rtlEnabled, new.rtlEnabled),
            screenReaderEnabled: diff(old?.screenReaderEnabled, new.screenReaderEnabled),
            shakeToUndoEnabled: diff(old?.shakeToUndoEnabled, new.shakeToUndoEnabled),
            shouldDifferentiateWithoutColor: diff(old?.shouldDifferentiateWithoutColor, new.shouldDifferentiateWithoutColor),
            singleAppModeEnabled: diff(old?.singleAppModeEnabled, new.singleAppModeEnabled),
            speakScreenEnabled: diff(old?.speakScreenEnabled, new.speakScreenEnabled),
            speakSelectionEnabled: diff(old?.speakSelectionEnabled, new.speakSelectionEnabled),
            textSize: diff(old?.textSize, new.textSize),
            videoAutoplayEnabled: diff(old?.videoAutoplayEnabled, new.videoAutoplayEnabled)
        )
    }
}

private extension RUMViewUpdateEvent.View.Action {
    init(_ s: RUMViewEvent.View.Action) { self.init(count: s.count) }
}

private extension RUMViewUpdateEvent.View.Crash {
    init(_ s: RUMViewEvent.View.Crash) { self.init(count: s.count) }
}

private extension RUMViewUpdateEvent.View.CustomTimings {
    init(_ s: RUMViewEvent.View.CustomTimings) { self.init(customTimingsInfo: s.customTimingsInfo) }
}

private extension RUMViewUpdateEvent.View.Error {
    init(_ s: RUMViewEvent.View.Error) { self.init(count: s.count) }
}

private extension RUMViewUpdateEvent.View.FlutterBuildTime {
    init(_ s: RUMViewEvent.View.FlutterBuildTime) {
        self.init(average: s.average, max: s.max, metricMax: s.metricMax, min: s.min)
    }
}

private extension RUMViewUpdateEvent.View.FlutterRasterTime {
    init(_ s: RUMViewEvent.View.FlutterRasterTime) {
        self.init(average: s.average, max: s.max, metricMax: s.metricMax, min: s.min)
    }
}

private extension RUMViewUpdateEvent.View.FrozenFrame {
    init(_ s: RUMViewEvent.View.FrozenFrame) { self.init(count: s.count) }
}

private extension RUMViewUpdateEvent.View.Frustration {
    init(_ s: RUMViewEvent.View.Frustration) { self.init(count: s.count) }
}

private extension RUMViewUpdateEvent.View.InForegroundPeriods {
    init(_ s: RUMViewEvent.View.InForegroundPeriods) { self.init(duration: s.duration, start: s.start) }
}

private extension RUMViewUpdateEvent.View.JsRefreshRate {
    init(_ s: RUMViewEvent.View.JsRefreshRate) {
        self.init(average: s.average, max: s.max, metricMax: s.metricMax, min: s.min)
    }
}

private extension RUMViewUpdateEvent.View.LongTask {
    init(_ s: RUMViewEvent.View.LongTask) { self.init(count: s.count) }
}

private extension RUMViewUpdateEvent.View.Performance {
    init(_ s: RUMViewEvent.View.Performance) {
        self.init(
            cls: s.cls.map { .init($0) },
            fbc: s.fbc.map { .init($0) },
            fcp: s.fcp.map { .init($0) },
            fid: s.fid.map { .init($0) },
            inp: s.inp.map { .init($0) },
            lcp: s.lcp.map { .init($0) }
        )
    }
}

private extension RUMViewUpdateEvent.View.Performance.CLS {
    init(_ s: RUMViewEvent.View.Performance.CLS) {
        self.init(
            currentRect: s.currentRect.map { .init($0) },
            previousRect: s.previousRect.map { .init($0) },
            score: s.score,
            targetSelector: s.targetSelector,
            timestamp: s.timestamp
        )
    }
}

private extension RUMViewUpdateEvent.View.Performance.CLS.CurrentRect {
    init(_ s: RUMViewEvent.View.Performance.CLS.CurrentRect) {
        self.init(height: s.height, width: s.width, x: s.x, y: s.y)
    }
}

private extension RUMViewUpdateEvent.View.Performance.CLS.PreviousRect {
    init(_ s: RUMViewEvent.View.Performance.CLS.PreviousRect) {
        self.init(height: s.height, width: s.width, x: s.x, y: s.y)
    }
}

private extension RUMViewUpdateEvent.View.Performance.FBC {
    init(_ s: RUMViewEvent.View.Performance.FBC) { self.init(timestamp: s.timestamp) }
}

private extension RUMViewUpdateEvent.View.Performance.FCP {
    init(_ s: RUMViewEvent.View.Performance.FCP) { self.init(timestamp: s.timestamp) }
}

private extension RUMViewUpdateEvent.View.Performance.FID {
    init(_ s: RUMViewEvent.View.Performance.FID) {
        self.init(duration: s.duration, targetSelector: s.targetSelector, timestamp: s.timestamp)
    }
}

private extension RUMViewUpdateEvent.View.Performance.INP {
    init(_ s: RUMViewEvent.View.Performance.INP) {
        self.init(
            duration: s.duration,
            subParts: s.subParts.map { .init($0) },
            targetSelector: s.targetSelector,
            timestamp: s.timestamp
        )
    }
}

private extension RUMViewUpdateEvent.View.Performance.INP.SubParts {
    init(_ s: RUMViewEvent.View.Performance.INP.SubParts) {
        self.init(inputDelay: s.inputDelay, presentationDelay: s.presentationDelay, processingDuration: s.processingDuration)
    }
}

private extension RUMViewUpdateEvent.View.Performance.LCP {
    init(_ s: RUMViewEvent.View.Performance.LCP) {
        self.init(
            resourceUrl: s.resourceUrl,
            subParts: s.subParts.map { .init($0) },
            targetSelector: s.targetSelector,
            timestamp: s.timestamp
        )
    }
}

private extension RUMViewUpdateEvent.View.Performance.LCP.SubParts {
    init(_ s: RUMViewEvent.View.Performance.LCP.SubParts) {
        self.init(loadDelay: s.loadDelay, loadTime: s.loadTime, renderDelay: s.renderDelay)
    }
}

private extension RUMViewUpdateEvent.View.Resource {
    init(_ s: RUMViewEvent.View.Resource) { self.init(count: s.count) }
}

private extension RUMViewUpdateEvent.View.SlowFrames {
    init(_ s: RUMViewEvent.View.SlowFrames) { self.init(duration: s.duration, start: s.start) }
}
