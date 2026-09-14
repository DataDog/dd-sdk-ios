/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import SwiftUI
import UIKit
#if DEBUG
@testable import DatadogRUM
#else
import DatadogRUM
#endif

#if DEBUG
private typealias ProbeNavigationOccurrenceSource = RUMSwiftUINavigationOccurrenceSource
#else
private final class ProbeNavigationOccurrenceSource {}
#endif

struct ProbeWindow: Codable, Hashable {
    static let windowGroupID = "rum-probe"

    let runID: String
    let label: String
    let opensPeer: Bool
}

private enum ProbeRoute: Hashable {
    case detail(Int)
    case alternate
}

private enum ProbeNavigationOccurrence: Hashable {
    case home
    case detail(Int)
    case alternate
    case splitDetail(Int)
    case splitPlaceholder
}

private enum ProbeSplitSelection: Hashable {
    case detail(Int)
    case placeholder

    var screen: String {
        switch self {
        case .detail(let instance):
            return "detail-\(instance)"
        case .placeholder:
            return "placeholder"
        }
    }
}

private enum ProbeTrackingBoundary: Equatable {
    case navigationRoute
    case auxiliary
}

private struct ProbeRUMNavigationView {
    let screen: String
    let name: String
    let occurrence: ProbeNavigationOccurrence
}

private struct ProbeRUMTrackedScreen<Content: View>: View {
    let window: ProbeWindow
    let sceneSessionID: String
    let screen: String
    let name: String
    let trackingBoundary: ProbeTrackingBoundary
    let readerControlGeneration: Int
    let navigationOccurrence: ProbeNavigationOccurrence?
    let bindingGeneration: UInt64
    let navigationOccurrenceSource: ProbeNavigationOccurrenceSource?
    @ViewBuilder let content: Content

    init(
        window: ProbeWindow,
        sceneSessionID: String,
        screen: String,
        name: String,
        trackingBoundary: ProbeTrackingBoundary,
        readerControlGeneration: Int,
        navigationOccurrence: ProbeNavigationOccurrence? = nil,
        bindingGeneration: UInt64 = 0,
        navigationOccurrenceSource: ProbeNavigationOccurrenceSource? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.window = window
        self.sceneSessionID = sceneSessionID
        self.screen = screen
        self.name = name
        self.trackingBoundary = trackingBoundary
        self.readerControlGeneration = readerControlGeneration
        self.navigationOccurrence = navigationOccurrence
        self.bindingGeneration = bindingGeneration
        self.navigationOccurrenceSource = navigationOccurrenceSource
        self.content = content()
    }

    @ViewBuilder
    var body: some View {
        #if DEBUG
        if ProbeRuntime.usesNavigationOccurrenceSwiftUIViewTracking {
            if usesExplicitTracking, let navigationOccurrence {
                content.trackRUMView(
                    name: name,
                    occurrenceKey: RUMViewOccurrenceKey(navigationOccurrence),
                    bindingGeneration: bindingGeneration,
                    navigationOccurrenceSource: navigationOccurrenceSource,
                    attributes: trackingAttributes
                )
            } else {
                content
            }
        } else if usesExplicitTracking {
            content.trackRUMView(
                name: name,
                attributes: trackingAttributes
            )
        } else {
            content
        }
        #else
        if usesExplicitTracking {
            content.trackRUMView(name: name, attributes: trackingAttributes)
        } else {
            content
        }
        #endif
    }

    private var usesExplicitTracking: Bool {
        if ProbeRuntime.usesManualSwiftUIViewTracking(
            in: window.label,
            screen: screen
        ) {
            return true
        }
        if ProbeRuntime.usesAutomaticSwiftUIViewTracking {
            return false
        }
        if ProbeRuntime.usesNavigationOccurrenceSwiftUIViewTracking {
            return trackingBoundary == .navigationRoute
                && ProbeRuntime.usesSemanticNavigationTracking(in: window.label)
        }
        if ProbeRuntime.usesNavigationPathSwiftUIViewTracking {
            return trackingBoundary == .navigationRoute
        }
        return true
    }

    private var trackingAttributes: [String: Encodable] {
        [
            ProbeRuntime.Attribute.runID: window.runID,
            ProbeRuntime.Attribute.host: trackingHost,
            ProbeRuntime.Attribute.sourceScene: window.label,
            ProbeRuntime.Attribute.sceneSessionID: sceneSessionID,
            ProbeRuntime.Attribute.screen: screen,
            ProbeRuntime.Attribute.viewScene: window.label,
            ProbeRuntime.Attribute.viewSceneSessionID: sceneSessionID,
            ProbeRuntime.Attribute.viewScreen: screen,
            ProbeRuntime.Attribute.readerControlGeneration: readerControlGeneration
        ]
    }

    private var trackingHost: String {
        if ProbeRuntime.usesNavigationOccurrenceSwiftUIViewTracking {
            return "native-swiftui-navigation-occurrence"
        }
        if ProbeRuntime.usesNavigationPathSwiftUIViewTracking {
            return "native-swiftui-navigation-path"
        }
        return "native-swiftui"
    }
}

private enum ProbeSwiftUIPresentation: String {
    case sheet
    case fullScreenCover = "full-screen-cover"

    var rumViewName: String {
        switch self {
        case .sheet:
            return "ProbeSheetView"
        case .fullScreenCover:
            return "ProbeFullScreenCoverView"
        }
    }

    var manualViewKey: String { "probe-scene-targeted-\(rawValue)" }
    var activeInterval: String { "manual-\(rawValue)-active" }

    var subtreeInterval: String {
        switch self {
        case .sheet:
            return "swiftui-presentation-subtree"
        case .fullScreenCover:
            return "swiftui-full-screen-cover-subtree"
        }
    }

    var dismissedImmediatePhase: String { "\(rawValue)-dismissed-immediate" }
    var dismissedSettledPhase: String { "\(rawValue)-dismissed-settled" }
}

private enum ProbeKeyedManualDestination: String, Hashable {
    case compose
    case preview

    var manualViewKey: String {
        switch self {
        case .compose:
            return "probe-keyed-manual-view"
        case .preview:
            return "probe-keyed-manual-preview"
        }
    }

    var rumViewName: String {
        switch self {
        case .compose:
            return "ProbeKeyedManualView"
        case .preview:
            return "ProbeKeyedManualPreviewView"
        }
    }
}

private struct ProbeRUMSemanticPresentationBoundary<Content: View>: View {
    let isEnabled: Bool
    @ViewBuilder let content: Content

    init(isEnabled: Bool, @ViewBuilder content: () -> Content) {
        self.isEnabled = isEnabled
        self.content = content()
    }

    @ViewBuilder
    var body: some View {
        #if DEBUG
        if isEnabled {
            content.suppressAutomaticRUMViewTracking()
        } else {
            content
        }
        #else
        content
        #endif
    }
}

private struct ProbeControllerAncestry: Equatable {
    let identities: [ObjectIdentifier]
    let classNames: [String]
}

/// Runtime witness used only by the sibling-container experiment. It proves
/// that SwiftUI materialized separate controller branches before the probe
/// draws conclusions from the SDK's controller-containment authority rule.
private struct ProbeControllerAncestryReader: UIViewRepresentable {
    let role: String
    let didResolve: (String, ProbeControllerAncestry) -> Void

    func makeUIView(context: Context) -> ReaderView {
        ReaderView(role: role, didResolve: didResolve)
    }

    func updateUIView(_ uiView: ReaderView, context: Context) {
        uiView.role = role
        uiView.didResolve = didResolve
        uiView.resolveAfterAttachment()
    }

    final class ReaderView: UIView {
        var role: String
        var didResolve: (String, ProbeControllerAncestry) -> Void

        init(
            role: String,
            didResolve: @escaping (String, ProbeControllerAncestry) -> Void
        ) {
            self.role = role
            self.didResolve = didResolve
            super.init(frame: .zero)
            isHidden = true
            isUserInteractionEnabled = false
            accessibilityIdentifier = "probe.controller-ancestry.\(role)"
        }

        required init?(coder: NSCoder) {
            role = "unresolved"
            didResolve = { _, _ in }
            super.init(coder: coder)
            isHidden = true
            isUserInteractionEnabled = false
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            resolveAfterAttachment()
        }

        func resolveAfterAttachment() {
            Task { @MainActor [weak self] in
                await Task.yield()
                self?.resolve()
            }
        }

        private func resolve() {
            guard window != nil else {
                return
            }
            var responder: UIResponder? = self
            var identities: [ObjectIdentifier] = []
            var classNames: [String] = []
            var remainingDepth = 64
            while remainingDepth > 0, let next = responder?.next {
                responder = next
                remainingDepth -= 1
                guard let controller = next as? UIViewController else {
                    continue
                }
                identities.append(ObjectIdentifier(controller))
                classNames.append(String(reflecting: type(of: controller)))
            }
            guard !identities.isEmpty else {
                return
            }
            didResolve(
                role,
                ProbeControllerAncestry(
                    identities: identities,
                    classNames: classNames
                )
            )
        }
    }
}

/// Probe-only shape for the reviewed once-per-container integration. It keeps
/// route-to-RUM metadata and the SDK-owned tracking modifier out of destination
/// views while preserving route-owned placement at each materialized boundary.
private struct ProbeRUMNavigationStack<Root: View, Destination: View>: View {
    let window: ProbeWindow
    let sceneSessionID: String
    let readerControlGeneration: Int
    let path: Binding<[ProbeRoute]>
    let root: ProbeRUMNavigationView
    let destination: (ProbeRoute) -> ProbeRUMNavigationView
    let bindingGeneration: (ProbeNavigationOccurrence) -> UInt64
    let navigationOccurrenceSource: ProbeNavigationOccurrenceSource
    @ViewBuilder let rootContent: Root
    @ViewBuilder let destinationContent: (ProbeRoute) -> Destination

    init(
        window: ProbeWindow,
        sceneSessionID: String,
        readerControlGeneration: Int,
        path: Binding<[ProbeRoute]>,
        root: ProbeRUMNavigationView,
        destination: @escaping (ProbeRoute) -> ProbeRUMNavigationView,
        bindingGeneration: @escaping (ProbeNavigationOccurrence) -> UInt64,
        navigationOccurrenceSource: ProbeNavigationOccurrenceSource,
        @ViewBuilder rootContent: () -> Root,
        @ViewBuilder destinationContent: @escaping (ProbeRoute) -> Destination
    ) {
        self.window = window
        self.sceneSessionID = sceneSessionID
        self.readerControlGeneration = readerControlGeneration
        self.path = path
        self.root = root
        self.destination = destination
        self.bindingGeneration = bindingGeneration
        self.navigationOccurrenceSource = navigationOccurrenceSource
        self.rootContent = rootContent()
        self.destinationContent = destinationContent
    }

    var body: some View {
        NavigationStack(path: path) {
            tracked(rootContent, as: root)
                .navigationDestination(for: ProbeRoute.self) { route in
                    tracked(destinationContent(route), as: destination(route))
                        .modifier(
                            ProbeRouteIdentityModifier(
                                identity: route,
                                isEnabled: ProbeRuntime.forcesNavigationRouteIdentity
                                    && !ProbeRuntime.usesNavigationOccurrenceSwiftUIViewTracking
                            )
                        )
                }
        }
    }

    private func tracked<Content: View>(
        _ content: Content,
        as rumView: ProbeRUMNavigationView
    ) -> some View {
        ProbeRUMTrackedScreen(
            window: window,
            sceneSessionID: sceneSessionID,
            screen: rumView.screen,
            name: rumView.name,
            trackingBoundary: .navigationRoute,
            readerControlGeneration: readerControlGeneration,
            navigationOccurrence: rumView.occurrence,
            bindingGeneration: bindingGeneration(rumView.occurrence),
            navigationOccurrenceSource: navigationOccurrenceSource
        ) {
            content
        }
    }
}

