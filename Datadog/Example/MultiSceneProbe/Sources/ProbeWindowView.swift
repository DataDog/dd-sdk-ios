/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import SwiftUI
import UIKit

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

private struct ProbeRUMTrackedScreen<Content: View>: View {
    let window: ProbeWindow
    let sceneSessionID: String
    let screen: String
    let name: String
    let trackingBoundary: ProbeTrackingBoundary
    let readerControlGeneration: Int
    @ViewBuilder let content: Content

    @ViewBuilder
    var body: some View {
        if usesExplicitTracking {
            content.trackRUMView(
                name: name,
                attributes: [
                    ProbeRuntime.Attribute.runID: window.runID,
                    ProbeRuntime.Attribute.host: ProbeRuntime.usesNavigationPathSwiftUIViewTracking
                        ? "native-swiftui-navigation-path"
                        : "native-swiftui",
                    ProbeRuntime.Attribute.sourceScene: window.label,
                    ProbeRuntime.Attribute.sceneSessionID: sceneSessionID,
                    ProbeRuntime.Attribute.screen: screen,
                    ProbeRuntime.Attribute.readerControlGeneration: readerControlGeneration
                ]
            )
        } else {
            content
        }
    }

    private var usesExplicitTracking: Bool {
        if ProbeRuntime.usesAutomaticSwiftUIViewTracking {
            return false
        }
        if ProbeRuntime.usesNavigationPathSwiftUIViewTracking {
            return trackingBoundary == .navigationRoute
        }
        return true
    }
}

struct ProbeWindowRoot: View {
    let window: ProbeWindow

    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var path: [ProbeRoute] = []
    @State private var navigationMutation = 0
    @State private var sceneSessionID = "unresolved"
    @State private var sceneWindow: UIWindow?
    @State private var readerControlGeneration = 0
    @State private var didScheduleNavigation = false
    @State private var didShowDetail = false
    @State private var didOpenPeer = false
    @State private var isSheetPresented = false
    @State private var didScheduleClose = false
    @State private var didScheduleAbortedDetail = false
    @State private var didScheduleDetailReplacement = false
    @State private var didScheduleDetailInstanceReplacement = false
    @State private var didScheduleSyntheticReaderDisconnect = false

