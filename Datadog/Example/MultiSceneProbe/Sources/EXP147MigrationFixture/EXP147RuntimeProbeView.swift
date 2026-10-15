/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import SwiftUI

enum EXP147ProbeSemantics {
    static func screen(for state: EXP147NavigationState) -> String {
        if let presentation = state.presentation {
            switch presentation.style {
            case .sheet:
                return "sheet"
            case .fullScreenCover:
                return "full-screen-cover"
            }
        }

        guard let route = state.path.last else {
            return "home"
        }
        switch route {
        case .thread(let id):
            return "detail-\(id)"
        default:
            return route.displayTitle
                .lowercased()
                .replacingOccurrences(of: " ", with: "-")
        }
    }

    static func route(for state: EXP147NavigationState) -> [String] {
        ["home"]
            + state.path.map {
                EXP147NavigationState(
                    flow: state.flow,
                    path: [$0]
                )
            }
            .map(screen(for:))
            + (state.presentation.map {
                [screen(
                    for: EXP147NavigationState(
                        flow: state.flow,
                        path: state.path,
                        presentation: $0
                    )
                )]
            } ?? [])
    }
}

enum EXP153ProbeSemantics {
    static func screen(
        for snapshot: EXP153ThirdPartyNavigator.Snapshot
    ) -> String {
        EXP147ProbeSemantics.screen(for: navigationState(for: snapshot))
    }

    static func route(
        for snapshot: EXP153ThirdPartyNavigator.Snapshot
    ) -> [String] {
        EXP147ProbeSemantics.route(for: navigationState(for: snapshot))
    }

    private static func navigationState(
        for snapshot: EXP153ThirdPartyNavigator.Snapshot
    ) -> EXP147NavigationState {
        EXP147NavigationState(
            flow: snapshot.flow,
            path: snapshot.path.map(\.route),
            presentation: snapshot.presentation?.presentation
        )
    }
}

/// Runtime arm for EXP-147. Probe attributes are injected by the dedicated
/// adapter so the ordinary customer screens and router stay unchanged.
#if !EXP147_PROBE_TESTS
@available(iOS 27.0, *)
struct EXP147RuntimeProbeView: View {
    @ObservedObject var router: EXP147NavigationRouter
    let attributesForState: (EXP147NavigationState) -> [String: Encodable]

    var body: some View {
        EXP147RUMRouterBoundary(
            router: router,
            attributesForState: attributesForState
        ) {
            EXP147BaselineNavigationContainer(
                flow: .messages,
                router: router
            )
        }
    }
}

/// Runtime arm for EXP-151. It reuses the unchanged realistic navigation
/// fixture and observes accepted `@Observable` state synchronously at `.didSet`.
@available(iOS 27.0, *)
struct EXP151RuntimeProbeView: View {
    @ObservedObject var router: EXP147NavigationRouter
    let attributesForState: (EXP147NavigationState) -> [String: Encodable]

    var body: some View {
        EXP151RUMObservationBoundary(
            router: router,
            attributesForState: attributesForState
        ) {
            EXP147BaselineNavigationContainer(
                flow: .messages,
                router: router
            )
        }
    }
}

/// Probe-only EXP-152 arm. It keeps the accepted Observation boundary and
/// reproduces the customer's standard navigation container solely to attach
/// diagnostic callbacks to SwiftUI's native presentation modifiers. These
/// callbacks are not part of the proposed RUM integration.
@available(iOS 27.0, *)
struct EXP152RuntimeProbeView: View {
    @ObservedObject var router: EXP147NavigationRouter
    let attributesForState: (EXP147NavigationState) -> [String: Encodable]
    let onSheetAppear: () -> Void
    let onSheetDismiss: () -> Void
    let onFullScreenCoverAppear: () -> Void
    let onFullScreenCoverDismiss: () -> Void

    var body: some View {
        EXP151RUMObservationBoundary(
            router: router,
            attributesForState: attributesForState
        ) {
            EXP152NativeDismissCallbackNavigationContainer(
                router: router,
                onSheetAppear: onSheetAppear,
                onSheetDismiss: onSheetDismiss,
                onFullScreenCoverAppear: onFullScreenCoverAppear,
                onFullScreenCoverDismiss: onFullScreenCoverDismiss
            )
        }
    }
}

/// Runtime arm for EXP-153. The custom visual container and navigator expose no
/// Datadog surface; this wrapper adds one callback adapter and one host boundary.
@available(iOS 27.0, *)
struct EXP153RuntimeProbeView: View {
    @ObservedObject var navigator: EXP153ThirdPartyNavigator
    let attributesForSnapshot:
        (EXP153ThirdPartyNavigator.Snapshot) -> [String: Encodable]
    let recordInitialLifecycle: (String) -> Void

    var body: some View {
        EXP153RUMThirdPartyBoundary(
            navigator: navigator,
            attributesForSnapshot: attributesForSnapshot
        ) {
            EXP153ThirdPartyNavigationContainer(navigator: navigator)
                .onAppear {
                    recordInitialLifecycle("on-appear")
                }
                .task {
                    recordInitialLifecycle("task-immediate")
                }
        }
    }
}

@available(iOS 27.0, *)
private struct EXP152NativeDismissCallbackNavigationContainer: View {
    @ObservedObject var router: EXP147NavigationRouter
    let onSheetAppear: () -> Void
    let onSheetDismiss: () -> Void
    let onFullScreenCoverAppear: () -> Void
    let onFullScreenCoverDismiss: () -> Void

    var body: some View {
        NavigationStack(path: router.path) {
            EXP147MessagesRootScreen(router: router)
                .navigationDestination(for: EXP147Route.self) { route in
                    EXP147MessagesDestinationScreen(
                        route: route,
                        router: router
                    )
                }
        }
        .sheet(item: router.sheet, onDismiss: onSheetDismiss) { presentation in
            EXP147PresentationScreen(
                presentation: presentation,
                router: router
            )
            .onAppear(perform: onSheetAppear)
        }
        .fullScreenCover(
            item: router.fullScreenCover,
            onDismiss: onFullScreenCoverDismiss
        ) { presentation in
            EXP147PresentationScreen(
                presentation: presentation,
                router: router
            )
            .onAppear(perform: onFullScreenCoverAppear)
        }
    }
}
#endif