struct ProbeWindowRoot: View {
    let window: ProbeWindow

    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.scenePhase)
    private var scenePhase
    @State private var path: [ProbeRoute] = []
    @State private var navigationMutation: UInt64 = 0
    @State private var rumViewBindingGeneration: UInt64 = 0
    @State private var homeBindingGeneration: UInt64 = 0
    @State private var destinationBindingGeneration: UInt64 = 0
    @State private var navigationOccurrenceSource = ProbeNavigationOccurrenceSource()
    @State private var splitSelection: ProbeSplitSelection? =
        ProbeRuntime.startsSplitWithoutSelection ? nil : .detail(1)
    @State private var splitRUMViewBindingGeneration: UInt64 = 1
    @State private var splitNavigationOccurrenceSource = ProbeNavigationOccurrenceSource()
    @State private var scenarioStepExecutor = ProbeSceneStepExecutor()
    @State private var uiKitNavigationStepExecutor = ProbeUIKitNavigationStepExecutor()
    @State private var sceneSessionID = "unresolved"
    @State private var sceneHandle: ProbeSceneHandle?
    @State private var readerControlGeneration = 0
    @State private var didScheduleNavigation = false
    @State private var didShowDetail = false
    @State private var didOpenPeer = false
    @State private var swiftUIPresentation: ProbeSwiftUIPresentation?
    @State private var keyedManualViewStack: [ProbeKeyedManualDestination] = []
    @State private var isSiblingAuthorityActive = false
    @State private var siblingControllerAncestries: [String: ProbeControllerAncestry] = [:]
    @State private var didReportSiblingControllerTopology = false
    @State private var didBeginSiblingContainerObservation = false
    @State private var didEndSiblingContainerObservation = false
    @State private var didScheduleClose = false
    @State private var didScheduleAbortedDetail = false
    @State private var didScheduleDetailReplacement = false
    @State private var didScheduleDetailInstanceReplacement = false
    @State private var didScheduleSyntheticReaderDisconnect = false

    var body: some View {
        Group {
            if ProbeRuntime.usesSiblingContainerAuthorityStress {
                siblingContainerContent
            } else if ProbeRuntime.usesTabPreloadStress {
                TabView {
                    navigationContent
                        .tabItem { Label("Visible", systemImage: "house") }

                    ProbeRUMTrackedScreen(
                        window: window,
                        sceneSessionID: sceneSessionID,
                        screen: "offscreen-tab",
                        name: "ProbeOffscreenTabView",
                        trackingBoundary: .auxiliary,
                        readerControlGeneration: readerControlGeneration
                    ) {
                        ProbeOffscreenTabView(window: window)
                    }
                    .tabItem { Label("Offscreen", systemImage: "eye.slash") }
                }
            } else {
                navigationContent
            }
        }
        .sheet(
            isPresented: sheetPresentation,
            onDismiss: sheetDidDismiss
        ) {
            ProbeRUMSemanticPresentationBoundary(
                isEnabled: ProbeRuntime.usesSceneTargetedPresentationAuthority
            ) {
                ProbeRUMTrackedScreen(
                    window: window,
                    sceneSessionID: sceneSessionID,
                    screen: "sheet",
                    name: "ProbeSheetView",
                    trackingBoundary: .auxiliary,
                    readerControlGeneration: readerControlGeneration
                ) {
                    ProbeSheetView(
                        window: window,
                        sceneSessionID: sceneSessionID
                    )
                }
            }
        }
        .fullScreenCover(
            isPresented: fullScreenCoverPresentation,
            onDismiss: fullScreenCoverDidDismiss
        ) {
            ProbeRUMSemanticPresentationBoundary(
                isEnabled: ProbeRuntime.usesSceneTargetedPresentationAuthority
            ) {
                ProbeRUMTrackedScreen(
                    window: window,
                    sceneSessionID: sceneSessionID,
                    screen: ProbeSwiftUIPresentation.fullScreenCover.rawValue,
                    name: ProbeSwiftUIPresentation.fullScreenCover.rumViewName,
                    trackingBoundary: .auxiliary,
                    readerControlGeneration: readerControlGeneration
                ) {
                    ProbeFullScreenCoverView(
                        window: window,
                        sceneSessionID: sceneSessionID
                    )
                }
            }
        }
        .background(
            SceneSessionReader { resolvedWindow in
                registerScene(resolvedWindow)
            }
        )
        .accessibilityIdentifier("probe.native.root.\(window.label)")
        .onChange(of: scenePhase, initial: true) { _, _ in
            updateScenePresentation(kind: .sceneLifecycle)
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: UIScene.didDisconnectNotification
            )
        ) { notification in
            guard
                let handle = sceneHandle,
                let disconnectedScene = notification.object as? UIWindowScene,
                disconnectedScene.session.persistentIdentifier == handle.nativeSceneID,
                let snapshot = ProbeRuntime.sceneRegistry.disconnect(handle)
            else {
                return
            }
            ProbeRuntime.scenarioDriver?.unregister(handle: handle)
            ProbeRuntime.recordSceneSnapshot(snapshot, kind: .sceneLifecycle)
            ProbeRuntime.record(
                "scene disconnected source=\(window.label) "
                    + "native=\(handle.nativeSceneID) "
                    + "generation=\(snapshot.disconnectGeneration)"
            )
            sceneHandle = nil
        }
        .task {
            guard
                ProbeRuntime.automaticallyNavigates,
                !ProbeRuntime.usesObservableScenarioDriver,
                !didScheduleNavigation
            else {
                return
            }
            didScheduleNavigation = true
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else {
                return
            }
            ProbeRuntime.record("navigation requested source=\(window.label) destination=detail")
            openDetail()
        }
        .task(id: didShowDetail) {
            guard
                didShowDetail,
                window.opensPeer,
                ProbeRuntime.automaticallyOpensSecondWindow,
                !ProbeRuntime.usesObservableScenarioDriver,
                !didOpenPeer
            else {
                return
            }
            didOpenPeer = true
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else {
                return
            }
            openPeer()
        }
        .task(id: sceneSessionID) {
            guard
                sceneSessionID != "unresolved",
                ProbeRuntime.usesAnySplitLayout,
                window.opensPeer,
                ProbeRuntime.automaticallyOpensSecondWindow,
                !ProbeRuntime.usesObservableScenarioDriver,
                !didOpenPeer
            else {
                return
            }
            didOpenPeer = true
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else {
                return
            }
            ProbeRuntime.record(
                "split peer open scheduled source=\(window.label) native=\(sceneSessionID)"
            )
            openPeer()
        }
        .task(id: didShowDetail) {
            guard
                didShowDetail,
                ProbeRuntime.automaticallyReplacesDetail,
                !ProbeRuntime.usesObservableScenarioDriver,
                !didScheduleDetailReplacement
            else {
                return
            }
            didScheduleDetailReplacement = true
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else {
                return
            }
            replaceDetailWithAlternate()
        }
        .task(id: didShowDetail) {
            guard
                didShowDetail,
                ProbeRuntime.automaticallyReplacesDetailInstance,
                !ProbeRuntime.usesObservableScenarioDriver,
                !didScheduleDetailInstanceReplacement
            else {
                return
            }
            didScheduleDetailInstanceReplacement = true
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else {
                return
            }
            replaceDetailWithNextInstance()
        }
        .task {
            guard
                ProbeRuntime.automaticallyClosesSceneB,
                window.label == "scene-B",
                !ProbeRuntime.usesObservableScenarioDriver,
                !didScheduleClose
            else {
                return
            }
            didScheduleClose = true
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(25))
            guard !Task.isCancelled else {
                return
            }
            closeCurrentWindow()
        }
        .task {
            guard
                ProbeRuntime.automaticallyAbortsDetail,
                !ProbeRuntime.automaticallyNavigates,
                !ProbeRuntime.usesObservableScenarioDriver,
                !didScheduleAbortedDetail
            else {
                return
            }
            didScheduleAbortedDetail = true
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else {
                return
            }
            pushAndRevertDetail()
        }
        .task(id: sceneSessionID) {
            guard
                ProbeRuntime.syntheticReaderDisconnectTarget == window.label,
                sceneSessionID != "unresolved",
                !didScheduleSyntheticReaderDisconnect
            else {
                return
            }
            didScheduleSyntheticReaderDisconnect = true
            ProbeRuntime.record(
                "reader-control scheduled source=\(window.label) native=\(sceneSessionID)"
            )
            try? await Task.sleep(for: .seconds(2.5))
            guard
                !Task.isCancelled,
                let handle = sceneHandle,
                let resolvedWindow = ProbeRuntime.sceneRegistry.window(for: handle),
                let windowScene = resolvedWindow.windowScene,
                windowScene.session.persistentIdentifier == sceneSessionID
            else {
                ProbeRuntime.record(
                    "reader-control skipped source=\(window.label) reason=window-changed"
                )
                return
            }

            let wasConnected = UIApplication.shared.connectedScenes.contains { scene in
                scene === windowScene
            }
            ProbeRuntime.record(
                "reader-control posting synthetic-didDisconnect source=\(window.label) "
                    + "native=\(sceneSessionID) activation=\(windowScene.activationState) "
                    + "platform_connected=\(wasConnected) generation=\(readerControlGeneration)"
            )
            NotificationCenter.default.post(
                name: UIScene.didDisconnectNotification,
                object: windowScene
            )
            let remainsConnected = UIApplication.shared.connectedScenes.contains { scene in
                scene === windowScene
            }
            ProbeRuntime.record(
                "reader-control posted synthetic-didDisconnect source=\(window.label) "
                    + "native=\(sceneSessionID) activation=\(windowScene.activationState) "
                    + "platform_connected=\(remainsConnected)"
            )

            readerControlGeneration += 1
            advanceCurrentRUMViewBindingGeneration()
            await Task.yield()
            registerScene(resolvedWindow)
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else {
                return
            }
            ProbeRuntime.record(
                "reader-control post-update source=\(window.label) native=\(sceneSessionID) "
                + "screen=\(currentSceneScreen) generation=\(readerControlGeneration)"
            )
            ProbeRuntime.emitLifecycleMarker(
                window: window,
                sceneSessionID: sceneSessionID,
                screen: currentSceneScreen,
                phase: "post-retained-reader-remount"
            )
        }
    }

    @ViewBuilder
    private var navigationContent: some View {
        if let destination = keyedManualViewStack.last {
            ProbeKeyedManualView(
                window: window,
                sceneSessionID: sceneSessionID,
                destination: destination
            )
            .id(destination)
        } else if
            ProbeRuntime.usesUIKitSplitLayout
                || ProbeRuntime.usesUIKitSplitSubclass
                || ProbeRuntime.usesUIKitSplitNavigationLayout
        {
            uikitSplitContent
        } else if ProbeRuntime.usesSplitSelectionLayout {
            splitSelectionContent
        } else {
            navigationStack
        }
    }

    private var siblingContainerContent: some View {
        HStack(spacing: 0) {
            NavigationStack {
                ProbeRUMSemanticPresentationBoundary(isEnabled: true) {
                    ProbeSiblingAuthorityView(
                        window: window,
                        sceneSessionID: sceneSessionID,
                        isActive: isSiblingAuthorityActive
                    )
                    .background(
                        ProbeControllerAncestryReader(
                            role: "left-authority",
                            didResolve: recordSiblingControllerAncestry
                        )
                    )
                }
            }
            .frame(minWidth: 240, idealWidth: 280, maxWidth: 320)

            Divider()

            navigationStack
                .frame(maxWidth: .infinity)
        }
        .onAppear {
            beginSiblingContainerObservationIfNeeded()
        }
    }

    @ViewBuilder
    private var uikitSplitContent: some View {
        if sceneSessionID == "unresolved" {
            ProgressView("Resolving scene")
        } else if ProbeRuntime.usesUIKitSplitNavigationLayout {
            ProbeUIKitSplitNavigationControllerRepresentable(
                window: window,
                sceneSessionID: sceneSessionID,
                stepExecutor: uiKitNavigationStepExecutor
            )
        } else {
            ProbeUIKitSplitControllerRepresentable(
                window: window,
                sceneSessionID: sceneSessionID,
                usesApplicationSubclass: ProbeRuntime.usesUIKitSplitSubclass
            )
        }
    }

    @ViewBuilder
    private var splitSelectionContent: some View {
        if sceneSessionID == "unresolved" {
            ProgressView("Resolving scene")
        } else {
            ProbeSplitLayout(
                window: window,
                sceneSessionID: sceneSessionID,
                readerControlGeneration: readerControlGeneration,
                selection: $splitSelection,
                rumViewBindingGeneration: splitRUMViewBindingGeneration,
                navigationOccurrenceSource: splitNavigationOccurrenceSource,
                commitSelection: commitSplitSelection
            )
        }
    }

    private var navigationStack: some View {
        ProbeRUMNavigationStack(
            window: window,
            sceneSessionID: sceneSessionID,
            readerControlGeneration: readerControlGeneration,
            path: navigationPath,
            root: rumView(for: nil),
            destination: rumView(for:),
            bindingGeneration: bindingGeneration(for:),
            navigationOccurrenceSource: navigationOccurrenceSource
        ) {
            ProbeHomeView(
                window: window,
                sceneSessionID: sceneSessionID,
                openDetail: openDetail,
                openSheet: { setSwiftUIPresentation(.sheet) },
                closeCurrentWindow: closeCurrentWindow,
                openPeer: openPeer
            )
            .background {
                if ProbeRuntime.usesSiblingContainerAuthorityStress {
                    ProbeControllerAncestryReader(
                        role: "right-home",
                        didResolve: recordSiblingControllerAncestry
                    )
                }
            }
        } destinationContent: { route in
            Group {
                switch route {
                case .detail(let instance):
                    ProbeDetailView(
                        window: window,
                        sceneSessionID: sceneSessionID,
                        instance: instance,
                        readerControlGeneration: readerControlGeneration,
                        replaceWithAlternate: replaceDetailWithAlternate,
                        didAppear: detailDidAppear
                    )
                    .background {
                        if ProbeRuntime.usesSiblingContainerAuthorityStress {
                            ProbeControllerAncestryReader(
                                role: "right-detail",
                                didResolve: recordSiblingControllerAncestry
                            )
                        }
                    }
                case .alternate:
                    ProbeAlternateView(
                        window: window,
                        sceneSessionID: sceneSessionID
                    )
                }
            }
        }
    }

    private func openDetail() {
        guard !isShowingDetail else {
            return
        }
        navigationPath.wrappedValue = path + [.detail(1)]
    }

    private func replaceDetailWithAlternate() {
        guard isShowingDetail else {
            return
        }
        ProbeRuntime.record("navigation replacement requested source=\(window.label) destination=alternate")
        navigationPath.wrappedValue = [.alternate]
    }

    private func replaceDetailWithNextInstance() {
        guard path.last == .detail(1) else {
            return
        }
        ProbeRuntime.record(
            "navigation replacement requested source=\(window.label) "
                + "destination=detail-2 same_type=true"
        )
        navigationPath.wrappedValue = [.detail(2)]
    }

    private func detailDidAppear() {
        didShowDetail = true
        if isSiblingAuthorityActive {
            // ProbeDetailView records the materialized call-site destination.
            // Restore the authoritative scene route while the left manual view
            // remains current.
            updateSceneRoute()
        }
    }

    private var isShowingDetail: Bool {
        guard case .detail = path.last else {
            return false
        }
        return true
    }

    private var navigationPath: Binding<[ProbeRoute]> {
        Binding(
            get: { path },
            set: { newPath in
                guard newPath != path else {
                    return
                }
                let previousPath = path
                path = newPath
                navigationMutation += 1
                advanceRUMViewBindingGeneration(for: newPath)
                updateSceneRoute()
                ProbeRuntime.eventRecorder.record(
                    ProbeSignal(
                        kind: .navigationPathMutation,
                        semanticContext: ProbeSemanticContext(
                            logicalSceneID: window.label,
                            nativeSceneID: sceneSessionID,
                            screen: currentNavigationScreen
                        ),
                        previousNavigationPath: navigationPathDescription(
                            for: previousPath
                        ),
                        navigationPath: navigationPathDescription(for: newPath),
                        mutation: navigationMutation
                    )
                )
                ProbeRuntime.record(
                    "navigation path mutated source=\(window.label) "
                        + "screen=\(currentNavigationScreen) mutation=\(navigationMutation)"
                )
                #if DEBUG
                if
                    ProbeRuntime.usesNavigationOccurrenceSwiftUIViewTracking,
                    newPath.count < previousPath.count
                {
                    let didReveal = navigationOccurrenceSource.revealRetainedRoute(
                        occurrenceKey: RUMViewOccurrenceKey(
                            navigationOccurrence(for: newPath)
                        ),
                        bindingGeneration: bindingGeneration(for: newPath)
                    )
                    ProbeRuntime.record(
                        "navigation occurrence source source=\(window.label) "
                            + "screen=\(currentNavigationScreen) "
                            + "generation=\(bindingGeneration(for: newPath)) "
                            + "delivered=\(didReveal)"
                    )
                }
                #endif
                if newPath.count < previousPath.count {
                    ProbeRuntime.recordDestination(
                        window: window,
                        sceneSessionID: sceneSessionID,
                        screen: currentNavigationScreen,
                        isCommitted: true
                    )
                }
            }
        )
    }

    private var currentNavigationScreen: String {
        switch path.last {
        case .detail(let instance):
            return "detail-\(instance)"
        case .alternate:
            return "alternate"
        case nil:
            return "home"
        }
    }

    private var currentSceneScreen: String {
        if ProbeRuntime.usesSplitSelectionLayout {
            return splitSelection?.screen ?? "split-empty"
        }
        if isSiblingAuthorityActive {
            return "sibling-authority"
        }
        if let keyedManualDestination = keyedManualViewStack.last {
            return keyedManualDestination.rawValue
        }
        if let swiftUIPresentation {
            return swiftUIPresentation.rawValue
        }
        return currentNavigationScreen
    }

    private var currentSceneRoute: [String] {
        if ProbeRuntime.usesSplitSelectionLayout {
            return splitSelection.map { [$0.screen] } ?? []
        }
        let navigationRoute = navigationPathDescription(for: path)
        if isSiblingAuthorityActive {
            return navigationRoute + ["sibling-authority"]
        }
        if let keyedManualDestination = keyedManualViewStack.last {
            return navigationRoute + [keyedManualDestination.rawValue]
        }
        return swiftUIPresentation.map { navigationRoute + [$0.rawValue] } ?? navigationRoute
    }

    private var sheetPresentation: Binding<Bool> {
        presentationBinding(for: .sheet)
    }

    private var fullScreenCoverPresentation: Binding<Bool> {
        presentationBinding(for: .fullScreenCover)
    }

    private func presentationBinding(
        for presentation: ProbeSwiftUIPresentation
    ) -> Binding<Bool> {
        Binding(
            get: { swiftUIPresentation == presentation },
            set: { isPresented in
                if isPresented {
                    setSwiftUIPresentation(presentation)
                } else if swiftUIPresentation == presentation {
                    setSwiftUIPresentation(nil)
                }
            }
        )
    }

    private func setSwiftUIPresentation(_ presentation: ProbeSwiftUIPresentation?) {
        guard swiftUIPresentation != presentation else {
            return
        }
        guard swiftUIPresentation == nil || presentation == nil else {
            ProbeRuntime.record(
                "rejected direct presentation replacement source=\(window.label) "
                    + "from=\(swiftUIPresentation?.rawValue ?? "none") "
                    + "to=\(presentation?.rawValue ?? "none")"
            )
            return
        }

        let previousPresentation = swiftUIPresentation
        let previousRoute = currentSceneRoute
        if let presentation {
            ProbeRuntime.eventRecorder.record(
                ProbeSignal(
                    kind: .intervalBegan,
                    semanticContext: ProbeSemanticContext(
                        logicalSceneID: window.label,
                        nativeSceneID: sceneSessionID,
                        screen: presentation.rawValue
                    ),
                    interval: presentation.activeInterval
                )
            )
            ProbeRuntime.eventRecorder.record(
                ProbeSignal(
                    kind: .intervalBegan,
                    semanticContext: ProbeSemanticContext(
                        logicalSceneID: window.label,
                        nativeSceneID: sceneSessionID,
                        screen: presentation.rawValue
                    ),
                    interval: presentation.subtreeInterval
                )
            )
        }
        swiftUIPresentation = presentation
        navigationMutation += 1
        updateSceneRoute()
        ProbeRuntime.eventRecorder.record(
            ProbeSignal(
                kind: .navigationPathMutation,
                semanticContext: ProbeSemanticContext(
                    logicalSceneID: window.label,
                    nativeSceneID: sceneSessionID,
                    screen: currentSceneScreen
                ),
                previousNavigationPath: previousRoute,
                navigationPath: currentSceneRoute,
                mutation: navigationMutation
            )
        )
        if ProbeRuntime.usesSceneTargetedPresentationAuthority {
            if let previousPresentation {
                updateSceneTargetedPresentationAuthority(
                    previousPresentation,
                    isPresented: false
                )
            }
            if let presentation {
                updateSceneTargetedPresentationAuthority(presentation, isPresented: true)
            }
        }
        if let previousPresentation {
            ProbeRuntime.eventRecorder.record(
                ProbeSignal(
                    kind: .intervalEnded,
                    semanticContext: ProbeSemanticContext(
                        logicalSceneID: window.label,
                        nativeSceneID: sceneSessionID,
                        screen: currentSceneScreen
                    ),
                    interval: previousPresentation.activeInterval
                )
            )
        }
        ProbeRuntime.record(
            "SwiftUI presentation mutated source=\(window.label) "
                + "from=\(previousPresentation?.rawValue ?? "none") "
                + "to=\(presentation?.rawValue ?? "none") "
                + "mutation=\(navigationMutation)"
        )
    }

    private func updateSceneTargetedPresentationAuthority(
        _ presentation: ProbeSwiftUIPresentation,
        isPresented: Bool
    ) {
        if isPresented {
            #if DEBUG
            guard let monitor = RUMMonitor.shared() as? any RUMSceneTargetedManualViewHandling else {
                recordSceneTargetedManualViewFailure(operation: "\(presentation.rawValue)-start")
                return
            }
            monitor.startView(
                key: presentation.manualViewKey,
                name: presentation.rumViewName,
                attributes: sceneTargetedPresentationAttributes(for: presentation),
                sceneIdentifier: RUMSceneIdentifier(rawValue: sceneSessionID)
            )
            #else
            RUMMonitor.shared().startView(
                key: presentation.manualViewKey,
                name: presentation.rumViewName,
                attributes: sceneTargetedPresentationAttributes(for: presentation)
            )
            #endif
            ProbeRuntime.record(
                "scene-targeted \(presentation.rawValue) started source=\(window.label) "
                    + "native=\(sceneSessionID)"
            )
            return
        }

        #if DEBUG
        guard let monitor = RUMMonitor.shared() as? any RUMSceneTargetedManualViewHandling else {
            recordSceneTargetedManualViewFailure(operation: "\(presentation.rawValue)-stop")
            return
        }
        monitor.stopView(
            key: presentation.manualViewKey,
            attributes: [
                ProbeRuntime.Attribute.runID: window.runID,
                ProbeRuntime.Attribute.sourceScene: window.label,
                ProbeRuntime.Attribute.sceneSessionID: sceneSessionID,
                ProbeRuntime.Attribute.screen: presentation.rawValue
            ],
            sceneIdentifier: RUMSceneIdentifier(rawValue: sceneSessionID)
        )
        #else
        RUMMonitor.shared().stopView(key: presentation.manualViewKey)
        #endif
        ProbeRuntime.record(
            "scene-targeted \(presentation.rawValue) stopped source=\(window.label) "
                + "native=\(sceneSessionID)"
        )
    }

    private func sceneTargetedPresentationAttributes(
        for presentation: ProbeSwiftUIPresentation
    ) -> [String: Encodable] {
        [
            ProbeRuntime.Attribute.runID: window.runID,
            ProbeRuntime.Attribute.host: "native-swiftui-complete-destination",
            ProbeRuntime.Attribute.sourceScene: window.label,
            ProbeRuntime.Attribute.sceneSessionID: sceneSessionID,
            ProbeRuntime.Attribute.screen: presentation.rawValue,
            ProbeRuntime.Attribute.viewScene: window.label,
            ProbeRuntime.Attribute.viewSceneSessionID: sceneSessionID,
            ProbeRuntime.Attribute.viewScreen: presentation.rawValue
        ]
    }

    private func sheetDidDismiss() {
        presentationDidDismiss(.sheet)
    }

    private func fullScreenCoverDidDismiss() {
        presentationDidDismiss(.fullScreenCover)
    }

    private func presentationDidDismiss(_ presentation: ProbeSwiftUIPresentation) {
        ProbeRuntime.eventRecorder.record(
            ProbeSignal(
                kind: .intervalEnded,
                semanticContext: ProbeSemanticContext(
                    logicalSceneID: window.label,
                    nativeSceneID: sceneSessionID,
                    screen: currentNavigationScreen
                ),
                interval: presentation.subtreeInterval
            )
        )
        guard swiftUIPresentation == nil else {
            return
        }
        ProbeRuntime.recordDestination(
            window: window,
            sceneSessionID: sceneSessionID,
            screen: currentNavigationScreen,
            isCommitted: true
        )
        ProbeRuntime.emitLifecycleMarker(
            window: window,
            sceneSessionID: sceneSessionID,
            screen: currentNavigationScreen,
            phase: presentation.dismissedImmediatePhase
        )
        Task { @MainActor in
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, swiftUIPresentation == nil else {
                return
            }
            ProbeRuntime.emitLifecycleMarker(
                window: window,
                sceneSessionID: sceneSessionID,
                screen: currentNavigationScreen,
                phase: presentation.dismissedSettledPhase
            )
        }
    }

    private func openPeer() {
        let peer = ProbeWindow(
            runID: window.runID,
            label: "scene-B",
            opensPeer: false
        )
        ProbeRuntime.record(
            "openWindow invoked source=\(window.label) requested=\(peer.label)"
        )
        openWindow(id: ProbeWindow.windowGroupID, value: peer)
    }

    private func closeCurrentWindow() {
        ProbeRuntime.record("dismissWindow invoked source=\(window.label)")
        dismissWindow(id: ProbeWindow.windowGroupID, value: window)
    }

    private func advanceRUMViewBindingGeneration(for path: [ProbeRoute]) {
        rumViewBindingGeneration &+= 1
        if path.isEmpty {
            homeBindingGeneration = rumViewBindingGeneration
        } else {
            destinationBindingGeneration = rumViewBindingGeneration
        }
    }

    private func advanceCurrentRUMViewBindingGeneration() {
        if ProbeRuntime.usesSplitSelectionLayout {
            splitRUMViewBindingGeneration &+= 1
        } else {
            advanceRUMViewBindingGeneration(for: path)
        }
    }

    private func bindingGeneration(for path: [ProbeRoute]) -> UInt64 {
        path.isEmpty ? homeBindingGeneration : destinationBindingGeneration
    }

    private func bindingGeneration(
        for occurrence: ProbeNavigationOccurrence
    ) -> UInt64 {
        switch occurrence {
        case .home:
            return homeBindingGeneration
        case .detail, .alternate:
            return destinationBindingGeneration
        case .splitDetail, .splitPlaceholder:
            return splitRUMViewBindingGeneration
        }
    }

    private func rumView(for route: ProbeRoute?) -> ProbeRUMNavigationView {
        switch route {
        case .detail(let instance):
            return ProbeRUMNavigationView(
                screen: "detail-\(instance)",
                name: "ProbeDetailView",
                occurrence: .detail(instance)
            )
        case .alternate:
            return ProbeRUMNavigationView(
                screen: "alternate",
                name: "ProbeAlternateView",
                occurrence: .alternate
            )
        case nil:
            return ProbeRUMNavigationView(
                screen: "home",
                name: "ProbeHomeView",
                occurrence: .home
            )
        }
    }

    private func navigationOccurrence(for path: [ProbeRoute]) -> ProbeNavigationOccurrence {
        switch path.last {
        case .detail(let instance):
            return .detail(instance)
        case .alternate:
            return .alternate
        case nil:
            return .home
        }
    }

    private func navigationPathDescription(for path: [ProbeRoute]) -> [String] {
        ["home"] + path.map { route in
            switch route {
            case .detail(let instance):
                return "detail-\(instance)"
            case .alternate:
                return "alternate"
            }
        }
    }

    private func commitSplitSelection(_ newSelection: ProbeSplitSelection) {
        guard splitSelection != newSelection else {
            return
        }
        let previous = splitSelection?.screen ?? "none"
        splitRUMViewBindingGeneration &+= 1
        splitSelection = newSelection
        updateSceneRoute()
        ProbeRuntime.eventRecorder.record(
            ProbeSignal(
                kind: .navigationPathMutation,
                semanticContext: ProbeSemanticContext(
                    logicalSceneID: window.label,
                    nativeSceneID: sceneSessionID,
                    screen: newSelection.screen
                ),
                previousNavigationPath: [previous],
                navigationPath: [newSelection.screen],
                mutation: splitRUMViewBindingGeneration
            )
        )
        ProbeRuntime.record(
            "split selection committed source=\(window.label) "
                + "from=\(previous) to=\(newSelection.screen) "
                + "generation=\(splitRUMViewBindingGeneration)"
        )
        #if DEBUG
        guard ProbeRuntime.usesNavigationOccurrenceSwiftUIViewTracking else {
            return
        }
        let didReveal = splitNavigationOccurrenceSource.revealRetainedRoute(
            occurrenceKey: RUMViewOccurrenceKey(
                navigationOccurrence(for: newSelection)
            ),
            bindingGeneration: splitRUMViewBindingGeneration
        )
        ProbeRuntime.record(
            "split occurrence source source=\(window.label) "
                + "screen=\(newSelection.screen) "
                + "generation=\(splitRUMViewBindingGeneration) "
                + "delivered=\(didReveal)"
        )
        #endif
    }

    private func navigationOccurrence(
        for selection: ProbeSplitSelection
    ) -> ProbeNavigationOccurrence {
        switch selection {
        case .detail(let instance):
            return .splitDetail(instance)
        case .placeholder:
            return .splitPlaceholder
        }
    }

    private func registerScene(_ resolvedWindow: UIWindow) {
        guard let windowScene = resolvedWindow.windowScene else {
            return
        }
        let identifier = windowScene.session.persistentIdentifier
        let previousSnapshot = ProbeRuntime.sceneRegistry.snapshot(
            logicalSceneID: window.label
        )
        let result = ProbeRuntime.sceneRegistry.register(
            logicalSceneID: window.label,
            nativeSceneID: identifier,
            window: resolvedWindow,
            currentRoute: currentSceneRoute
        )

        guard case .registered(let handle) = result else {
            if case .rejected(let reason) = result {
                ProbeRuntime.eventRecorder.record(
                    ProbeSignal(
                        kind: .assertion,
                        semanticContext: ProbeSemanticContext(
                            logicalSceneID: window.label,
                            nativeSceneID: identifier,
                            screen: currentSceneScreen
                        ),
                        result: .fail,
                        reason: "scene registry rejected: \(reason)"
                    )
                )
                ProbeRuntime.record(
                    "scene registry rejected source=\(window.label) "
                        + "native=\(identifier) reason=\(reason)"
                )
            }
            return
        }

        let wasReady = previousSnapshot?.nativeSceneID == identifier
            && previousSnapshot?.disconnectGeneration == handle.disconnectGeneration
            && previousSnapshot?.readiness == .ready
        let didChangeIdentity = sceneHandle != handle
        sceneHandle = handle
        if sceneSessionID != identifier {
            sceneSessionID = identifier
            advanceCurrentRUMViewBindingGeneration()
        }

        guard let snapshot = ProbeRuntime.sceneRegistry.markReady(handle) else {
            return
        }
        if !wasReady {
            ProbeRuntime.recordSceneSnapshot(snapshot, kind: .sceneReady)
        } else if previousSnapshot?.presentation != snapshot.presentation {
            ProbeRuntime.recordSceneSnapshot(snapshot, kind: .sceneGeometry)
        }
        if didChangeIdentity {
            ProbeRuntime.record(
                "scene resolved source=\(window.label) native=\(identifier) "
                    + "generation=\(handle.disconnectGeneration)"
            )
        }
        registerScenarioStepExecutor(handle: handle)
    }

    private func registerScenarioStepExecutor(
        handle: ProbeSceneHandle
    ) {
        guard let driver = ProbeRuntime.scenarioDriver else {
            return
        }
        let logicalSceneID = window.label
        let pathBinding = navigationPath
        scenarioStepExecutor.configure(handle: handle) { step in
            guard step.scene == logicalSceneID else {
                return .rejected(
                    reason: "step targeted \(step.scene ?? "nil"), not \(logicalSceneID)"
                )
            }
            switch step.kind {
            case .openWindow:
                guard
                    window.opensPeer,
                    let targetSceneID = step.value,
                    targetSceneID != logicalSceneID,
                    ProbeRuntime.sceneRegistry.handle(
                        logicalSceneID: targetSceneID
                    ) == nil
                else {
                    return .rejected(
                        reason: "\(logicalSceneID) cannot open \(step.value ?? "nil")"
                    )
                }
                let requestedWindow = ProbeWindow(
                    runID: window.runID,
                    label: targetSceneID,
                    opensPeer: false
                )
                ProbeRuntime.record(
                    "openWindow invoked source=\(logicalSceneID) "
                        + "requested=\(targetSceneID)"
                )
                openWindow(
                    id: ProbeWindow.windowGroupID,
                    value: requestedWindow
                )
            case .closeWindow:
                closeCurrentWindow()
            case .activateWindow:
                guard
                    let resolvedWindow = ProbeRuntime.sceneRegistry.window(for: handle),
                    let windowScene = resolvedWindow.windowScene,
                    windowScene.session.persistentIdentifier == handle.nativeSceneID
                else {
                    return .rejected(
                        reason: "no exact live window for \(logicalSceneID)"
                    )
                }
                ProbeRuntime.record(
                    "scene activation requested source=\(logicalSceneID) "
                        + "native=\(handle.nativeSceneID)"
                )
                UIApplication.shared.requestSceneSessionActivation(
                    windowScene.session,
                    userActivity: nil,
                    options: nil
                ) { _ in
                    ProbeRuntime.eventRecorder.record(
                        ProbeSignal(
                            kind: .assertion,
                            semanticContext: ProbeSemanticContext(
                                logicalSceneID: logicalSceneID,
                                nativeSceneID: handle.nativeSceneID
                            ),
                            result: .fail,
                            reason: "scene activation request failed"
                        )
                    )
                }
                if
                    windowScene.activationState == .foregroundActive,
                    let snapshot = ProbeRuntime.sceneRegistry.updatePresentation(
                        from: resolvedWindow,
                        for: handle
                    )
                {
                    ProbeRuntime.recordSceneSnapshot(snapshot, kind: .sceneLifecycle)
                }
            case .setSwiftUIPath, .replaceSwiftUIDestination:
                guard let value = step.value else {
                    return .rejected(reason: "SwiftUI path is missing")
                }
                switch value {
                case "home":
                    pathBinding.wrappedValue = []
                case "detail-1":
                    pathBinding.wrappedValue = [.detail(1)]
                case "detail-2":
                    pathBinding.wrappedValue = [.detail(2)]
                case "alternate":
                    pathBinding.wrappedValue = [.alternate]
                default:
                    return .rejected(reason: "unsupported SwiftUI path \(value)")
                }
            case .setSwiftUIPresentation:
                guard let value = step.value else {
                    return .rejected(reason: "SwiftUI presentation is missing")
                }
                switch value {
                case "sheet":
                    setSwiftUIPresentation(.sheet)
                case "full-screen-cover":
                    setSwiftUIPresentation(.fullScreenCover)
                case "home":
                    setSwiftUIPresentation(nil)
                default:
                    return .rejected(
                        reason: "unsupported SwiftUI presentation \(value)"
                    )
                }
            case .startKeyedManualView:
                switch step.value {
                case "compose":
                    startKeyedManualView(.compose)
                case "preview":
                    startKeyedManualView(.preview)
                case "sibling-authority"
                    where ProbeRuntime.usesSiblingContainerAuthorityStress:
                    setSiblingAuthorityActive(true)
                default:
                    return .rejected(
                        reason: "unsupported keyed manual view \(step.value ?? "nil")"
                    )
                }
            case .stopKeyedManualView:
                switch step.value {
                case "compose":
                    stopKeyedManualView(.compose)
                case "preview":
                    stopKeyedManualView(.preview)
                case "sibling-authority"
                    where ProbeRuntime.usesSiblingContainerAuthorityStress:
                    setSiblingAuthorityActive(false)
                default:
                    return .rejected(
                        reason: "unsupported keyed manual view \(step.value ?? "nil")"
                    )
                }
            case .pushAndRevertSwiftUIPath:
                guard step.value == "detail-1" else {
                    return .rejected(
                        reason: "unsupported reverted SwiftUI path \(step.value ?? "nil")"
                    )
                }
                pushAndRevertDetail()
            case .setSplitSelection:
                guard let value = step.value else {
                    return .rejected(reason: "split selection is missing")
                }
                let selection: ProbeSplitSelection
                switch value {
                case "detail-1":
                    selection = .detail(1)
                case "detail-2":
                    selection = .detail(2)
                case "placeholder":
                    selection = .placeholder
                default:
                    return .rejected(reason: "unsupported split selection \(value)")
                }
                commitSplitSelection(selection)
            case .beginUIKitInteractiveTransition,
                 .updateUIKitInteractiveTransition,
                 .resolveUIKitInteractiveTransition:
                return uiKitNavigationStepExecutor.execute(step)
            case .emitMarker:
                guard let marker = step.value else {
                    return .rejected(reason: "marker is missing")
                }
                ProbeRuntime.emitLifecycleMarker(
                    window: window,
                    sceneSessionID: handle.nativeSceneID,
                    screen: marker == "sibling-underlying-detail-active"
                        ? currentNavigationScreen
                        : currentSceneScreen,
                    phase: marker
                )
            default:
                return .rejected(
                    reason: "unsupported scene step \(step.kind.rawValue)"
                )
            }
            return .accepted
        }
        driver.register(handle: handle, executor: scenarioStepExecutor)
        driver.startIfNeeded()
    }

    private func updateScenePresentation(kind: ProbeSignalKind) {
        guard
            let handle = sceneHandle,
            let resolvedWindow = ProbeRuntime.sceneRegistry.window(for: handle),
            let previous = ProbeRuntime.sceneRegistry.snapshot(
                logicalSceneID: window.label
            ),
            let snapshot = ProbeRuntime.sceneRegistry.updatePresentation(
                from: resolvedWindow,
                for: handle
            ),
            previous.presentation != snapshot.presentation || kind == .sceneLifecycle
        else {
            return
        }
        ProbeRuntime.recordSceneSnapshot(snapshot, kind: kind)
    }

    private func pushAndRevertDetail() {
        ProbeRuntime.record(
            "navigation abort requested source=\(window.label) destination=detail"
        )
        ProbeRuntime.eventRecorder.record(
            ProbeSignal(
                kind: .intervalBegan,
                semanticContext: ProbeSemanticContext(
                    logicalSceneID: window.label,
                    nativeSceneID: sceneSessionID,
                    screen: "home"
                ),
                interval: "aborted-navigation"
            )
        )
        navigationPath.wrappedValue = [.detail(1)]
        navigationPath.wrappedValue = []

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else {
                return
            }
            ProbeRuntime.eventRecorder.record(
                ProbeSignal(
                    kind: .intervalEnded,
                    semanticContext: ProbeSemanticContext(
                        logicalSceneID: window.label,
                        nativeSceneID: sceneSessionID,
                        screen: "home"
                    ),
                    interval: "aborted-navigation"
                )
            )
            ProbeRuntime.emitLifecycleMarker(
                window: window,
                sceneSessionID: sceneSessionID,
                screen: "home",
                phase: "post-aborted-navigation"
            )
        }
    }

    private func beginSiblingContainerObservationIfNeeded() {
        guard
            ProbeRuntime.usesSiblingContainerAuthorityStress,
            !didBeginSiblingContainerObservation
        else {
            return
        }
        didBeginSiblingContainerObservation = true
        ProbeRuntime.eventRecorder.record(
            ProbeSignal(
                kind: .intervalBegan,
                semanticContext: ProbeSemanticContext(
                    logicalSceneID: window.label,
                    nativeSceneID: sceneSessionID == "unresolved" ? nil : sceneSessionID,
                    screen: "sibling-authority"
                ),
                interval: "sibling-container-observation"
            )
        )
    }

    private func endSiblingContainerObservationIfNeeded() {
        guard
            didBeginSiblingContainerObservation,
            !didEndSiblingContainerObservation
        else {
            return
        }
        didEndSiblingContainerObservation = true
        ProbeRuntime.eventRecorder.record(
            ProbeSignal(
                kind: .intervalEnded,
                semanticContext: ProbeSemanticContext(
                    logicalSceneID: window.label,
                    nativeSceneID: sceneSessionID,
                    screen: currentNavigationScreen
                ),
                interval: "sibling-container-observation"
            )
        )
    }

    private func recordSiblingControllerAncestry(
        role: String,
        ancestry: ProbeControllerAncestry
    ) {
        guard ProbeRuntime.usesSiblingContainerAuthorityStress else {
            return
        }
        if siblingControllerAncestries[role] == ancestry {
            return
        }
        siblingControllerAncestries[role] = ancestry
        let identities = ancestry.identities.map(String.init(describing:))
        ProbeRuntime.record(
            "sibling controller ancestry source=\(window.label) role=\(role) "
                + "classes=\(ancestry.classNames.joined(separator: ">")) "
                + "identities=\(identities.joined(separator: ">"))"
        )
        validateSiblingControllerTopology()
    }

    private func validateSiblingControllerTopology() {
        guard !didReportSiblingControllerTopology else {
            return
        }
        guard
            let left = siblingControllerAncestries["left-authority"],
            let rightHome = siblingControllerAncestries["right-home"],
            let rightDetail = siblingControllerAncestries["right-detail"]
        else {
            return
        }

        let leftIDs = Set(left.identities)
        let rightHomeIndex = rightHome.identities.firstIndex {
            !leftIDs.contains($0)
        }
        let preexistingIDs = leftIDs.union(rightHome.identities)
        let rightDetailIndex = rightDetail.identities.firstIndex {
            !preexistingIDs.contains($0)
        }
        if let rightHomeIndex, let rightDetailIndex {
            reportSiblingControllerTopology(
                result: .pass,
                reason: "right Home and fresh Detail have controller branches outside left authority: "
                    + "home=\(rightHome.classNames[rightHomeIndex]) "
                    + "detail=\(rightDetail.classNames[rightDetailIndex])"
            )
        } else {
            reportSiblingControllerTopology(
                result: .inconclusive,
                reason: "iOS did not expose a fresh right Detail controller branch outside "
                    + "the left authority and right Home ancestries"
            )
        }
    }

    private func reportSiblingControllerTopology(
        result: ProbeSemanticResultState,
        reason: String
    ) {
        guard !didReportSiblingControllerTopology else {
            return
        }
        didReportSiblingControllerTopology = true
        ProbeRuntime.eventRecorder.record(
            ProbeSignal(
                kind: .assertion,
                semanticContext: ProbeSemanticContext(
                    logicalSceneID: window.label,
                    nativeSceneID: sceneSessionID,
                    screen: currentNavigationScreen
                ),
                name: "sibling-controller-topology",
                result: result,
                reason: reason
            )
        )
        ProbeRuntime.record(
            "sibling controller topology source=\(window.label) "
                + "result=\(result.rawValue) reason=\(reason)"
        )
    }

    private func setSiblingAuthorityActive(_ isActive: Bool) {
        guard
            ProbeRuntime.usesSiblingContainerAuthorityStress,
            isSiblingAuthorityActive != isActive
        else {
            return
        }

        if isActive {
            #if DEBUG
            guard let monitor = RUMMonitor.shared() as? any RUMSceneTargetedManualViewHandling else {
                recordSceneTargetedManualViewFailure(operation: "sibling-authority-start")
                return
            }
            #endif
            ProbeRuntime.eventRecorder.record(
                ProbeSignal(
                    kind: .intervalBegan,
                    semanticContext: ProbeSemanticContext(
                        logicalSceneID: window.label,
                        nativeSceneID: sceneSessionID,
                        screen: "sibling-authority"
                    ),
                    interval: "manual-sibling-authority"
                )
            )
            isSiblingAuthorityActive = true
            updateSceneRoute()
            let attributes: [String: Encodable] = [
                ProbeRuntime.Attribute.runID: window.runID,
                ProbeRuntime.Attribute.host: "native-swiftui-sibling-authority",
                ProbeRuntime.Attribute.sourceScene: window.label,
                ProbeRuntime.Attribute.sceneSessionID: sceneSessionID,
                ProbeRuntime.Attribute.screen: "sibling-authority",
                ProbeRuntime.Attribute.viewScene: window.label,
                ProbeRuntime.Attribute.viewSceneSessionID: sceneSessionID,
                ProbeRuntime.Attribute.viewScreen: "sibling-authority"
            ]
            #if DEBUG
            monitor.startView(
                key: "probe-sibling-authority",
                name: "ProbeSiblingAuthorityView",
                attributes: attributes,
                sceneIdentifier: RUMSceneIdentifier(rawValue: sceneSessionID)
            )
            #else
            RUMMonitor.shared().startView(
                key: "probe-sibling-authority",
                name: "ProbeSiblingAuthorityView",
                attributes: attributes
            )
            #endif
            ProbeRuntime.recordDestination(
                window: window,
                sceneSessionID: sceneSessionID,
                screen: "sibling-authority",
                isCommitted: true
            )
            ProbeRuntime.record(
                "sibling manual authority started source=\(window.label) "
                    + "native=\(sceneSessionID)"
            )
            return
        }

        ProbeRuntime.eventRecorder.record(
            ProbeSignal(
                kind: .intervalEnded,
                semanticContext: ProbeSemanticContext(
                    logicalSceneID: window.label,
                    nativeSceneID: sceneSessionID,
                    screen: "sibling-authority"
                ),
                interval: "manual-sibling-authority"
            )
        )
        #if DEBUG
        guard let monitor = RUMMonitor.shared() as? any RUMSceneTargetedManualViewHandling else {
            recordSceneTargetedManualViewFailure(operation: "sibling-authority-stop")
            return
        }
        monitor.stopView(
            key: "probe-sibling-authority",
            attributes: [
                ProbeRuntime.Attribute.runID: window.runID,
                ProbeRuntime.Attribute.sourceScene: window.label,
                ProbeRuntime.Attribute.sceneSessionID: sceneSessionID,
                ProbeRuntime.Attribute.screen: "sibling-authority"
            ],
            sceneIdentifier: RUMSceneIdentifier(rawValue: sceneSessionID)
        )
        #else
        RUMMonitor.shared().stopView(key: "probe-sibling-authority")
        #endif
        isSiblingAuthorityActive = false
        updateSceneRoute()
        ProbeRuntime.recordDestination(
            window: window,
            sceneSessionID: sceneSessionID,
            screen: currentNavigationScreen,
            isCommitted: true
        )
        ProbeRuntime.record(
            "sibling manual authority stopped source=\(window.label) "
                + "native=\(sceneSessionID) revealed=\(currentNavigationScreen)"
        )
        ProbeRuntime.emitLifecycleMarker(
            window: window,
            sceneSessionID: sceneSessionID,
            screen: currentNavigationScreen,
            phase: "sibling-authority-stopped-immediate"
        )
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, !isSiblingAuthorityActive else {
                return
            }
            ProbeRuntime.emitLifecycleMarker(
                window: window,
                sceneSessionID: sceneSessionID,
                screen: currentNavigationScreen,
                phase: "sibling-authority-stopped-settled"
            )
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled, !isSiblingAuthorityActive else {
                return
            }
            endSiblingContainerObservationIfNeeded()
        }
    }

    private func startKeyedManualView(
        _ destination: ProbeKeyedManualDestination
    ) {
        #if DEBUG
        guard let monitor = RUMMonitor.shared() as? any RUMSceneTargetedManualViewHandling else {
            recordSceneTargetedManualViewFailure(operation: "\(destination.rawValue)-start")
            return
        }
        #endif

        let isDuplicate = keyedManualViewStack.contains(destination)
        let duplicateInterval = "duplicate-keyed-manual-start-\(destination.rawValue)"
        if isDuplicate {
            ProbeRuntime.eventRecorder.record(
                ProbeSignal(
                    kind: .intervalBegan,
                    semanticContext: ProbeSemanticContext(
                        logicalSceneID: window.label,
                        nativeSceneID: sceneSessionID,
                        screen: currentSceneScreen
                    ),
                    interval: duplicateInterval
                )
            )
        } else {
            if keyedManualViewStack.isEmpty {
                ProbeRuntime.eventRecorder.record(
                    ProbeSignal(
                        kind: .intervalBegan,
                        semanticContext: ProbeSemanticContext(
                            logicalSceneID: window.label,
                            nativeSceneID: sceneSessionID,
                            screen: currentSceneScreen
                        ),
                        interval: "keyed-manual-authority"
                    )
                )
            }
            keyedManualViewStack.append(destination)
            updateSceneRoute()
        }

        #if DEBUG
        monitor.startView(
            key: destination.manualViewKey,
            name: destination.rumViewName,
            attributes: keyedManualViewAttributes(for: destination),
            sceneIdentifier: RUMSceneIdentifier(rawValue: sceneSessionID)
        )
        #else
        RUMMonitor.shared().startView(
            key: destination.manualViewKey,
            name: destination.rumViewName,
            attributes: keyedManualViewAttributes(for: destination)
        )
        #endif
        ProbeRuntime.record(
            "keyed manual view started source=\(window.label) "
                + "native=\(sceneSessionID) screen=\(destination.rawValue) "
                + "duplicate=\(isDuplicate)"
        )

        guard isDuplicate else {
            return
        }
        ProbeRuntime.emitLifecycleMarker(
            window: window,
            sceneSessionID: sceneSessionID,
            screen: currentSceneScreen,
            phase: duplicateInterval
        )
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            guard
                !Task.isCancelled,
                keyedManualViewStack.contains(destination)
            else {
                return
            }
            ProbeRuntime.eventRecorder.record(
                ProbeSignal(
                    kind: .intervalEnded,
                    semanticContext: ProbeSemanticContext(
                        logicalSceneID: window.label,
                        nativeSceneID: sceneSessionID,
                        screen: currentSceneScreen
                    ),
                    interval: duplicateInterval
                )
            )
            ProbeRuntime.eventRecorder.record(
                ProbeSignal(
                    kind: .assertion,
                    semanticContext: ProbeSemanticContext(
                        logicalSceneID: window.label,
                        nativeSceneID: sceneSessionID,
                        screen: currentSceneScreen
                    ),
                    name: duplicateInterval,
                    result: .pass,
                    reason: "duplicate start reached the SDK without changing the probe destination"
                )
            )
        }
    }

    private func stopKeyedManualView(
        _ destination: ProbeKeyedManualDestination
    ) {
        guard keyedManualViewStack.last == destination else {
            ProbeRuntime.eventRecorder.record(
                ProbeSignal(
                    kind: .assertion,
                    semanticContext: ProbeSemanticContext(
                        logicalSceneID: window.label,
                        nativeSceneID: sceneSessionID,
                        screen: currentSceneScreen
                    ),
                    name: "keyed-manual-stop-\(destination.rawValue)",
                    result: .fail,
                    reason: "attempted to stop a keyed manual destination that was not current"
                )
            )
            return
        }

        #if DEBUG
        guard let monitor = RUMMonitor.shared() as? any RUMSceneTargetedManualViewHandling else {
            recordSceneTargetedManualViewFailure(operation: "\(destination.rawValue)-stop")
            return
        }
        #endif

        if keyedManualViewStack.count == 1 {
            ProbeRuntime.eventRecorder.record(
                ProbeSignal(
                    kind: .intervalEnded,
                    semanticContext: ProbeSemanticContext(
                        logicalSceneID: window.label,
                        nativeSceneID: sceneSessionID,
                        screen: destination.rawValue
                    ),
                    interval: "keyed-manual-authority"
                )
            )
        }
        ProbeRuntime.eventRecorder.record(
            ProbeSignal(
                kind: .intervalBegan,
                semanticContext: ProbeSemanticContext(
                    logicalSceneID: window.label,
                    nativeSceneID: sceneSessionID,
                    screen: destination.rawValue
                ),
                interval: "keyed-manual-stop-\(destination.rawValue)"
            )
        )
        #if DEBUG
        monitor.stopView(
            key: destination.manualViewKey,
            attributes: [
                ProbeRuntime.Attribute.runID: window.runID,
                ProbeRuntime.Attribute.sourceScene: window.label,
                ProbeRuntime.Attribute.sceneSessionID: sceneSessionID,
                ProbeRuntime.Attribute.screen: destination.rawValue
            ],
            sceneIdentifier: RUMSceneIdentifier(rawValue: sceneSessionID)
        )
        #else
        RUMMonitor.shared().stopView(key: destination.manualViewKey)
        #endif
        keyedManualViewStack.removeLast()
        updateSceneRoute()
        let revealedDestination = keyedManualViewStack.last
        let revealedScreen = currentSceneScreen
        let stoppedPhase = destination == .preview
            ? "keyed-manual-preview-stopped"
            : "keyed-manual-stopped"
        ProbeRuntime.record(
            "keyed manual view stopped source=\(window.label) "
                + "native=\(sceneSessionID) screen=\(destination.rawValue) "
                + "revealed=\(revealedScreen)"
        )
        ProbeRuntime.emitLifecycleMarker(
            window: window,
            sceneSessionID: sceneSessionID,
            screen: revealedScreen,
            phase: "\(stoppedPhase)-immediate"
        )
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            guard
                !Task.isCancelled,
                keyedManualViewStack.last == revealedDestination,
                currentSceneScreen == revealedScreen
            else {
                return
            }
            ProbeRuntime.emitLifecycleMarker(
                window: window,
                sceneSessionID: sceneSessionID,
                screen: revealedScreen,
                phase: "\(stoppedPhase)-settled"
            )
            ProbeRuntime.eventRecorder.record(
                ProbeSignal(
                    kind: .intervalEnded,
                    semanticContext: ProbeSemanticContext(
                        logicalSceneID: window.label,
                        nativeSceneID: sceneSessionID,
                        screen: revealedScreen
                    ),
                    interval: "keyed-manual-stop-\(destination.rawValue)"
                )
            )
        }
    }

    private func keyedManualViewAttributes(
        for destination: ProbeKeyedManualDestination
    ) -> [String: Encodable] {
        [
            ProbeRuntime.Attribute.runID: window.runID,
            ProbeRuntime.Attribute.host: "native-swiftui-scene-targeted-manual",
            ProbeRuntime.Attribute.sourceScene: window.label,
            ProbeRuntime.Attribute.sceneSessionID: sceneSessionID,
            ProbeRuntime.Attribute.screen: destination.rawValue,
            ProbeRuntime.Attribute.viewScene: window.label,
            ProbeRuntime.Attribute.viewSceneSessionID: sceneSessionID,
            ProbeRuntime.Attribute.viewScreen: destination.rawValue
        ]
    }

    private func recordSceneTargetedManualViewFailure(operation: String) {
        let reason = "scene-targeted manual view \(operation) is unavailable"
        ProbeRuntime.eventRecorder.record(
            ProbeSignal(
                kind: .assertion,
                semanticContext: ProbeSemanticContext(
                    logicalSceneID: window.label,
                    nativeSceneID: sceneSessionID,
                    screen: currentSceneScreen
                ),
                result: .fail,
                reason: reason
            )
        )
        ProbeRuntime.record(
            "scene-targeted manual view failed source=\(window.label) "
                + "native=\(sceneSessionID) reason=\(reason)"
        )
    }

    private func updateSceneRoute() {
        guard
            let handle = sceneHandle,
            handle.nativeSceneID == sceneSessionID
        else {
            return
        }
        _ = ProbeRuntime.sceneRegistry.updateRoute(
            currentSceneRoute,
            for: handle
        )
    }
}

