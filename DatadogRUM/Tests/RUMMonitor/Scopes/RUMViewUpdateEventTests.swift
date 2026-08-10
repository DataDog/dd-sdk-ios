/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogInternal
@testable import DatadogRUM
@testable import TestUtilities

/// Tests the roundtrip invariant for `RUMViewEvent.update(from:)`:
/// for any two view events A and B, `A.apply(update: A.update(from: B))` must equal B
/// for every field that the update path diffs or forwards.
///
/// The key structural guarantee: when a new field is added to `RUMViewEvent`, the compiler forces
/// `update(from:)` to be updated (it uses `RUMViewUpdateEvent.init` which lists all fields), and
/// `mockRandom()` to be updated (it uses `RUMViewEvent.init`). The `apply(update:)` extension below
/// mirrors this: it explicitly calls `RUMViewEvent.init(...)` and `RUMViewEvent.View.init(...)`,
/// so any new field that isn't handled here also fails to compile.
class RUMViewUpdateEventTests: XCTestCase {
    func testRoundtrip_allDiffableFieldsAreReconstructed() throws {
        for _ in 0..<100 {
            let base = RUMViewEvent.mockRandom()
            let target = RUMViewEvent.mockRandom()
            let update = base.update(from: target)
            let reconstructed = base.apply(update: update)
            DDAssertJSONEqual(reconstructed, target)
        }
    }
}

// MARK: - RUMViewEvent apply extensions

private extension RUMViewEvent {
    /// Applies a `RUMViewUpdateEvent` on top of `self`, reconstructing the target event.
    ///
    /// Nil fields in the update (meaning "unchanged") keep the value from `self`; non-nil fields
    /// override it. This is the inverse of `RUMViewEvent.update(from:)`.
    ///
    /// The explicit `RUMViewEvent.init(...)`, `RUMViewEvent.DD.apply(update:)`, and
    /// `RUMViewEvent.View.apply(update:)` calls are intentional: when a new field is added to those
    /// types, this method won't compile until it's handled here — the same structural guarantee that
    /// `mockRandom()` and `update(from:)` provide.
    func apply(update: RUMViewUpdateEvent) -> RUMViewEvent {
        RUMViewEvent(
            dd: dd.apply(update: update.dd),
            account: update.account ?? account,
            application: .init(update.application),
            buildId: update.buildId ?? buildId,
            buildVersion: update.buildVersion ?? buildVersion,
            ciTest: update.ciTest ?? ciTest,
            connectivity: update.connectivity ?? connectivity,
            container: update.container.map { .init($0) } ?? container,
            context: update.context ?? context,
            date: update.date,
            ddtags: update.ddtags ?? ddtags,
            device: update.device ?? device,
            display: update.display.map { .init($0) } ?? display,
            featureFlags: update.featureFlags.map { .init($0) } ?? featureFlags,
            os: update.os ?? os,
            privacy: update.privacy.map { .init($0) } ?? privacy,
            service: update.service ?? service,
            session: .init(update.session),
            source: update.source.map { .init($0) } ?? source,
            stream: update.stream.map { .init($0) } ?? stream,
            synthetics: update.synthetics ?? synthetics,
            tab: update.tab.map { .init($0) } ?? tab,
            usr: update.usr ?? usr,
            version: update.version ?? version,
            view: view.apply(update: update.view)
        )
    }
}

private extension RUMViewEvent.DD {
    // dd is always forwarded wholesale from the target in update(from:), so all fields come
    // from the update — nil means the target field was nil, not that it was unchanged.
    func apply(update: RUMViewUpdateEvent.DD) -> RUMViewEvent.DD {
        RUMViewEvent.DD(
            browserSdkVersion: update.browserSdkVersion,
            cls: update.cls.map { .init($0) },
            configuration: update.configuration.map { .init($0) },
            documentVersion: update.documentVersion,
            pageStates: update.pageStates.map { $0.map { .init($0) } },
            profiling: update.profiling,
            replayStats: update.replayStats.map { .init($0) },
            sdkName: update.sdkName,
            session: update.session.map { .init($0) }
        )
    }
}

