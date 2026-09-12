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
    case detail
}

struct ProbeWindowRoot: View {
    let window: ProbeWindow

    @Environment(\.openWindow) private var openWindow
    @State private var path: [ProbeRoute] = []
    @State private var sceneSessionID = "unresolved"
    @State private var didScheduleNavigation = false
    @State private var didShowDetail = false
    @State private var didOpenPeer = false

    var body: some View {
        NavigationStack(path: $path) {
            ProbeHomeView(
                window: window,
                sceneSessionID: sceneSessionID,
                openDetail: openDetail,
                openPeer: openPeer
            )
            .navigationDestination(for: ProbeRoute.self) { route in
                switch route {
                case .detail:
                    ProbeDetailView(
                        window: window,
                        sceneSessionID: sceneSessionID,
                        didAppear: { didShowDetail = true }
                    )
                }
            }
        }
        .background(
            SceneSessionReader { identifier in
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
    }

    private func openDetail() {
        guard path.last != .detail else {
            return
        }
        path.append(.detail)
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
}

private struct ProbeHomeView: View {
    let window: ProbeWindow
    let sceneSessionID: String
    let openDetail: () -> Void
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

private struct ProbeDetailView: View {
    let window: ProbeWindow
    let sceneSessionID: String
    let didAppear: () -> Void

    @State private var emittedAppearance = false
    @State private var didRunTask = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ProbeHeading(
                window: window,
                sceneSessionID: sceneSessionID,
                screen: "detail"
            )
            Text("This screen is reached through a bound NavigationStack path.")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(24)
        .navigationTitle("\(window.label): Detail")
        .accessibilityIdentifier("probe.native.\(window.label).detail")
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
            screen: "detail",
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
    let resolve: (String) -> Void

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
    var resolve: ((String) -> Void)?
    private var lastIdentifier: String?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        resolveIfPossible()
    }

    func resolveIfPossible() {
        guard let identifier = window?.windowScene?.session.persistentIdentifier else {
            return
        }
        guard identifier != lastIdentifier else {
            return
        }
        lastIdentifier = identifier
        resolve?(identifier)
    }
}