private struct ProbeSiblingAuthorityView: View {
    let window: ProbeWindow
    let sceneSessionID: String
    let isActive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ProbeHeading(
                window: window,
                sceneSessionID: sceneSessionID,
                screen: "sibling-authority"
            )
            Text("Sibling authority container")
                .font(.headline)
            Text(
                isActive
                    ? "This container is the exact-scene RUM destination."
                    : "This container remains mounted only to test scoped automatic suppression."
            )
            .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(24)
        .navigationTitle("Authority")
        .accessibilityIdentifier("probe.native.\(window.label).sibling-authority")
    }
}

private struct ProbeKeyedManualView: View {
    let window: ProbeWindow
    let sceneSessionID: String
    let destination: ProbeKeyedManualDestination

    @State private var didAppear = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ProbeHeading(
                window: window,
                sceneSessionID: sceneSessionID,
                screen: destination.rawValue
            )
            Text(
                destination == .compose
                    ? "This destination is tracked through the keyed manual RUM API."
                    : "This nested preview temporarily replaces the Compose destination."
            )
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(24)
        .accessibilityIdentifier("probe.native.\(window.label).\(destination.rawValue)")
        .onAppear {
            guard !didAppear else {
                return
            }
            didAppear = true
            ProbeRuntime.recordDestination(
                window: window,
                sceneSessionID: sceneSessionID,
                screen: destination.rawValue,
                isCommitted: true
            )
        }
    }
}