private extension RUMViewEvent.View {
    func apply(update: RUMViewUpdateEvent.View) -> RUMViewEvent.View {
        RUMViewEvent.View(
            accessibility: update.accessibility.map { .init($0, fallback: accessibility) } ?? accessibility,
            action: update.action.map { .init($0) } ?? action,
            cpuTicksCount: update.cpuTicksCount ?? cpuTicksCount,
            cpuTicksPerSecond: update.cpuTicksPerSecond ?? cpuTicksPerSecond,
            crash: update.crash.map { .init($0) } ?? crash,
            cumulativeLayoutShift: update.cumulativeLayoutShift ?? cumulativeLayoutShift,
            cumulativeLayoutShiftTargetSelector: update.cumulativeLayoutShiftTargetSelector ?? cumulativeLayoutShiftTargetSelector,
            cumulativeLayoutShiftTime: update.cumulativeLayoutShiftTime ?? cumulativeLayoutShiftTime,
            customTimings: update.customTimings.map { .init($0) } ?? customTimings,
            domComplete: update.domComplete ?? domComplete,
            domContentLoaded: update.domContentLoaded ?? domContentLoaded,
            domInteractive: update.domInteractive ?? domInteractive,
            error: update.error.map { .init($0) } ?? error,
            firstByte: update.firstByte ?? firstByte,
            firstContentfulPaint: update.firstContentfulPaint ?? firstContentfulPaint,
            firstInputDelay: update.firstInputDelay ?? firstInputDelay,
            firstInputTargetSelector: update.firstInputTargetSelector ?? firstInputTargetSelector,
            firstInputTime: update.firstInputTime ?? firstInputTime,
            flutterBuildTime: update.flutterBuildTime.map { .init($0) } ?? flutterBuildTime,
            flutterRasterTime: update.flutterRasterTime.map { .init($0) } ?? flutterRasterTime,
            freezeRate: update.freezeRate ?? freezeRate,
            frozenFrame: update.frozenFrame.map { .init($0) } ?? frozenFrame,
            frustration: update.frustration.map { .init($0) } ?? frustration,
            id: update.id,
            inForegroundPeriods: update.inForegroundPeriods.map { $0.map { .init($0) } } ?? inForegroundPeriods,
            interactionToNextPaint: update.interactionToNextPaint ?? interactionToNextPaint,
            interactionToNextPaintTargetSelector: update.interactionToNextPaintTargetSelector ?? interactionToNextPaintTargetSelector,
            interactionToNextPaintTime: update.interactionToNextPaintTime ?? interactionToNextPaintTime,
            interactionToNextViewTime: update.interactionToNextViewTime ?? interactionToNextViewTime,
            isActive: update.isActive ?? isActive,
            isSlowRendered: update.isSlowRendered ?? isSlowRendered,
            jsRefreshRate: update.jsRefreshRate.map { .init($0) } ?? jsRefreshRate,
            largestContentfulPaint: update.largestContentfulPaint ?? largestContentfulPaint,
            largestContentfulPaintTargetSelector: update.largestContentfulPaintTargetSelector ?? largestContentfulPaintTargetSelector,
            loadEvent: update.loadEvent ?? loadEvent,
            loadingTime: update.loadingTime ?? loadingTime,
            loadingType: update.loadingType.map { .init($0) } ?? loadingType,
            longTask: update.longTask.map { .init($0) } ?? longTask,
            memoryAverage: update.memoryAverage ?? memoryAverage,
            memoryMax: update.memoryMax ?? memoryMax,
            name: update.name ?? name,
            networkSettledTime: update.networkSettledTime ?? networkSettledTime,
            performance: update.performance.map { .init($0) } ?? performance,
            referrer: update.referrer ?? referrer,
            refreshRateAverage: update.refreshRateAverage ?? refreshRateAverage,
            refreshRateMin: update.refreshRateMin ?? refreshRateMin,
            resource: update.resource.map { .init($0) } ?? resource,
            slowFrames: update.slowFrames.map { $0.map { .init($0) } } ?? slowFrames,
            slowFramesRate: update.slowFramesRate ?? slowFramesRate,
            timeSpent: update.timeSpent ?? timeSpent,
            url: update.url
        )
    }
}

// MARK: - RUMViewEvent type extensions (inverse of RUMViewEvent+Update.swift projections)

private extension RUMViewEvent.Application {
    init(_ s: RUMViewUpdateEvent.Application) {
        self.init(currentLocale: s.currentLocale, id: s.id)
    }
}

