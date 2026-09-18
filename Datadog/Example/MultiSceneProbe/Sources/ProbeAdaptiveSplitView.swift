/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import SwiftUI
@_spi(Experimental) import DatadogRUM

/// Current accepted-state integration for the adaptive split acceptance gate.
@available(iOS 27.0, *)
struct ProbeAdaptiveSplitView: View {
    let window: ProbeWindow
    let sceneSessionID: String
    @ObservedObject var router: ProbeAdaptiveSplitState
    let didCommit: (ProbeAdaptiveSplitState.Snapshot, ProbeAdaptiveSplitState.Snapshot) -> Void

    @State private var markerOrdinal = 0
    @State private var materializedGeneration: UInt64?

    var body: some View {
        RUMNavigationHost(
            observing: router.publisher,
            destination: destination(for:),
            metadata: .automatic
                .overriding(ProbeAdaptiveSplitDestination.empty, name: "ProbeSplitEmptyView")
                .overriding(ProbeAdaptiveSplitDestination.detailOne, name: "ProbeSplitDetailView")
                .overriding(ProbeAdaptiveSplitDestination.detailTwo, name: "ProbeSplitDetailView")
                .overriding(ProbeAdaptiveSplitDestination.placeholder, name: "ProbeSplitPlaceholderView")
        ) {
            NavigationSplitView {
                List(selection: selection) {
                    NavigationLink("Detail 1", value: ProbeAdaptiveSplitDestination.detailOne)
                    NavigationLink("Detail 2", value: ProbeAdaptiveSplitDestination.detailTwo)
                    NavigationLink("Placeholder", value: ProbeAdaptiveSplitDestination.placeholder)
                    Button("Emit adaptive marker") { emitMeasuredMarker() }
                        .accessibilityIdentifier("probe.adaptive.sidebar-marker")
                }
                .navigationTitle("Selections")
            } detail: {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Adaptive split acceptance")
                    Text("run: \(window.runID)")
                    Text("source: \(window.label)")
                    Text("native session: \(sceneSessionID)")
                    Text("screen: \(router.current.destination.rawValue)")
                    Text("accepted generation: \(router.current.generation)")
                    Button("Emit adaptive marker") { emitMeasuredMarker() }
                    .accessibilityIdentifier("probe.adaptive.marker")
                    Button("Clear selection") { selection.wrappedValue = nil }
                    Spacer()
                }
                .padding(24)
                .navigationTitle(router.current.destination.rawValue)
                .accessibilityIdentifier("probe.adaptive.destination")
                .task(id: router.current) {
                    guard materializedGeneration != router.current.generation else { return }
                    materializedGeneration = router.current.generation
                    ProbeRuntime.recordDestination(
                        window: window,
                        sceneSessionID: sceneSessionID,
                        screen: router.current.destination.rawValue,
                        isCommitted: true
                    )
                    emit("adaptive-materialized-\(router.current.generation)")
                }
            }
            .navigationSplitViewStyle(.balanced)
        }
        .task {
            guard ProbeRuntime.usesAdaptiveSplitResizeAcceptance else { return }
            for await signal in ProbeRuntime.eventRecorder.signalStream() {
                guard !Task.isCancelled,
                      signal.runID == window.runID,
                      let handle = ProbeRuntime.sceneRegistry.handle(logicalSceneID: window.label),
                      handle.nativeSceneID == sceneSessionID,
                      let nativeWindow = ProbeRuntime.sceneRegistry.window(for: handle),
                      ProbeRuntime.sceneRegistry.snapshot(logicalSceneID: window.label)?.currentRoute
                        == router.current.destination.route
                else { continue }
                let live = ProbeScenePresentation.capture(window: nativeWindow)
                guard let ordinal = router.consumeResize(
                    signal, live: live, logicalSceneID: window.label, nativeSceneID: sceneSessionID
                ) else { continue }
                ProbeRuntime.eventRecorder.record(ProbeSignal(
                    kind: .assertion,
                    semanticContext: ProbeSemanticContext(
                        logicalSceneID: window.label,
                        nativeSceneID: sceneSessionID,
                        screen: router.current.destination.rawValue
                    ),
                    activationState: live.activationState.rawValue,
                    geometry: live.geometry,
                    horizontalSizeClass: live.horizontalSizeClass,
                    verticalSizeClass: live.verticalSizeClass,
                    navigationPath: router.current.destination.route,
                    acknowledgedSignalSequence: signal.sequence,
                    name: "adaptive-resize-guard-\(ordinal)",
                    result: .pass
                ))
                emit("adaptive-resize-\(ordinal)")
            }
        }
    }

    private var selection: Binding<ProbeAdaptiveSplitDestination?> {
        Binding(
            get: { router.current.destination == .empty ? nil : router.current.destination },
            set: { selected in
                let previous = router.current
                guard router.select(selected) else { return }
                didCommit(previous, router.current)
                emit("adaptive-commit-\(router.current.generation)")
            }
        )
    }

    private func destination(
        for snapshot: ProbeAdaptiveSplitState.Snapshot
    ) -> RUMNavigationDestination {
        let attributes: [String: Encodable] = [
            ProbeRuntime.Attribute.runID: window.runID,
            ProbeRuntime.Attribute.host: "adaptive-split-accepted-state",
            ProbeRuntime.Attribute.sourceScene: window.label,
            ProbeRuntime.Attribute.sceneSessionID: sceneSessionID,
            ProbeRuntime.Attribute.screen: snapshot.destination.rawValue,
            ProbeRuntime.Attribute.viewScene: window.label,
            ProbeRuntime.Attribute.viewSceneSessionID: sceneSessionID,
            ProbeRuntime.Attribute.viewScreen: snapshot.destination.rawValue
        ]
        if snapshot.destination == .empty {
            return .root(snapshot.destination, attributes: attributes)
        }
        return .route(
            snapshot.destination,
            occurrence: snapshot.generation,
            attributes: attributes
        )
    }

    private func emitMeasuredMarker() {
        markerOrdinal += 1
        emit("adaptive-marker-\(markerOrdinal)")
    }

    private func emit(_ phase: String) {
        ProbeRuntime.emitLifecycleMarker(
            window: window,
            sceneSessionID: sceneSessionID,
            screen: router.current.destination.rawValue,
            phase: phase
        )
    }
}