private struct ProbeRouteIdentityModifier<ID: Hashable>: ViewModifier {
    let identity: ID
    let isEnabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.id(identity)
        } else {
            content
        }
    }
}

private struct ProbeSplitLayout: View {
    let window: ProbeWindow
    let sceneSessionID: String
    let readerControlGeneration: Int
    @Binding var selection: ProbeSplitSelection?
    let rumViewBindingGeneration: UInt64
    let navigationOccurrenceSource: ProbeNavigationOccurrenceSource
    let commitSelection: (ProbeSplitSelection) -> Void

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var materializedSelection: ProbeSplitSelection?
    @State private var didScheduleDetailTwo = false
    @State private var didSchedulePlaceholder = false
    @State private var didScheduleReturnedDetail = false
    @State private var didRecordLayout = false

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                NavigationLink(value: ProbeSplitSelection.detail(1)) {
                    Text("Detail 1")
                }
                NavigationLink(value: ProbeSplitSelection.detail(2)) {
                    Text("Detail 2")
                }
                NavigationLink(value: ProbeSplitSelection.placeholder) {
                    Text("Placeholder")
                }
            }
            .navigationTitle("Selections")
            .accessibilityIdentifier("probe.native.\(window.label).split-sidebar")
        } detail: {
            splitDetail
        }
        .navigationSplitViewStyle(.balanced)
        .accessibilityIdentifier("probe.native.\(window.label).split-layout")
        .task {
            guard !didRecordLayout else {
                return
            }
            didRecordLayout = true
            ProbeRuntime.record(
                "split layout materialized source=\(window.label) "
                    + "horizontal_size_class=\(sizeClassDescription) "
                    + "selection=\(selection?.screen ?? "none")"
            )
        }
        .task(id: materializedSelection) {
            guard
                ProbeRuntime.automaticallyAdvancesSplitSelection,
                !ProbeRuntime.usesObservableScenarioDriver
            else {
                return
            }
            guard horizontalSizeClass == .regular else {
                if materializedSelection != nil {
                    ProbeRuntime.record(
                        "split sequence skipped source=\(window.label) "
                            + "reason=non-regular-width size_class=\(sizeClassDescription)"
                    )
                }
                return
            }

            switch materializedSelection {
            case .detail(1) where !didScheduleDetailTwo:
                didScheduleDetailTwo = true
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else {
                    return
                }
                commit(.detail(2))
            case .detail(2) where !didSchedulePlaceholder:
                didSchedulePlaceholder = true
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else {
                    return
                }
                commit(.placeholder)
            case .placeholder
                where ProbeRuntime.automaticallyReturnsSplitToDetail
                    && !didScheduleReturnedDetail:
                didScheduleReturnedDetail = true
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else {
                    return
                }
                commit(.detail(2))
            default:
                return
            }
        }
    }

    @ViewBuilder
    private var splitDetail: some View {
        switch selection {
        case .detail(let instance):
            ProbeRUMTrackedScreen(
                window: window,
                sceneSessionID: sceneSessionID,
                screen: "detail-\(instance)",
                name: "ProbeSplitDetailView",
                trackingBoundary: .navigationRoute,
                readerControlGeneration: readerControlGeneration,
                navigationOccurrence: .splitDetail(instance),
                bindingGeneration: rumViewBindingGeneration,
                navigationOccurrenceSource: navigationOccurrenceSource
            ) {
                ProbeSplitDetailView(
                    window: window,
                    sceneSessionID: sceneSessionID,
                    instance: instance,
                    materialized: materialized
                )
            }
            .modifier(
                ProbeRouteIdentityModifier(
                    identity: ProbeSplitSelection.detail(instance),
                    isEnabled: ProbeRuntime.forcesNavigationRouteIdentity
                        && !ProbeRuntime.usesNavigationOccurrenceSwiftUIViewTracking
                )
            )
        case .placeholder:
            ProbeRUMTrackedScreen(
                window: window,
                sceneSessionID: sceneSessionID,
                screen: "placeholder",
                name: "ProbeSplitPlaceholderView",
                trackingBoundary: .navigationRoute,
                readerControlGeneration: readerControlGeneration,
                navigationOccurrence: .splitPlaceholder,
                bindingGeneration: rumViewBindingGeneration,
                navigationOccurrenceSource: navigationOccurrenceSource
            ) {
                ProbeSplitPlaceholderView(
                    window: window,
                    sceneSessionID: sceneSessionID,
                    materialized: materialized
                )
            }
            .modifier(
                ProbeRouteIdentityModifier(
                    identity: ProbeSplitSelection.placeholder,
                    isEnabled: ProbeRuntime.forcesNavigationRouteIdentity
                        && !ProbeRuntime.usesNavigationOccurrenceSwiftUIViewTracking
                )
            )
        case nil:
            Text("Select a destination")
                .accessibilityIdentifier("probe.native.\(window.label).split-empty")
        }
    }

    private func commit(_ newSelection: ProbeSplitSelection) {
        commitSelection(newSelection)
    }

    private func materialized(_ newSelection: ProbeSplitSelection) {
        guard materializedSelection != newSelection else {
            return
        }
        materializedSelection = newSelection
        ProbeRuntime.record(
            "split selection materialized source=\(window.label) "
                + "screen=\(newSelection.screen)"
        )
        ProbeRuntime.recordDestination(
            window: window,
            sceneSessionID: sceneSessionID,
            screen: newSelection.screen,
            isCommitted: true
        )
        ProbeRuntime.emitLifecycleMarker(
            window: window,
            sceneSessionID: sceneSessionID,
            screen: newSelection.screen,
            phase: "selection-committed"
        )
    }

    private var sizeClassDescription: String {
        switch horizontalSizeClass {
        case .compact:
            return "compact"
        case .regular:
            return "regular"
        case nil:
            return "unspecified"
        @unknown default:
            return "unknown"
        }
    }
}

