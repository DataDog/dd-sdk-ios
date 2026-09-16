/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import SwiftUI

/// Uninstrumented customer navigation. Standard SwiftUI APIs remain unchanged in
/// the instrumented variant because the RUM boundary wraps this whole container.
struct EXP147BaselineNavigationContainer: View {
    let flow: EXP147Flow
    @ObservedObject var router: EXP147NavigationRouter

    var body: some View {
        NavigationStack(path: router.path) {
            root
                .navigationDestination(for: EXP147Route.self) { route in
                    destination(for: route)
                }
        }
        .sheet(item: router.sheet) { presentation in
            EXP147PresentationScreen(
                presentation: presentation,
                router: router
            )
        }
        .fullScreenCover(item: router.fullScreenCover) { presentation in
            EXP147PresentationScreen(
                presentation: presentation,
                router: router
            )
        }
    }

    @ViewBuilder
    private var root: some View {
        switch flow {
        case .messages:
            EXP147MessagesRootScreen(router: router)
        case .notes:
            EXP147NotesRootScreen(router: router)
        case .settings:
            EXP147SettingsRootScreen(router: router)
        }
    }

    @ViewBuilder
    private func destination(for route: EXP147Route) -> some View {
        switch flow {
        case .messages:
            EXP147MessagesDestinationScreen(route: route, router: router)
        case .notes:
            EXP147NotesDestinationScreen(route: route, router: router)
        case .settings:
            EXP147SettingsDestinationScreen(route: route, router: router)
        }
    }
}

/// Baseline composition used for the source-diff measurement.
struct EXP147BaselineApplication: View {
    @State private var activeFlow: EXP147Flow = .messages
    @StateObject private var messagesRouter =
        EXP147NavigationRouter(flow: .messages)
    @StateObject private var notesRouter =
        EXP147NavigationRouter(flow: .notes)
    @StateObject private var settingsRouter =
        EXP147NavigationRouter(flow: .settings)

    var body: some View {
        VStack(spacing: 0) {
            Picker("Flow", selection: $activeFlow) {
                ForEach(EXP147Flow.allCases, id: \.self) { flow in
                    Text(flow.title).tag(flow)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            activeContainer
        }
    }

    @ViewBuilder
    private var activeContainer: some View {
        switch activeFlow {
        case .messages:
            EXP147BaselineNavigationContainer(
                flow: .messages,
                router: messagesRouter
            )
        case .notes:
            EXP147BaselineNavigationContainer(
                flow: .notes,
                router: notesRouter
            )
        case .settings:
            EXP147BaselineNavigationContainer(
                flow: .settings,
                router: settingsRouter
            )
        }
    }
}

/// Native SwiftUI arm with no observable router or RUM-specific state. It
/// represents generated application code that must remain valid unchanged.
struct EXP147NativeSwiftUIContainer: View {
    @State private var path: [Int] = []
    @State private var isComposePresented = false
    @State private var isAttachmentPresented = false

    var body: some View {
        NavigationStack(path: $path) {
            EXP147ScreenScaffold(
                title: "Native home",
                detail: "A native SwiftUI flow with local navigation state."
            ) {
                Button("Open item 1") { path.append(1) }
                Button("Compose") { isComposePresented = true }
                Button("Attachment") { isAttachmentPresented = true }
            }
            .navigationDestination(for: Int.self) { item in
                EXP147ScreenScaffold(
                    title: "Native item \(item)",
                    detail: "A destination without an exposed transition stream."
                ) {
                    Button("Open next") { path.append(item + 1) }
                    Button("Home") { path.removeAll() }
                }
            }
        }
        .sheet(isPresented: $isComposePresented) {
            Text("Native compose")
        }
        .fullScreenCover(isPresented: $isAttachmentPresented) {
            Text("Native attachment")
        }
    }
}

/// Stand-in for an imported navigation container whose internal state and
/// transition stream are opaque to the application.
struct EXP147OpaqueThirdPartyContainer: View {
    @State private var selectedItem = 0

    var body: some View {
        VStack(spacing: 16) {
            Text("Opaque container item \(selectedItem)")
            Button("Advance opaque navigation") {
                selectedItem += 1
            }
        }
        .accessibilityIdentifier("exp147.opaque-container")
    }
}