private extension RUMViewEvent.Container {
    init(_ s: RUMViewUpdateEvent.Container) {
        self.init(source: .init(s.source), view: .init(s.view))
    }
}

private extension RUMViewEvent.Container.Source {
    init(_ s: RUMViewUpdateEvent.Container.Source) {
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

private extension RUMViewEvent.Container.View {
    init(_ s: RUMViewUpdateEvent.Container.View) { self.init(id: s.id) }
}

private extension RUMViewEvent.Display {
    init(_ s: RUMViewUpdateEvent.Display) {
        self.init(scroll: s.scroll.map { .init($0) }, viewport: s.viewport.map { .init($0) })
    }
}

private extension RUMViewEvent.Display.Scroll {
    init(_ s: RUMViewUpdateEvent.Display.Scroll) {
        self.init(
            maxDepth: s.maxDepth,
            maxDepthScrollTop: s.maxDepthScrollTop,
            maxScrollHeight: s.maxScrollHeight,
            maxScrollHeightTime: s.maxScrollHeightTime
        )
    }
}

private extension RUMViewEvent.Display.Viewport {
    init(_ s: RUMViewUpdateEvent.Display.Viewport) { self.init(height: s.height, width: s.width) }
}

private extension RUMViewEvent.FeatureFlags {
    init(_ s: RUMViewUpdateEvent.FeatureFlags) { self.init(featureFlagsInfo: s.featureFlagsInfo) }
}

private extension RUMViewEvent.Privacy {
    init(_ s: RUMViewUpdateEvent.Privacy) { self.init(replayLevel: .init(s.replayLevel)) }
}

private extension RUMViewEvent.Privacy.ReplayLevel {
    init(_ s: RUMViewUpdateEvent.Privacy.ReplayLevel) {
        switch s {
        case .allow: self = .allow
        case .mask: self = .mask
        case .maskUserInput: self = .maskUserInput
        }
    }
}

private extension RUMViewEvent.Session {
    init(_ s: RUMViewUpdateEvent.Session) {
        self.init(
            hasReplay: s.hasReplay,
            id: s.id,
            isActive: s.isActive,
            sampledForReplay: s.sampledForReplay,
            type: s.type
        )
    }
}

private extension RUMViewEvent.Source {
    init(_ s: RUMViewUpdateEvent.Source) {
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

private extension RUMViewEvent.Stream {
    init(_ s: RUMViewUpdateEvent.Stream) {
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

private extension RUMViewEvent.TAB {
    init(_ s: RUMViewUpdateEvent.TAB) { self.init(id: s.id) }
}

// MARK: - DD sub-type extensions

private extension RUMViewEvent.DD.CLS {
    init(_ s: RUMViewUpdateEvent.DD.CLS) { self.init(devicePixelRatio: s.devicePixelRatio) }
}

private extension RUMViewEvent.DD.Configuration {
    init(_ s: RUMViewUpdateEvent.DD.Configuration) {
        self.init(
            profilingSampleRate: s.profilingSampleRate,
            sessionReplayExperimentalFeatures: s.sessionReplayExperimentalFeatures,
            sessionReplaySampleRate: s.sessionReplaySampleRate,
            sessionSampleRate: s.sessionSampleRate,
            startSessionReplayRecordingManually: s.startSessionReplayRecordingManually,
            traceSampleRate: s.traceSampleRate
        )
    }
}

private extension RUMViewEvent.DD.PageStates {
    init(_ s: RUMViewUpdateEvent.DD.PageStates) { self.init(start: s.start, state: .init(s.state)) }
}

private extension RUMViewEvent.DD.PageStates.State {
    init(_ s: RUMViewUpdateEvent.DD.PageStates.State) {
        switch s {
        case .active: self = .active
        case .passive: self = .passive
        case .hidden: self = .hidden
        case .frozen: self = .frozen
        case .terminated: self = .terminated
        }
    }
}

private extension RUMViewEvent.DD.ReplayStats {
    init(_ s: RUMViewUpdateEvent.DD.ReplayStats) {
        self.init(
            recordsCount: s.recordsCount,
            segmentsCount: s.segmentsCount,
            segmentsTotalRawSize: s.segmentsTotalRawSize
        )
    }
}

private extension RUMViewEvent.DD.Session {
    init(_ s: RUMViewUpdateEvent.DD.Session) {
        self.init(plan: s.plan.map { .init($0) }, sessionPrecondition: s.sessionPrecondition)
    }
}

private extension RUMViewEvent.DD.Session.Plan {
    init(_ s: RUMViewUpdateEvent.DD.Session.Plan) {
        switch s {
        case .plan1: self = .plan1
        case .plan2: self = .plan2
        }
    }
}

// MARK: - View sub-type extensions

private extension RUMViewEvent.View.Accessibility {
    // Accessibility fields are individually diffed in update(from:), so each may be nil (unchanged).
    // Fall back to the corresponding base field when nil.
    init(_ s: RUMViewUpdateEvent.View.Accessibility, fallback: RUMViewEvent.View.Accessibility?) {
        self.init(
            assistiveSwitchEnabled: s.assistiveSwitchEnabled ?? fallback?.assistiveSwitchEnabled,
            assistiveTouchEnabled: s.assistiveTouchEnabled ?? fallback?.assistiveTouchEnabled,
            boldTextEnabled: s.boldTextEnabled ?? fallback?.boldTextEnabled,
            buttonShapesEnabled: s.buttonShapesEnabled ?? fallback?.buttonShapesEnabled,
            closedCaptioningEnabled: s.closedCaptioningEnabled ?? fallback?.closedCaptioningEnabled,
            grayscaleEnabled: s.grayscaleEnabled ?? fallback?.grayscaleEnabled,
            increaseContrastEnabled: s.increaseContrastEnabled ?? fallback?.increaseContrastEnabled,
            invertColorsEnabled: s.invertColorsEnabled ?? fallback?.invertColorsEnabled,
            monoAudioEnabled: s.monoAudioEnabled ?? fallback?.monoAudioEnabled,
            onOffSwitchLabelsEnabled: s.onOffSwitchLabelsEnabled ?? fallback?.onOffSwitchLabelsEnabled,
            reduceMotionEnabled: s.reduceMotionEnabled ?? fallback?.reduceMotionEnabled,
            reduceTransparencyEnabled: s.reduceTransparencyEnabled ?? fallback?.reduceTransparencyEnabled,
            reducedAnimationsEnabled: s.reducedAnimationsEnabled ?? fallback?.reducedAnimationsEnabled,
            rtlEnabled: s.rtlEnabled ?? fallback?.rtlEnabled,
            screenReaderEnabled: s.screenReaderEnabled ?? fallback?.screenReaderEnabled,
            shakeToUndoEnabled: s.shakeToUndoEnabled ?? fallback?.shakeToUndoEnabled,
            shouldDifferentiateWithoutColor: s.shouldDifferentiateWithoutColor ?? fallback?.shouldDifferentiateWithoutColor,
            singleAppModeEnabled: s.singleAppModeEnabled ?? fallback?.singleAppModeEnabled,
            speakScreenEnabled: s.speakScreenEnabled ?? fallback?.speakScreenEnabled,
            speakSelectionEnabled: s.speakSelectionEnabled ?? fallback?.speakSelectionEnabled,
            textSize: s.textSize ?? fallback?.textSize,
            videoAutoplayEnabled: s.videoAutoplayEnabled ?? fallback?.videoAutoplayEnabled
        )
    }
}

private extension RUMViewEvent.View.Action {
    init(_ s: RUMViewUpdateEvent.View.Action) { self.init(count: s.count) }
}

private extension RUMViewEvent.View.Crash {
    init(_ s: RUMViewUpdateEvent.View.Crash) { self.init(count: s.count) }
}

private extension RUMViewEvent.View.CustomTimings {
    init(_ s: RUMViewUpdateEvent.View.CustomTimings) { self.init(customTimingsInfo: s.customTimingsInfo) }
}

private extension RUMViewEvent.View.Error {
    init(_ s: RUMViewUpdateEvent.View.Error) { self.init(count: s.count) }
}

private extension RUMViewEvent.View.FlutterBuildTime {
    init(_ s: RUMViewUpdateEvent.View.FlutterBuildTime) {
        self.init(average: s.average, max: s.max, metricMax: s.metricMax, min: s.min)
    }
}

private extension RUMViewEvent.View.FlutterRasterTime {
    init(_ s: RUMViewUpdateEvent.View.FlutterRasterTime) {
        self.init(average: s.average, max: s.max, metricMax: s.metricMax, min: s.min)
    }
}

private extension RUMViewEvent.View.FrozenFrame {
    init(_ s: RUMViewUpdateEvent.View.FrozenFrame) { self.init(count: s.count) }
}

private extension RUMViewEvent.View.Frustration {
    init(_ s: RUMViewUpdateEvent.View.Frustration) { self.init(count: s.count) }
}

private extension RUMViewEvent.View.InForegroundPeriods {
    init(_ s: RUMViewUpdateEvent.View.InForegroundPeriods) { self.init(duration: s.duration, start: s.start) }
}

private extension RUMViewEvent.View.JsRefreshRate {
    init(_ s: RUMViewUpdateEvent.View.JsRefreshRate) {
        self.init(average: s.average, max: s.max, metricMax: s.metricMax, min: s.min)
    }
}

private extension RUMViewEvent.View.LoadingType {
    init(_ s: RUMViewUpdateEvent.View.LoadingType) {
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

private extension RUMViewEvent.View.LongTask {
    init(_ s: RUMViewUpdateEvent.View.LongTask) { self.init(count: s.count) }
}

private extension RUMViewEvent.View.Performance {
    init(_ s: RUMViewUpdateEvent.View.Performance) {
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

private extension RUMViewEvent.View.Performance.CLS {
    init(_ s: RUMViewUpdateEvent.View.Performance.CLS) {
        self.init(
            currentRect: s.currentRect.map { .init($0) },
            previousRect: s.previousRect.map { .init($0) },
            score: s.score,
            targetSelector: s.targetSelector,
            timestamp: s.timestamp
        )
    }
}

private extension RUMViewEvent.View.Performance.CLS.CurrentRect {
    init(_ s: RUMViewUpdateEvent.View.Performance.CLS.CurrentRect) {
        self.init(height: s.height, width: s.width, x: s.x, y: s.y)
    }
}

private extension RUMViewEvent.View.Performance.CLS.PreviousRect {
    init(_ s: RUMViewUpdateEvent.View.Performance.CLS.PreviousRect) {
        self.init(height: s.height, width: s.width, x: s.x, y: s.y)
    }
}

private extension RUMViewEvent.View.Performance.FBC {
    init(_ s: RUMViewUpdateEvent.View.Performance.FBC) { self.init(timestamp: s.timestamp) }
}

private extension RUMViewEvent.View.Performance.FCP {
    init(_ s: RUMViewUpdateEvent.View.Performance.FCP) { self.init(timestamp: s.timestamp) }
}

private extension RUMViewEvent.View.Performance.FID {
    init(_ s: RUMViewUpdateEvent.View.Performance.FID) {
        self.init(duration: s.duration, targetSelector: s.targetSelector, timestamp: s.timestamp)
    }
}

private extension RUMViewEvent.View.Performance.INP {
    init(_ s: RUMViewUpdateEvent.View.Performance.INP) {
        self.init(
            duration: s.duration,
            subParts: s.subParts.map { .init($0) },
            targetSelector: s.targetSelector,
            timestamp: s.timestamp
        )
    }
}

private extension RUMViewEvent.View.Performance.INP.SubParts {
    init(_ s: RUMViewUpdateEvent.View.Performance.INP.SubParts) {
        self.init(inputDelay: s.inputDelay, presentationDelay: s.presentationDelay, processingDuration: s.processingDuration)
    }
}

private extension RUMViewEvent.View.Performance.LCP {
    init(_ s: RUMViewUpdateEvent.View.Performance.LCP) {
        self.init(
            resourceUrl: s.resourceUrl,
            subParts: s.subParts.map { .init($0) },
            targetSelector: s.targetSelector,
            timestamp: s.timestamp
        )
    }
}

private extension RUMViewEvent.View.Performance.LCP.SubParts {
    init(_ s: RUMViewUpdateEvent.View.Performance.LCP.SubParts) {
        self.init(loadDelay: s.loadDelay, loadTime: s.loadTime, renderDelay: s.renderDelay)
    }
}

private extension RUMViewEvent.View.Resource {
    init(_ s: RUMViewUpdateEvent.View.Resource) { self.init(count: s.count) }
}

private extension RUMViewEvent.View.SlowFrames {
    init(_ s: RUMViewUpdateEvent.View.SlowFrames) { self.init(duration: s.duration, start: s.start) }
}