private struct ProbeSplitDetailView: View {
    let window: ProbeWindow
    let sceneSessionID: String
    let instance: Int
    let materialized: (ProbeSplitSelection) -> Void

    @State private var lastMaterializedInstance: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ProbeHeading(
                window: window,
                sceneSessionID: sceneSessionID,
                screen: screen
            )
            Text("Regular-width split selection Detail \(instance).")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(24)
        .navigationTitle("\(window.label): Split Detail \(instance)")
        .accessibilityIdentifier("probe.native.\(window.label).split-detail-\(instance)")
        .background(
            ProbeSplitDetailTrackingWitness(
                window: window,
                route: screen
            )
        )
        .task(id: instance) {
            guard lastMaterializedInstance != instance else {
                return
            }
            lastMaterializedInstance = instance
            materialized(.detail(instance))
        }
    }

    private var screen: String {
        "detail-\(instance)"
    }
}

private struct ProbeSplitPlaceholderView: View {
    let window: ProbeWindow
    let sceneSessionID: String
    let materialized: (ProbeSplitSelection) -> Void

    @State private var didMaterialize = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ProbeHeading(
                window: window,
                sceneSessionID: sceneSessionID,
                screen: "placeholder"
            )
            Text("Different-type split selection placeholder.")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(24)
        .navigationTitle("\(window.label): Split Placeholder")
        .accessibilityIdentifier("probe.native.\(window.label).split-placeholder")
        .background(
            ProbeSplitPlaceholderTrackingWitness(window: window)
        )
        .task {
            guard !didMaterialize else {
                return
            }
            didMaterialize = true
            materialized(.placeholder)
        }
    }
}

private struct ProbeSplitDetailTrackingWitness: UIViewRepresentable {
    let window: ProbeWindow
    let route: String

    func makeUIView(context: Context) -> ProbeSplitDetailTrackingWitnessView {
        let view = ProbeSplitDetailTrackingWitnessView()
        view.route = route
        ProbeRuntime.record(
            "split tracking witness created source=\(window.label) "
                + "kind=detail route=\(route) object=\(ObjectIdentifier(view))"
        )
        return view
    }

    func updateUIView(_ uiView: ProbeSplitDetailTrackingWitnessView, context: Context) {
        guard uiView.route != route else {
            return
        }
        let previousRoute = uiView.route
        uiView.route = route
        ProbeRuntime.record(
            "split tracking witness retained source=\(window.label) "
                + "kind=detail from=\(previousRoute) to=\(route) "
                + "object=\(ObjectIdentifier(uiView))"
        )
    }
}

private final class ProbeSplitDetailTrackingWitnessView: UIView {
    var route = "unresolved"
}

private struct ProbeSplitPlaceholderTrackingWitness: UIViewRepresentable {
    let window: ProbeWindow

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        ProbeRuntime.record(
            "split tracking witness created source=\(window.label) "
                + "kind=placeholder route=placeholder object=\(ObjectIdentifier(view))"
        )
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

internal protocol ProbeUIKitSplitChildLifecycleDelegate: AnyObject {
    func splitChildDidAppear(_ child: ProbeUIKitSplitChildViewController)
}

private struct ProbeUIKitSplitControllerRepresentable: UIViewControllerRepresentable {
    let window: ProbeWindow
    let sceneSessionID: String
    let usesApplicationSubclass: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(window: window, sceneSessionID: sceneSessionID)
    }