    var body: some View {
        Group {
            if ProbeRuntime.usesTabPreloadStress {
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
        .sheet(isPresented: $isSheetPresented) {
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
        .background(
            SceneSessionReader { resolvedWindow in
                let identifier = resolvedWindow.windowScene?.session.persistentIdentifier
                    ?? "unresolved"
                sceneWindow = resolvedWindow
                guard sceneSessionID != identifier else {
                    return
                }
                sceneSessionID = identifier
                ProbeRuntime.record(
                    "scene resolved source=\(window.label) native=\(identifier)"
                )
            }
        )
        .accessibilityIdentifier("probe.native.root.\(window.label)")
        .task {
            guard
                ProbeRuntime.automaticallyNavigates,
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
        .task(id: didShowDetail) {
            guard
                didShowDetail,
                ProbeRuntime.automaticallyReplacesDetail,
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
                !didScheduleAbortedDetail
            else {
                return
            }
            didScheduleAbortedDetail = true
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else {
                return
            }
            ProbeRuntime.record("navigation abort requested source=\(window.label) destination=detail")
            navigationPath.wrappedValue = [.detail(1)]
            navigationPath.wrappedValue = []
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else {
                return
            }
            ProbeRuntime.emitLifecycleMarker(
                window: window,
                sceneSessionID: sceneSessionID,
                screen: "home",
                phase: "post-aborted-navigation"
            )
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
                let sceneWindow,
                let windowScene = sceneWindow.windowScene,
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
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else {
                return
            }
            ProbeRuntime.record(
                "reader-control post-update source=\(window.label) native=\(sceneSessionID) "
                    + "screen=\(currentNavigationScreen) generation=\(readerControlGeneration)"
            )
            ProbeRuntime.emitLifecycleMarker(
                window: window,
                sceneSessionID: sceneSessionID,
                screen: currentNavigationScreen,
                phase: "post-retained-reader-remount"
            )
        }
    }

    @ViewBuilder
    private var navigationContent: some View {
        if
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

    @ViewBuilder
    private var uikitSplitContent: some View {
        if sceneSessionID == "unresolved" {
            ProgressView("Resolving scene")
        } else if ProbeRuntime.usesUIKitSplitNavigationLayout {
            ProbeUIKitSplitNavigationControllerRepresentable(
                window: window,
                sceneSessionID: sceneSessionID
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
                readerControlGeneration: readerControlGeneration
            )
        }
    }

    private var navigationStack: some View {
        NavigationStack(path: navigationPath) {
            ProbeRUMTrackedScreen(
                window: window,
                sceneSessionID: sceneSessionID,
                screen: "home",
                name: "ProbeHomeView",
                trackingBoundary: .navigationRoute,
                readerControlGeneration: readerControlGeneration
            ) {
                ProbeHomeView(
                    window: window,
                    sceneSessionID: sceneSessionID,
                    openDetail: openDetail,
                    openSheet: { isSheetPresented = true },
                    closeCurrentWindow: closeCurrentWindow,
                    openPeer: openPeer
                )
            }
            .navigationDestination(for: ProbeRoute.self) { route in
                switch route {
                case .detail(let instance):
                    ProbeRUMTrackedScreen(
                        window: window,
                        sceneSessionID: sceneSessionID,
                        screen: "detail-\(instance)",
                        name: "ProbeDetailView",
                        trackingBoundary: .navigationRoute,
                        readerControlGeneration: readerControlGeneration
                    ) {
                        ProbeDetailView(
                            window: window,
                            sceneSessionID: sceneSessionID,
                            instance: instance,
                            readerControlGeneration: readerControlGeneration,
                            replaceWithAlternate: replaceDetailWithAlternate,
                            didAppear: { didShowDetail = true }
                        )
                    }
                    .modifier(
                        ProbeRouteIdentityModifier(
                            identity: route,
                            isEnabled: ProbeRuntime.forcesNavigationRouteIdentity
                        )
                    )
                case .alternate:
                    ProbeRUMTrackedScreen(
                        window: window,
                        sceneSessionID: sceneSessionID,
                        screen: "alternate",
                        name: "ProbeAlternateView",
                        trackingBoundary: .navigationRoute,
                        readerControlGeneration: readerControlGeneration
                    ) {
                        ProbeAlternateView(
                            window: window,
                            sceneSessionID: sceneSessionID
                        )
                    }
                    .modifier(
                        ProbeRouteIdentityModifier(
                            identity: route,
                            isEnabled: ProbeRuntime.forcesNavigationRouteIdentity
                        )
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
                path = newPath
                navigationMutation += 1
                ProbeRuntime.record(
                    "navigation path mutated source=\(window.label) "
                        + "screen=\(currentNavigationScreen) mutation=\(navigationMutation)"
                )
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

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selection: ProbeSplitSelection? = .detail(1)
    @State private var materializedSelection: ProbeSplitSelection?
    @State private var didScheduleDetailTwo = false
    @State private var didSchedulePlaceholder = false
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
                readerControlGeneration: readerControlGeneration
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
                )
            )
        case .placeholder:
            ProbeRUMTrackedScreen(
                window: window,
                sceneSessionID: sceneSessionID,
                screen: "placeholder",
                name: "ProbeSplitPlaceholderView",
                trackingBoundary: .navigationRoute,
                readerControlGeneration: readerControlGeneration
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
                )
            )
        case nil:
            Text("Select a destination")
                .accessibilityIdentifier("probe.native.\(window.label).split-empty")
        }
    }

    private func commit(_ newSelection: ProbeSplitSelection) {
        guard selection != newSelection else {
            return
        }
        let previous = selection?.screen ?? "none"
        selection = newSelection
        ProbeRuntime.record(
            "split selection committed source=\(window.label) "
                + "from=\(previous) to=\(newSelection.screen)"
        )
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

private protocol ProbeUIKitSplitChildLifecycleDelegate: AnyObject {
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

private struct ProbeUIKitSplitNavigationControllerRepresentable: UIViewControllerRepresentable {
    let window: ProbeWindow
    let sceneSessionID: String

    func makeCoordinator() -> Coordinator {
        Coordinator(window: window, sceneSessionID: sceneSessionID)
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

    final class Coordinator: NSObject, ProbeUIKitSplitChildLifecycleDelegate {
        private let window: ProbeWindow
        private let sceneSessionID: String
        private weak var splitViewController: UISplitViewController?
        private weak var primary: ProbeUIKitSplitPrimaryViewController?
        private weak var navigationController: UINavigationController?
        private weak var secondaryOne: ProbeUIKitSplitSecondaryViewController?
        private var installNavigationWorkItem: DispatchWorkItem?
        private var pushWorkItem: DispatchWorkItem?
        private var popWorkItem: DispatchWorkItem?
        private var didInstallNavigation = false
        private var didPushSecondaryTwo = false
        private var didPopSecondaryTwo = false

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
                "uikit split navigation child materialized source=\(window.label) "
                    + "native=\(sceneSessionID) screen=\(child.screen) "
                    + "appearance=\(child.appearanceCount) "
                    + "object=\(ObjectIdentifier(child)) "
                    + "horizontal_size_class=\(child.horizontalSizeClassDescription)"
            )

            if child is ProbeUIKitSplitPrimaryViewController {
                emitMarker(afterMaterializing: child, phase: "post-materialization")
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
    }
}

private class ProbeUIKitSplitChildViewController: UIViewController {
    let window: ProbeWindow
    let sceneSessionID: String
    let screen: String
    weak var lifecycleDelegate: ProbeUIKitSplitChildLifecycleDelegate?

    private(set) var appearanceCount = 0

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
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24)
        ])
        view.accessibilityIdentifier = "probe.native.\(window.label).\(screen)"
        recordLifecycle("viewDidLoad")
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

private struct ProbeDetailView: View {
    let window: ProbeWindow
    let sceneSessionID: String
    let instance: Int
    let readerControlGeneration: Int
    let replaceWithAlternate: () -> Void
    let didAppear: () -> Void

    @State private var emittedAppearance = false
    @State private var didRunTask = false

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
    var resolve: ((UIWindow) -> Void)?
    private var lastIdentifier: String?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        resolveIfPossible()
    }

    func resolveIfPossible() {
        guard
            let window,
            let identifier = window.windowScene?.session.persistentIdentifier
        else {
            return
        }
        guard identifier != lastIdentifier else {
            return
        }
        lastIdentifier = identifier
        resolve?(window)
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