    func makeUIViewController(context: Context) -> UISplitViewController {
        let splitViewController: UISplitViewController
        if usesApplicationSubclass {
            splitViewController = ProbeUIKitSplitViewController(
                sourceScene: window.label,
                sceneSessionID: sceneSessionID
            )
        } else {
            splitViewController = UISplitViewController(style: .doubleColumn)
        }
        splitViewController.preferredDisplayMode = .oneBesideSecondary
        splitViewController.preferredSplitBehavior = .tile

        let primary = ProbeUIKitSplitPrimaryViewController(
            window: window,
            sceneSessionID: sceneSessionID,
            screen: "uikit-primary"
        )
        primary.lifecycleDelegate = context.coordinator

        let placeholder = UIViewController()
        placeholder.view.backgroundColor = .secondarySystemBackground
        placeholder.view.accessibilityIdentifier =
            "probe.native.\(window.label).uikit-split-empty-secondary"

        context.coordinator.connect(
            splitViewController: splitViewController,
            primary: primary
        )
        splitViewController.setViewController(primary, for: .primary)
        splitViewController.setViewController(placeholder, for: .secondary)

        ProbeRuntime.record(
            "uikit split container created source=\(window.label) "
                + "native=\(sceneSessionID) "
                + "kind=\(usesApplicationSubclass ? "application-subclass" : "stock") "
                + "container=\(ObjectIdentifier(splitViewController)) "
                + "primary=\(ObjectIdentifier(primary)) "
                + "placeholder=\(ObjectIdentifier(placeholder))"
        )
        return splitViewController
    }

    func updateUIViewController(
        _ uiViewController: UISplitViewController,
        context: Context
    ) {}

    static func dismantleUIViewController(
        _ uiViewController: UISplitViewController,
        coordinator: Coordinator
    ) {
        coordinator.disconnect()
    }

    final class Coordinator: NSObject, ProbeUIKitSplitChildLifecycleDelegate {
        private let window: ProbeWindow
        private let sceneSessionID: String
        private weak var splitViewController: UISplitViewController?
        private weak var primary: ProbeUIKitSplitPrimaryViewController?
        private var installSecondaryWorkItem: DispatchWorkItem?
        private var replaceSecondaryWorkItem: DispatchWorkItem?
        private var didInstallSecondary = false
        private var didReplaceSecondary = false

        init(window: ProbeWindow, sceneSessionID: String) {
            self.window = window
            self.sceneSessionID = sceneSessionID
        }

        func connect(
            splitViewController: UISplitViewController,
            primary: ProbeUIKitSplitPrimaryViewController
        ) {
            self.splitViewController = splitViewController
            self.primary = primary
        }

        func splitChildDidAppear(_ child: ProbeUIKitSplitChildViewController) {
            ProbeRuntime.record(
                "uikit split child materialized source=\(window.label) "
                    + "native=\(sceneSessionID) screen=\(child.screen) "
                    + "object=\(ObjectIdentifier(child)) "
                    + "horizontal_size_class=\(child.horizontalSizeClassDescription)"
            )
            emitMarker(afterMaterializing: child)

            if child is ProbeUIKitSplitPrimaryViewController {
                scheduleSecondaryOne(after: child)
            } else if
                let secondary = child as? ProbeUIKitSplitSecondaryViewController,
                secondary.instance == 1
            {
                scheduleSecondaryTwo(after: secondary)
            }
        }

        func disconnect() {
            installSecondaryWorkItem?.cancel()
            replaceSecondaryWorkItem?.cancel()
            ProbeRuntime.record(
                "uikit split representable dismantled source=\(window.label) "
                    + "native=\(sceneSessionID)"
            )
        }

        private func emitMarker(afterMaterializing child: ProbeUIKitSplitChildViewController) {
            DispatchQueue.main.async { [weak self, weak child] in
                guard
                    let self,
                    let child,
                    child.viewIfLoaded?.window != nil
                else {
                    return
                }
                ProbeRuntime.emitLifecycleMarker(
                    window: self.window,
                    sceneSessionID: self.sceneSessionID,
                    screen: child.screen,
                    phase: "post-materialization"
                )
            }
        }

        private func scheduleSecondaryOne(after primary: ProbeUIKitSplitChildViewController) {
            guard !didInstallSecondary else {
                return
            }
            didInstallSecondary = true
            let workItem = DispatchWorkItem { [weak self, weak primary] in
                guard
                    let self,
                    let splitViewController = self.splitViewController,
                    let primary,
                    primary.viewIfLoaded?.window != nil
                else {
                    return
                }
                let secondary = ProbeUIKitSplitSecondaryViewController(
                    window: self.window,
                    sceneSessionID: self.sceneSessionID,
                    screen: "uikit-secondary-1",
                    instance: 1
                )
                secondary.lifecycleDelegate = self
                ProbeRuntime.record(
                    "uikit split secondary installed source=\(self.window.label) "
                        + "native=\(self.sceneSessionID) screen=\(secondary.screen) "
                        + "object=\(ObjectIdentifier(secondary)) "
                        + "primary=\(ObjectIdentifier(primary))"
                )
                splitViewController.setViewController(secondary, for: .secondary)
            }
            installSecondaryWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: workItem)
        }

        private func scheduleSecondaryTwo(after secondaryOne: ProbeUIKitSplitSecondaryViewController) {
            guard !didReplaceSecondary else {
                return
            }
            didReplaceSecondary = true
            let workItem = DispatchWorkItem { [weak self, weak secondaryOne] in
                guard
                    let self,
                    let splitViewController = self.splitViewController,
                    let secondaryOne,
                    splitViewController.viewController(for: .secondary) === secondaryOne
                else {
                    return
                }
                let secondaryTwo = ProbeUIKitSplitSecondaryViewController(
                    window: self.window,
                    sceneSessionID: self.sceneSessionID,
                    screen: "uikit-secondary-2",
                    instance: 2
                )
                secondaryTwo.lifecycleDelegate = self
                ProbeRuntime.record(
                    "uikit split secondary replaced source=\(self.window.label) "
                        + "native=\(self.sceneSessionID) "
                        + "from=\(ObjectIdentifier(secondaryOne)) "
                        + "to=\(ObjectIdentifier(secondaryTwo)) "
                        + "primary=\(self.primary.map { String(describing: ObjectIdentifier($0)) } ?? "nil") "
                        + "primary_visible=\(self.primary?.viewIfLoaded?.window != nil)"
                )
                splitViewController.setViewController(secondaryTwo, for: .secondary)
            }
            replaceSecondaryWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: workItem)
        }
    }
}

@MainActor
private final class ProbeUIKitNavigationStepExecutor {
    private var ownerID: ObjectIdentifier?
    private var executeStep: ((ProbeStep) -> ProbeStepExecutionResult)?

    func configure(
        owner: AnyObject,
        execute: @escaping (ProbeStep) -> ProbeStepExecutionResult
    ) {
        ownerID = ObjectIdentifier(owner)
        executeStep = execute
    }

    func disconnect(owner: AnyObject) {
        guard ownerID == ObjectIdentifier(owner) else {
            return
        }
        ownerID = nil
        executeStep = nil
    }

    func execute(_ step: ProbeStep) -> ProbeStepExecutionResult {
        guard let executeStep else {
            return .rejected(reason: "UIKit navigation executor is not configured")
        }
        return executeStep(step)
    }
}

private struct ProbeUIKitSplitNavigationControllerRepresentable: UIViewControllerRepresentable {
    let window: ProbeWindow
    let sceneSessionID: String
    let stepExecutor: ProbeUIKitNavigationStepExecutor

    func makeCoordinator() -> Coordinator {
        Coordinator(
            window: window,
            sceneSessionID: sceneSessionID,
            stepExecutor: stepExecutor
        )
    }

    func makeUIViewController(context: Context) -> UISplitViewController {
        let splitViewController = UISplitViewController(style: .doubleColumn)
        splitViewController.preferredDisplayMode = .oneBesideSecondary
        splitViewController.preferredSplitBehavior = .tile

        let primary = ProbeUIKitSplitPrimaryViewController(
            window: window,
            sceneSessionID: sceneSessionID,
            screen: "uikit-navigation-primary"
        )
        primary.lifecycleDelegate = context.coordinator

        let placeholder = UIViewController()
        placeholder.view.backgroundColor = .secondarySystemBackground
        placeholder.view.accessibilityIdentifier =
            "probe.native.\(window.label).uikit-split-navigation-empty-secondary"

        context.coordinator.connect(
            splitViewController: splitViewController,
            primary: primary
        )
        splitViewController.setViewController(primary, for: .primary)
        splitViewController.setViewController(placeholder, for: .secondary)

        ProbeRuntime.record(
            "uikit split navigation container created source=\(window.label) "
                + "native=\(sceneSessionID) "
                + "container=\(ObjectIdentifier(splitViewController)) "
                + "primary=\(ObjectIdentifier(primary)) "
                + "placeholder=\(ObjectIdentifier(placeholder))"
        )
        return splitViewController
    }

    func updateUIViewController(
        _ uiViewController: UISplitViewController,
        context: Context
    ) {}

    static func dismantleUIViewController(
        _ uiViewController: UISplitViewController,
        coordinator: Coordinator
    ) {
        coordinator.disconnect()
    }

    final class Coordinator: NSObject, ProbeUIKitSplitChildLifecycleDelegate, UINavigationControllerDelegate {
        private let window: ProbeWindow
        private let sceneSessionID: String
        private weak var stepExecutor: ProbeUIKitNavigationStepExecutor?
        private weak var splitViewController: UISplitViewController?
        private weak var primary: ProbeUIKitSplitPrimaryViewController?
        private weak var navigationController: UINavigationController?
        private weak var secondaryOne: ProbeUIKitSplitSecondaryViewController?
        private var installNavigationWorkItem: DispatchWorkItem?
        private var pushWorkItem: DispatchWorkItem?
        private var popWorkItem: DispatchWorkItem?
        private var interactiveResolutionWorkItem: DispatchWorkItem?
        private var interactivePopTransition: UIPercentDrivenInteractiveTransition?
        private var interactiveTransitionID: String?
        private var interactiveInterval: String?
        private var interactiveRequestedOutcome: ProbeTransitionOutcome?
        private let interactivePopAnimator = ProbeUIKitSplitPopAnimator()
        private var didInstallNavigation = false
        private var didPushSecondaryTwo = false
        private var didPopSecondaryTwo = false

        init(
            window: ProbeWindow,
            sceneSessionID: String,
            stepExecutor: ProbeUIKitNavigationStepExecutor
        ) {
            self.window = window
            self.sceneSessionID = sceneSessionID
            self.stepExecutor = stepExecutor
        }

        func connect(
            splitViewController: UISplitViewController,
            primary: ProbeUIKitSplitPrimaryViewController
        ) {
            self.splitViewController = splitViewController
            self.primary = primary
            stepExecutor?.configure(owner: self) { [weak self] step in
                self?.execute(step) ?? .rejected(
                    reason: "UIKit navigation coordinator disappeared"
                )
            }
        }

        func splitChildDidAppear(_ child: ProbeUIKitSplitChildViewController) {
            ProbeRuntime.record(
                "uikit split navigation child materialized source=\(window.label) "
                    + "native=\(sceneSessionID) screen=\(child.screen) "
                    + "appearance=\(child.appearanceCount) "
                    + "object=\(ObjectIdentifier(child)) "
                    + "horizontal_size_class=\(child.horizontalSizeClassDescription)"
            )

            if child is ProbeUIKitSplitPrimaryViewController {
                if !ProbeRuntime.usesObservableScenarioDriver {
                    emitMarker(afterMaterializing: child, phase: "post-materialization")
                }
                scheduleNavigationInstallation(after: child)
            } else if
                let secondary = child as? ProbeUIKitSplitSecondaryViewController,
                secondary.instance == 1
            {
                let phase = secondary.appearanceCount == 1
                    ? "post-materialization"
                    : "post-return-materialization"
                emitMarker(afterMaterializing: secondary, phase: phase)
                if secondary.appearanceCount == 1 {
                    schedulePush(after: secondary)
                }
            } else if
                let secondary = child as? ProbeUIKitSplitSecondaryViewController,
                secondary.instance == 2
            {
                emitMarker(afterMaterializing: secondary, phase: "post-materialization")
                schedulePop(after: secondary)
            }
        }

        func disconnect() {
            installNavigationWorkItem?.cancel()
            pushWorkItem?.cancel()
            popWorkItem?.cancel()
            interactiveResolutionWorkItem?.cancel()
            interactivePopTransition?.cancel()
            navigationController?.delegate = nil
            stepExecutor?.disconnect(owner: self)
            ProbeRuntime.record(
                "uikit split navigation representable dismantled source=\(window.label) "
                    + "native=\(sceneSessionID)"
            )
        }

        private func emitMarker(
            afterMaterializing child: ProbeUIKitSplitChildViewController,
            phase: String
        ) {
            DispatchQueue.main.async { [weak self, weak child] in
                guard
                    let self,
                    let child,
                    child.viewIfLoaded?.window != nil
                else {
                    return
                }
                ProbeRuntime.emitLifecycleMarker(
                    window: self.window,
                    sceneSessionID: self.sceneSessionID,
                    screen: child.screen,
                    phase: phase
                )
            }
        }

        private func scheduleNavigationInstallation(
            after primary: ProbeUIKitSplitChildViewController
        ) {
            guard !didInstallNavigation else {
                return
            }
            didInstallNavigation = true
            let workItem = DispatchWorkItem { [weak self, weak primary] in
                guard
                    let self,
                    let splitViewController = self.splitViewController,
                    let primary,
                    primary.viewIfLoaded?.window != nil
                else {
                    return
                }
                let secondaryOne = ProbeUIKitSplitSecondaryViewController(
                    window: self.window,
                    sceneSessionID: self.sceneSessionID,
                    screen: "uikit-navigation-secondary-1",
                    instance: 1
                )
                secondaryOne.lifecycleDelegate = self
                let navigationController = UINavigationController(
                    rootViewController: secondaryOne
                )
                navigationController.delegate = self
                navigationController.view.accessibilityIdentifier =
                    "probe.native.\(self.window.label).uikit-split-navigation-secondary"
                self.navigationController = navigationController
                self.secondaryOne = secondaryOne

                ProbeRuntime.record(
                    "uikit split navigation installed source=\(self.window.label) "
                        + "native=\(self.sceneSessionID) "
                        + "navigation=\(ObjectIdentifier(navigationController)) "
                        + "root=\(ObjectIdentifier(secondaryOne)) "
                        + "primary=\(ObjectIdentifier(primary))"
                )
                splitViewController.setViewController(navigationController, for: .secondary)
            }
            installNavigationWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: workItem)
        }

        private func schedulePush(after secondaryOne: ProbeUIKitSplitSecondaryViewController) {
            guard !didPushSecondaryTwo else {
                return
            }
            didPushSecondaryTwo = true
            let workItem = DispatchWorkItem { [weak self, weak secondaryOne] in
                guard
                    let self,
                    let navigationController = self.navigationController,
                    let secondaryOne,
                    navigationController.topViewController === secondaryOne
                else {
                    return
                }
                let secondaryTwo = ProbeUIKitSplitSecondaryViewController(
                    window: self.window,
                    sceneSessionID: self.sceneSessionID,
                    screen: "uikit-navigation-secondary-2",
                    instance: 2
                )
                secondaryTwo.lifecycleDelegate = self
                ProbeRuntime.record(
                    "uikit split navigation push source=\(self.window.label) "
                        + "native=\(self.sceneSessionID) "
                        + "navigation=\(ObjectIdentifier(navigationController)) "
                        + "root=\(ObjectIdentifier(secondaryOne)) "
                        + "pushed=\(ObjectIdentifier(secondaryTwo)) "
                        + "primary=\(self.primary.map { String(describing: ObjectIdentifier($0)) } ?? "nil") "
                        + "primary_visible=\(self.primary?.viewIfLoaded?.window != nil)"
                )
                navigationController.pushViewController(secondaryTwo, animated: false)
            }
            pushWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: workItem)
        }

        private func schedulePop(after secondaryTwo: ProbeUIKitSplitSecondaryViewController) {
            if ProbeRuntime.usesObservableScenarioDriver {
                ProbeRuntime.record(
                    "uikit split navigation awaiting driven pop source=\(window.label) "
                        + "native=\(sceneSessionID) top=\(ObjectIdentifier(secondaryTwo))"
                )
                return
            }
            if let outcome = ProbeRuntime.uiKitSplitInteractivePopOutcome {
                scheduleInteractivePop(after: secondaryTwo, outcome: outcome)
                return
            }
            guard ProbeRuntime.automaticallyPopsUIKitSplitNavigation else {
                ProbeRuntime.record(
                    "uikit split navigation automatic pop skipped source=\(window.label) "
                        + "native=\(sceneSessionID) "
                        + "top=\(ObjectIdentifier(secondaryTwo))"
                )
                return
            }
            guard !didPopSecondaryTwo else {
                return
            }
            didPopSecondaryTwo = true
            let workItem = DispatchWorkItem { [weak self, weak secondaryTwo] in
                guard
                    let self,
                    let navigationController = self.navigationController,
                    let secondaryOne = self.secondaryOne,
                    let secondaryTwo,
                    navigationController.topViewController === secondaryTwo
                else {
                    return
                }
                ProbeRuntime.record(
                    "uikit split navigation pop source=\(self.window.label) "
                        + "native=\(self.sceneSessionID) "
                        + "navigation=\(ObjectIdentifier(navigationController)) "
                        + "from=\(ObjectIdentifier(secondaryTwo)) "
                        + "returning=\(ObjectIdentifier(secondaryOne)) "
                        + "primary=\(self.primary.map { String(describing: ObjectIdentifier($0)) } ?? "nil") "
                        + "primary_visible=\(self.primary?.viewIfLoaded?.window != nil)"
                )
                navigationController.popViewController(animated: false)
            }
            popWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: workItem)
        }

        private func scheduleInteractivePop(
            after secondaryTwo: ProbeUIKitSplitSecondaryViewController,
            outcome: ProbeRuntime.UIKitSplitInteractivePopOutcome
        ) {
            let workItem = DispatchWorkItem { [weak self, weak secondaryTwo] in
                guard
                    let self,
                    let secondaryTwo,
                    self.navigationController?.topViewController === secondaryTwo
                else {
                    return
                }
                let semanticOutcome: ProbeTransitionOutcome = outcome == .cancel
                    ? .cancel
                    : .finish
                guard case .accepted = self.beginInteractivePop(outcome: semanticOutcome) else {
                    return
                }
                DispatchQueue.main.async { [weak self] in
                    guard let self else {
                        return
                    }
                    guard case .accepted = self.updateInteractivePop(percentage: 0.35) else {
                        return
                    }
                    let resolution = DispatchWorkItem { [weak self] in
                        guard let self else {
                            return
                        }
                        _ = self.resolveInteractivePop(outcome: semanticOutcome)
                    }
                    self.interactiveResolutionWorkItem = resolution
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: resolution)
                }
            }
            popWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: workItem)
        }

        private func execute(_ step: ProbeStep) -> ProbeStepExecutionResult {
            switch step.kind {
            case .beginUIKitInteractiveTransition:
                guard let outcome = step.outcome else {
                    return .rejected(reason: "UIKit transition outcome is missing")
                }
                return beginInteractivePop(outcome: outcome)
            case .updateUIKitInteractiveTransition:
                guard let percentage = step.percentage else {
                    return .rejected(reason: "UIKit transition percentage is missing")
                }
                return updateInteractivePop(percentage: percentage)
            case .resolveUIKitInteractiveTransition:
                guard let outcome = step.outcome else {
                    return .rejected(reason: "UIKit transition outcome is missing")
                }
                return resolveInteractivePop(outcome: outcome)
            default:
                return .rejected(reason: "unsupported UIKit navigation step \(step.kind.rawValue)")
            }
        }

        private func beginInteractivePop(
            outcome: ProbeTransitionOutcome
        ) -> ProbeStepExecutionResult {
            guard !didPopSecondaryTwo, interactivePopTransition == nil else {
                return .rejected(reason: "UIKit transition is already active or resolved")
            }
            guard
                let navigationController,
                let secondaryOne,
                let secondaryTwo = navigationController.topViewController
                    as? ProbeUIKitSplitSecondaryViewController,
                secondaryTwo.instance == 2
            else {
                return .rejected(reason: "UIKit secondary-2 is not ready to pop")
            }

            let transition = UIPercentDrivenInteractiveTransition()
            transition.completionCurve = .easeInOut
            transition.completionSpeed = 0.75
            let transitionID = "uikit-pop-\(UUID().uuidString.lowercased())"
            let interval = outcome == .cancel ? "cancelled-pop" : "finished-pop"
            interactivePopTransition = transition
            interactiveTransitionID = transitionID
            interactiveInterval = interval
            interactiveRequestedOutcome = outcome
            didPopSecondaryTwo = true

            ProbeRuntime.eventRecorder.record(
                ProbeSignal(
                    kind: .intervalBegan,
                    semanticContext: transitionContext(screen: "secondary-2"),
                    interval: interval,
                    transitionID: transitionID
                )
            )
            ProbeRuntime.record(
                "uikit split navigation interactive pop started source=\(window.label) "
                    + "native=\(sceneSessionID) outcome=\(outcome.rawValue) "
                    + "navigation=\(ObjectIdentifier(navigationController)) "
                    + "from=\(ObjectIdentifier(secondaryTwo)) "
                    + "returning=\(ObjectIdentifier(secondaryOne))"
            )

            guard navigationController.popViewController(animated: true) === secondaryTwo else {
                clearInteractivePopState()
                didPopSecondaryTwo = false
                recordTransitionFailure(
                    reason: "deterministic UIKit pop was rejected",
                    transitionID: transitionID
                )
                return .rejected(reason: "deterministic UIKit pop was rejected")
            }

            guard let coordinator = navigationController.transitionCoordinator else {
                transition.cancel()
                clearInteractivePopState()
                recordTransitionFailure(
                    reason: "deterministic UIKit pop had no transition coordinator",
                    transitionID: transitionID
                )
                return .rejected(reason: "deterministic UIKit pop had no transition coordinator")
            }

            ProbeRuntime.eventRecorder.record(
                ProbeSignal(
                    kind: .transitionBegan,
                    semanticContext: transitionContext(screen: "secondary-2"),
                    interval: interval,
                    transitionID: transitionID,
                    interactive: true,
                    outcome: outcome
                )
            )

            _ = coordinator.animate(
                alongsideTransition: nil,
                completion: { [weak self, weak navigationController] context in
                    guard let self, let navigationController else {
                        return
                    }
                    self.completeInteractivePop(
                        context: context,
                        navigationController: navigationController,
                        requestedOutcome: outcome,
                        transitionID: transitionID,
                        interval: interval
                    )
                }
            )
            return .accepted
        }

        private func updateInteractivePop(
            percentage: Double
        ) -> ProbeStepExecutionResult {
            guard (0...1).contains(percentage) else {
                return .rejected(reason: "UIKit transition percentage is outside 0...1")
            }
            guard
                let transition = interactivePopTransition,
                let transitionID = interactiveTransitionID,
                let interval = interactiveInterval
            else {
                return .rejected(reason: "no active UIKit transition to update")
            }
            transition.update(percentage)
            ProbeRuntime.eventRecorder.record(
                ProbeSignal(
                    kind: .transitionProgress,
                    semanticContext: transitionContext(screen: "secondary-2"),
                    interval: interval,
                    transitionID: transitionID,
                    interactive: true,
                    transitionProgress: percentage
                )
            )
            return .accepted
        }

        private func resolveInteractivePop(
            outcome: ProbeTransitionOutcome
        ) -> ProbeStepExecutionResult {
            guard
                let transition = interactivePopTransition,
                let transitionID = interactiveTransitionID,
                let interval = interactiveInterval,
                interactiveRequestedOutcome == outcome
            else {
                return .rejected(reason: "no matching UIKit transition to resolve")
            }
            ProbeRuntime.eventRecorder.record(
                ProbeSignal(
                    kind: .transitionResolutionRequested,
                    semanticContext: transitionContext(screen: "secondary-2"),
                    interval: interval,
                    transitionID: transitionID,
                    interactive: true,
                    outcome: outcome
                )
            )
            switch outcome {
            case .cancel:
                transition.cancel()
            case .finish:
                transition.finish()
            }
            return .accepted
        }

        private func completeInteractivePop(
            context: UIViewControllerTransitionCoordinatorContext,
            navigationController: UINavigationController,
            requestedOutcome: ProbeTransitionOutcome,
            transitionID: String,
            interval: String
        ) {
            let observedOutcome: ProbeTransitionOutcome = context.isCancelled
                ? .cancel
                : .finish
            let resolvedScreen = context.isCancelled
                ? "secondary-2"
                : "secondary-1"
            ProbeRuntime.eventRecorder.record(
                ProbeSignal(
                    kind: .transitionResolved,
                    semanticContext: transitionContext(screen: resolvedScreen),
                    interval: interval,
                    transitionID: transitionID,
                    interactive: true,
                    outcome: observedOutcome
                )
            )
            ProbeRuntime.eventRecorder.record(
                ProbeSignal(
                    kind: .intervalEnded,
                    semanticContext: transitionContext(screen: resolvedScreen),
                    interval: interval,
                    transitionID: transitionID
                )
            )
            if observedOutcome != requestedOutcome {
                recordTransitionFailure(
                    reason: "UIKit transition resolved \(observedOutcome.rawValue), requested \(requestedOutcome.rawValue)",
                    transitionID: transitionID
                )
            }
            ProbeRuntime.emitLifecycleMarker(
                window: window,
                sceneSessionID: sceneSessionID,
                screen: resolvedScreen,
                phase: "post-\(observedOutcome.rawValue)-resolution"
            )
            let top = navigationController.topViewController.map {
                String(describing: ObjectIdentifier($0))
            } ?? "nil"
            ProbeRuntime.record(
                "uikit split navigation interactive pop completed source=\(window.label) "
                    + "native=\(sceneSessionID) requested=\(requestedOutcome.rawValue) "
                    + "observed=\(observedOutcome.rawValue) top=\(top)"
            )
            clearInteractivePopState()
        }

        private func transitionContext(screen: String) -> ProbeSemanticContext {
            ProbeSemanticContext(
                logicalSceneID: window.label,
                nativeSceneID: sceneSessionID,
                screen: screen
            )
        }

        private func recordTransitionFailure(
            reason: String,
            transitionID: String
        ) {
            ProbeRuntime.eventRecorder.record(
                ProbeSignal(
                    kind: .assertion,
                    semanticContext: transitionContext(screen: "secondary-2"),
                    transitionID: transitionID,
                    result: .fail,
                    reason: reason
                )
            )
            ProbeRuntime.record(
                "uikit split navigation interactive pop failed source=\(window.label) "
                    + "native=\(sceneSessionID) reason=\(reason)"
            )
        }

        private func clearInteractivePopState() {
            interactivePopTransition = nil
            interactiveTransitionID = nil
            interactiveInterval = nil
            interactiveRequestedOutcome = nil
        }

        func navigationController(
            _ navigationController: UINavigationController,
            animationControllerFor operation: UINavigationController.Operation,
            from fromViewController: UIViewController,
            to toViewController: UIViewController
        ) -> UIViewControllerAnimatedTransitioning? {
            guard operation == .pop, interactivePopTransition != nil else {
                return nil
            }
            return interactivePopAnimator
        }

        func navigationController(
            _ navigationController: UINavigationController,
            interactionControllerFor animationController: UIViewControllerAnimatedTransitioning
        ) -> UIViewControllerInteractiveTransitioning? {
            interactivePopTransition
        }
    }
}

private final class ProbeUIKitSplitPopAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        0.6
    }

    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        guard
            let fromViewController = transitionContext.viewController(forKey: .from),
            let toViewController = transitionContext.viewController(forKey: .to),
            let fromView = transitionContext.view(forKey: .from),
            let toView = transitionContext.view(forKey: .to)
        else {
            transitionContext.completeTransition(false)
            return
        }

        let container = transitionContext.containerView
        let finalFrame = transitionContext.finalFrame(for: toViewController)
        let width = max(finalFrame.width, fromViewController.view.bounds.width)
        toView.frame = finalFrame
        toView.transform = CGAffineTransform(translationX: -0.25 * width, y: 0)
        container.insertSubview(toView, belowSubview: fromView)

        UIView.animate(
            withDuration: transitionDuration(using: transitionContext),
            delay: 0,
            options: [.curveLinear, .allowUserInteraction],
            animations: {
                fromView.transform = CGAffineTransform(translationX: width, y: 0)
                toView.transform = .identity
            },
            completion: { _ in
                let didComplete = !transitionContext.transitionWasCancelled
                fromView.transform = .identity
                toView.transform = .identity
                if !didComplete {
                    toView.removeFromSuperview()
                }
                transitionContext.completeTransition(didComplete)
            }
        )
    }
}

internal class ProbeUIKitSplitChildViewController: UIViewController {
    let window: ProbeWindow
    let sceneSessionID: String
    let screen: String
    weak var lifecycleDelegate: ProbeUIKitSplitChildLifecycleDelegate?

    private(set) var appearanceCount = 0

    var semanticRUMScreen: String {
        for prefix in ["uikit-navigation-", "uikit-"] where screen.hasPrefix(prefix) {
            return String(screen.dropFirst(prefix.count))
        }
        return screen
    }

    init(window: ProbeWindow, sceneSessionID: String, screen: String) {
        self.window = window
        self.sceneSessionID = sceneSessionID
        self.screen = screen
        super.init(nibName: nil, bundle: nil)
        recordLifecycle("created")
    }

    required init?(coder: NSCoder) {
        window = ProbeWindow(
            runID: ProbeRuntime.runID,
            label: "decoded",
            opensPeer: false
        )
        sceneSessionID = "unresolved"
        screen = "decoded"
        super.init(coder: coder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .preferredFont(forTextStyle: .title2)
        titleLabel.numberOfLines = 0
        titleLabel.text = "UIKit split RUM probe\n\(window.label): \(screen)"
        view.addSubview(titleLabel)
        var constraints = [
            titleLabel.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24)
        ]

        if ProbeRuntime.exercisesUIEventContextHandoff {
            let handoffButton = UIButton(type: .system)
            handoffButton.translatesAutoresizingMaskIntoConstraints = false
            handoffButton.configuration = .filled()
            handoffButton.configuration?.title = "Emit scoped manual marker"
            handoffButton.accessibilityIdentifier = [
                ProbeRuntime.uiEventHandoffControlAccessibilityIdentifier,
                window.label,
                screen
            ].joined(separator: ".")
            handoffButton.accessibilityLabel = "Emit scoped marker \(window.label) \(screen)"
            handoffButton.addTarget(
                self,
                action: #selector(emitUIEventHandoffMarkers),
                for: .touchUpInside
            )
            view.addSubview(handoffButton)
            constraints.append(contentsOf: [
                handoffButton.leadingAnchor.constraint(
                    equalTo: view.layoutMarginsGuide.leadingAnchor
                ),
                handoffButton.topAnchor.constraint(
                    equalTo: titleLabel.bottomAnchor,
                    constant: 24
                )
            ])
        }

        NSLayoutConstraint.activate(constraints)
        view.accessibilityIdentifier = "probe.native.\(window.label).\(screen)"
        recordLifecycle("viewDidLoad")
    }

    @objc
    private func emitUIEventHandoffMarkers() {
        ProbeRuntime.record(
            "uikit ui-event handoff control invoked source=\(window.label) "
                + "native=\(sceneSessionID) screen=\(screen)"
        )
        ProbeRuntime.emitLifecycleMarker(
            window: window,
            sceneSessionID: sceneSessionID,
            screen: screen,
            phase: "ui-event-synchronous"
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self else {
                return
            }
            ProbeRuntime.emitLifecycleMarker(
                window: self.window,
                sceneSessionID: self.sceneSessionID,
                screen: self.screen,
                phase: "post-ui-event-async"
            )
        }
    }

    override func willMove(toParent parent: UIViewController?) {
        recordLifecycle(
            "willMove parent=\(parent.map { String(describing: type(of: $0)) } ?? "nil")"
        )
        super.willMove(toParent: parent)
    }

    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        recordLifecycle(
            "didMove parent=\(parent.map { String(describing: type(of: $0)) } ?? "nil")"
        )
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        recordLifecycle("viewWillAppear")
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        appearanceCount += 1
        recordLifecycle("viewDidAppear appearance=\(appearanceCount)")
        ProbeRuntime.recordDestination(
            window: window,
            sceneSessionID: sceneSessionID,
            screen: semanticRUMScreen,
            isCommitted: false,
            occurrence: appearanceCount
        )
        lifecycleDelegate?.splitChildDidAppear(self)
    }

    override func viewWillDisappear(_ animated: Bool) {
        recordLifecycle("viewWillDisappear")
        super.viewWillDisappear(animated)
    }

    override func viewDidDisappear(_ animated: Bool) {
        recordLifecycle("viewDidDisappear")
        super.viewDidDisappear(animated)
    }

    var horizontalSizeClassDescription: String {
        switch traitCollection.horizontalSizeClass {
        case .compact:
            return "compact"
        case .regular:
            return "regular"
        case .unspecified:
            return "unspecified"
        @unknown default:
            return "unknown"
        }
    }

    private func recordLifecycle(_ phase: String) {
        ProbeRuntime.record(
            "uikit split child lifecycle source=\(window.label) "
                + "native=\(sceneSessionID) screen=\(screen) "
                + "type=\(String(describing: type(of: self))) "
                + "object=\(ObjectIdentifier(self)) phase=\(phase)"
        )
    }
}

private final class ProbeUIKitSplitPrimaryViewController: ProbeUIKitSplitChildViewController {}

private final class ProbeUIKitSplitSecondaryViewController: ProbeUIKitSplitChildViewController {
    let instance: Int

    init(window: ProbeWindow, sceneSessionID: String, screen: String, instance: Int) {
        self.instance = instance
        super.init(window: window, sceneSessionID: sceneSessionID, screen: screen)
    }

    required init?(coder: NSCoder) {
        instance = 0
        super.init(coder: coder)
    }
}

private final class ProbeUIKitSplitViewController: UISplitViewController {
    private var sourceScene = "unresolved"
    private var sceneSessionID = "unresolved"

    init(sourceScene: String, sceneSessionID: String) {
        self.sourceScene = sourceScene
        self.sceneSessionID = sceneSessionID
        super.init(style: .doubleColumn)
        recordLifecycle("created")
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        recordLifecycle("viewDidLoad")
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        recordLifecycle("viewWillAppear")
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        recordLifecycle("viewDidAppear")
    }

    override func viewWillDisappear(_ animated: Bool) {
        recordLifecycle("viewWillDisappear")
        super.viewWillDisappear(animated)
    }

    override func viewDidDisappear(_ animated: Bool) {
        recordLifecycle("viewDidDisappear")
        super.viewDidDisappear(animated)
    }

    private func recordLifecycle(_ phase: String) {
        ProbeRuntime.record(
            "uikit split container lifecycle source=\(sourceScene) "
                + "native=\(sceneSessionID) object=\(ObjectIdentifier(self)) "
                + "phase=\(phase)"
        )
    }
}

private struct ProbeOffscreenTabView: View {
    let window: ProbeWindow

    var body: some View {
        Text("This tab must remain unselected during the preload stress run.")
            .onAppear {
                ProbeRuntime.record("offscreen tab appeared source=\(window.label)")
            }
            .onDisappear {
                ProbeRuntime.record("offscreen tab disappeared source=\(window.label)")
            }
    }
}

private struct ProbeHomeView: View {
    let window: ProbeWindow
    let sceneSessionID: String
    let openDetail: () -> Void
    let openSheet: () -> Void
    let closeCurrentWindow: () -> Void
    let openPeer: () -> Void

    @State private var didAppear = false
    @State private var didRunTask = false
    @State private var stateWitness = UUID()
    @State private var appearanceCount = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ProbeHeading(
                window: window,
                sceneSessionID: sceneSessionID,
                screen: "home"
            )

            Button("Open detail") {
                ProbeRuntime.record("tap handler source=\(window.label) target=detail")
                openDetail()
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("probe.native.\(window.label).open-detail")

            Button("Present sheet") {
                ProbeRuntime.record("tap handler source=\(window.label) target=sheet")
                openSheet()
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("probe.native.\(window.label).present-sheet")

            Button("Emit current-view marker") {
                emit(phase: "manual-marker")
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("probe.native.\(window.label).emit-marker")

            Button("Close this window") {
                closeCurrentWindow()
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("probe.native.\(window.label).close-window")

            Button("Open scene B") {
                ProbeRuntime.record("tap handler source=\(window.label) target=scene-B")
                openPeer()
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("probe.native.\(window.label).open-scene-B")

            Spacer()
        }
        .padding(24)
        .navigationTitle("\(window.label): Home")
        .accessibilityIdentifier("probe.native.\(window.label).home")
        .onAppear {
            if ProbeRuntime.usesNavigationOccurrenceSwiftUIViewTracking {
                appearanceCount += 1
                ProbeRuntime.record(
                    "navigation state witness source=\(window.label) screen=home "
                        + "token=\(stateWitness.uuidString.lowercased()) "
                        + "appearance=\(appearanceCount)"
                )
                emit(phase: "navigation-appearance-\(appearanceCount)")
            }
            ProbeRuntime.recordDestination(
                window: window,
                sceneSessionID: sceneSessionID,
                screen: "home",
                isCommitted: false,
                occurrence: ProbeRuntime.usesNavigationOccurrenceSwiftUIViewTracking
                    ? appearanceCount
                    : nil
            )
            guard !didAppear else {
                return
            }
            didAppear = true
            emit(phase: "on-appear")
        }
        .task {
            guard !didRunTask else {
                return
            }
            didRunTask = true
            emit(phase: "task-immediate")
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else {
                return
            }
            emit(phase: "task-delayed")
        }
    }

    private func emit(phase: String) {
        ProbeRuntime.emitLifecycleMarker(
            window: window,
            sceneSessionID: sceneSessionID,
            screen: "home",
            phase: phase
        )
    }
}

private struct ProbeSheetView: View {
    let window: ProbeWindow
    let sceneSessionID: String

    @Environment(\.dismiss) private var dismiss
    @State private var didAppear = false
    @State private var didRunTask = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ProbeHeading(
                window: window,
                sceneSessionID: sceneSessionID,
                screen: "sheet"
            )
            Text("This screen is presented as a SwiftUI sheet.")
                .foregroundStyle(.secondary)
            Button("Dismiss sheet") {
                ProbeRuntime.record("tap handler source=\(window.label) target=dismiss-sheet")
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("probe.native.\(window.label).dismiss-sheet")
            Spacer()
        }
        .padding(24)
        .accessibilityIdentifier("probe.native.\(window.label).sheet")
        .onAppear {
            guard !didAppear else {
                return
            }
            didAppear = true
            ProbeRuntime.recordDestination(
                window: window,
                sceneSessionID: sceneSessionID,
                screen: "sheet",
                isCommitted: true
            )
            emit(phase: "on-appear")
        }
        .task {
            guard !didRunTask else {
                return
            }
            didRunTask = true
            emit(phase: "task-immediate")
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else {
                return
            }
            emit(phase: "task-delayed")
        }
    }

    private func emit(phase: String) {
        ProbeRuntime.emitLifecycleMarker(
            window: window,
            sceneSessionID: sceneSessionID,
            screen: "sheet",
            phase: phase
        )
    }
}

private struct ProbeFullScreenCoverView: View {
    let window: ProbeWindow
    let sceneSessionID: String

    @Environment(\.dismiss) private var dismiss
    @State private var didAppear = false
    @State private var didRunTask = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ProbeHeading(
                window: window,
                sceneSessionID: sceneSessionID,
                screen: ProbeSwiftUIPresentation.fullScreenCover.rawValue
            )
            Text("This screen is presented as a SwiftUI full-screen cover.")
                .foregroundStyle(.secondary)
            Button("Dismiss full-screen cover") {
                ProbeRuntime.record(
                    "tap handler source=\(window.label) target=dismiss-full-screen-cover"
                )
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier(
                "probe.native.\(window.label).dismiss-full-screen-cover"
            )
            Spacer()
        }
        .padding(24)
        .accessibilityIdentifier("probe.native.\(window.label).full-screen-cover")
        .onAppear {
            guard !didAppear else {
                return
            }
            didAppear = true
            ProbeRuntime.recordDestination(
                window: window,
                sceneSessionID: sceneSessionID,
                screen: ProbeSwiftUIPresentation.fullScreenCover.rawValue,
                isCommitted: true
            )
            emit(phase: "on-appear")
        }
        .task {
            guard !didRunTask else {
                return
            }
            didRunTask = true
            emit(phase: "task-immediate")
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else {
                return
            }
            emit(phase: "task-delayed")
        }
    }

    private func emit(phase: String) {
        ProbeRuntime.emitLifecycleMarker(
            window: window,
            sceneSessionID: sceneSessionID,
            screen: ProbeSwiftUIPresentation.fullScreenCover.rawValue,
            phase: phase
        )
    }
}

private struct ProbeDetailView: View {
    let window: ProbeWindow
    let sceneSessionID: String
    let instance: Int
    let readerControlGeneration: Int
    let replaceWithAlternate: () -> Void
    let didAppear: () -> Void

    @State private var emittedAppearance = false
    @State private var didRunTask = false
    @State private var stateWitness = UUID()
    @State private var bindingUpdateCount = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ProbeHeading(
                window: window,
                sceneSessionID: sceneSessionID,
                screen: screen
            )
            Text("This is Detail navigation occurrence \(instance).")
                .foregroundStyle(.secondary)
            Button("Replace with alternate") {
                replaceWithAlternate()
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("probe.native.\(window.label).replace-detail")
            Spacer()
        }
        .padding(24)
        .navigationTitle("\(window.label): Detail \(instance)")
        .accessibilityIdentifier("probe.native.\(window.label).detail-\(instance)")
        .background(
            ProbeDestinationReader(
                window: window,
                route: screen,
                readerControlGeneration: readerControlGeneration
            )
        )
        .onChange(of: instance, initial: true) { _, instance in
            ProbeRuntime.recordDestination(
                window: window,
                sceneSessionID: sceneSessionID,
                screen: "detail-\(instance)",
                isCommitted: true
            )
            guard ProbeRuntime.usesNavigationOccurrenceSwiftUIViewTracking else {
                return
            }
            bindingUpdateCount += 1
            ProbeRuntime.record(
                "navigation state witness source=\(window.label) screen=detail-\(instance) "
                    + "token=\(stateWitness.uuidString.lowercased()) "
                    + "binding_update=\(bindingUpdateCount)"
            )
            emit(phase: "binding-update-\(bindingUpdateCount)")
        }
        .onAppear {
            guard !emittedAppearance else {
                return
            }
            emittedAppearance = true
            emit(phase: "on-appear")
            didAppear()
        }
        .task {
            guard !didRunTask else {
                return
            }
            didRunTask = true
            emit(phase: "task-immediate")
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else {
                return
            }
            emit(phase: "task-delayed")
        }
    }

    private func emit(phase: String) {
        ProbeRuntime.emitLifecycleMarker(
            window: window,
            sceneSessionID: sceneSessionID,
            screen: screen,
            phase: phase
        )
    }

    private var screen: String {
        "detail-\(instance)"
    }
}

private struct ProbeAlternateView: View {
    let window: ProbeWindow
    let sceneSessionID: String

    @State private var didAppear = false
    @State private var didRunTask = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ProbeHeading(
                window: window,
                sceneSessionID: sceneSessionID,
                screen: "alternate"
            )
            Text("This screen replaces Detail in the bound path.")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(24)
        .navigationTitle("\(window.label): Alternate")
        .accessibilityIdentifier("probe.native.\(window.label).alternate")
        .onAppear {
            guard !didAppear else {
                return
            }
            didAppear = true
            ProbeRuntime.recordDestination(
                window: window,
                sceneSessionID: sceneSessionID,
                screen: "alternate",
                isCommitted: true
            )
            emit(phase: "on-appear")
        }
        .task {
            guard !didRunTask else {
                return
            }
            didRunTask = true
            emit(phase: "task-immediate")
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else {
                return
            }
            emit(phase: "task-delayed")
        }
    }

    private func emit(phase: String) {
        ProbeRuntime.emitLifecycleMarker(
            window: window,
            sceneSessionID: sceneSessionID,
            screen: "alternate",
            phase: phase
        )
    }
}

private struct ProbeHeading: View {
    let window: ProbeWindow
    let sceneSessionID: String
    let screen: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Native SwiftUI RUM probe")
                .font(.title2)
            Text("run: \(window.runID)")
            Text("source: \(window.label)")
            Text("native session: \(sceneSessionID)")
            Text("screen: \(screen)")
        }
        .fontDesign(.monospaced)
    }
}

private struct SceneSessionReader: UIViewRepresentable {
    let resolve: (UIWindow) -> Void

    func makeUIView(context: Context) -> SceneSessionReaderView {
        let view = SceneSessionReaderView()
        view.resolve = resolve
        return view
    }

    func updateUIView(_ uiView: SceneSessionReaderView, context: Context) {
        uiView.resolve = resolve
        uiView.resolveIfPossible()
    }
}

private final class SceneSessionReaderView: UIView {
    private struct Resolution: Equatable {
        let windowID: ObjectIdentifier
        let nativeSceneID: String
        let frame: CGRect
        let horizontalSizeClass: UIUserInterfaceSizeClass
        let verticalSizeClass: UIUserInterfaceSizeClass
        let activationState: ProbeSceneActivationState
    }

    var resolve: ((UIWindow) -> Void)?
    private var lastResolution: Resolution?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        resolveIfPossible()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        resolveIfPossible()
    }

    func resolveIfPossible() {
        guard
            let window,
            let identifier = window.windowScene?.session.persistentIdentifier
        else {
            return
        }
        let resolution = Resolution(
            windowID: ObjectIdentifier(window),
            nativeSceneID: identifier,
            frame: window.frame,
            horizontalSizeClass: window.traitCollection.horizontalSizeClass,
            verticalSizeClass: window.traitCollection.verticalSizeClass,
            activationState: ProbeSceneActivationState(
                window.windowScene?.activationState
            )
        )
        guard resolution != lastResolution else {
            return
        }
        lastResolution = resolution
        DispatchQueue.main.async { [weak self, weak window] in
            guard
                let self,
                let window,
                self.window === window,
                window.windowScene?.session.persistentIdentifier == identifier
            else {
                return
            }
            self.resolve?(window)
        }
    }
}

private struct ProbeDestinationReader: UIViewRepresentable {
    let window: ProbeWindow
    let route: String
    let readerControlGeneration: Int

    func makeUIView(context: Context) -> ProbeDestinationReaderView {
        let view = ProbeDestinationReaderView()
        view.route = route
        view.readerControlGeneration = readerControlGeneration
        ProbeRuntime.record(
            "destination reader created source=\(window.label) route=\(route) "
                + "generation=\(readerControlGeneration) object=\(ObjectIdentifier(view))"
        )
        return view
    }

    func updateUIView(_ uiView: ProbeDestinationReaderView, context: Context) {
        if uiView.readerControlGeneration != readerControlGeneration {
            let previousGeneration = uiView.readerControlGeneration
            uiView.readerControlGeneration = readerControlGeneration
            ProbeRuntime.record(
                "destination reader retained-update source=\(window.label) route=\(route) "
                    + "from_generation=\(previousGeneration) "
                    + "to_generation=\(readerControlGeneration) "
                    + "object=\(ObjectIdentifier(uiView))"
            )
        }
        guard uiView.route != route else {
            return
        }
        let previousRoute = uiView.route
        uiView.route = route
        ProbeRuntime.record(
            "destination reader reused source=\(window.label) "
                + "from=\(previousRoute) to=\(route)"
        )
    }
}

private final class ProbeDestinationReaderView: UIView {
    var route = "unresolved"
    var readerControlGeneration = 0
}
