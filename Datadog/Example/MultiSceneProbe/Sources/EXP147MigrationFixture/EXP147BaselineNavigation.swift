/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Combine
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

/// Library-owned accepted navigation state used by EXP-153. The application can
/// read the current snapshot and subscribe to committed changes, but it does not
/// own the container's rendering or transition implementation.
@MainActor
final class EXP153ThirdPartyNavigator: ObservableObject {
    struct Entry: Hashable {
        let id: UInt64
        let route: EXP147Route
    }

    struct PresentationEntry: Hashable {
        let id: UInt64
        let presentation: EXP147Presentation
    }

    struct Snapshot: Equatable {
        let flow: EXP147Flow
        var path: [Entry]
        var presentation: PresentationEntry?
        var revision: UInt64
    }

    @MainActor
    final class Observation {
        private var callback: ((Snapshot) -> Void)?

        fileprivate init(callback: @escaping (Snapshot) -> Void) {
            self.callback = callback
        }

        fileprivate var isActive: Bool { callback != nil }

        fileprivate func notify(_ snapshot: Snapshot) {
            callback?(snapshot)
        }

        func cancel() {
            callback = nil
        }
    }

    @MainActor
    private final class WeakObservation {
        weak var value: Observation?

        init(_ value: Observation) {
            self.value = value
        }
    }

    let objectWillChange = ObservableObjectPublisher()
    private(set) var currentSnapshot: Snapshot
    private(set) var observerRegistrationCount = 0
    private var nextIdentity: UInt64 = 0
    private var observations: [WeakObservation] = []
    private var hasPendingInteractivePop = false

    init(flow: EXP147Flow = .messages) {
        currentSnapshot = Snapshot(
            flow: flow,
            path: [],
            presentation: nil,
            revision: 0
        )
    }

    var activeObserverCount: Int {
        compactObservations()
        return observations.count
    }

    func observeAcceptedSnapshots(
        _ observer: @escaping (Snapshot) -> Void
    ) -> Observation {
        observerRegistrationCount += 1
        let observation = Observation(callback: observer)
        observations.append(WeakObservation(observation))
        observation.notify(currentSnapshot)
        return observation
    }

    func push(_ route: EXP147Route) {
        commit { snapshot in
            snapshot.path.append(
                Entry(id: makeIdentity(), route: route)
            )
        }
    }

    func pop() {
        guard !currentSnapshot.path.isEmpty else {
            return
        }
        commit { snapshot in
            _ = snapshot.path.popLast()
        }
    }

    func popToRoot() {
        guard !currentSnapshot.path.isEmpty else {
            return
        }
        commit { snapshot in
            snapshot.path.removeAll()
        }
    }

    func present(_ presentation: EXP147Presentation) {
        guard currentSnapshot.presentation?.presentation != presentation else {
            return
        }
        commit { snapshot in
            snapshot.presentation = PresentationEntry(
                id: makeIdentity(),
                presentation: presentation
            )
        }
    }

    func dismissPresentation() {
        guard currentSnapshot.presentation != nil else {
            return
        }
        commit { snapshot in
            snapshot.presentation = nil
        }
    }

    func beginInteractivePop() {
        hasPendingInteractivePop = !currentSnapshot.path.isEmpty
    }

    func resolveInteractivePop(committed: Bool) {
        guard hasPendingInteractivePop else {
            return
        }
        hasPendingInteractivePop = false
        if committed {
            pop()
        }
    }

    private func makeIdentity() -> UInt64 {
        nextIdentity &+= 1
        return nextIdentity
    }

    private func commit(_ mutation: (inout Snapshot) -> Void) {
        var next = currentSnapshot
        mutation(&next)
        guard next != currentSnapshot else {
            return
        }
        next.revision &+= 1
        objectWillChange.send()
        currentSnapshot = next
        compactObservations()
        observations.compactMap(\.value).forEach {
            $0.notify(next)
        }
    }

    private func compactObservations() {
        observations.removeAll { observation in
            observation.value?.isActive != true
        }
    }
}

/// A custom, library-owned visual container. It intentionally does not use
/// NavigationStack, sheet, or fullScreenCover so EXP-153 exercises an imported
/// callback-driven integration rather than another native-container alias.
struct EXP153ThirdPartyNavigationContainer: View {
    @ObservedObject var navigator: EXP153ThirdPartyNavigator

    var body: some View {
        ZStack {
            if let presentation = navigator.currentSnapshot.presentation {
                presentationContent(presentation.presentation)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else if let entry = navigator.currentSnapshot.path.last {
                destinationContent(entry.route)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                rootContent
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: navigator.currentSnapshot.revision)
        .accessibilityIdentifier("exp153.third-party-container")
    }

    private var rootContent: some View {
        EXP147ScreenScaffold(
            title: "Messages",
            detail: "A callback-driven custom navigation container."
        ) {
            Button("Open thread 1") { navigator.push(.thread(1)) }
            Button("Compose") { navigator.present(.compose) }
            Button("Attachment") { navigator.present(.attachment(1)) }
        }
    }

    private func destinationContent(_ route: EXP147Route) -> some View {
        EXP147ScreenScaffold(
            title: route.displayTitle,
            detail: "A route rendered by the custom navigation library."
        ) {
            Button("Back") { navigator.pop() }
            Button("Home") { navigator.popToRoot() }
            Button("Compose") { navigator.present(.compose) }
        }
    }

    private func presentationContent(
        _ presentation: EXP147Presentation
    ) -> some View {
        ZStack {
            presentation.style == .sheet
                ? Color.secondary.opacity(0.12)
                : Color.accentColor.opacity(0.08)
            EXP147ScreenScaffold(
                title: presentation.displayTitle,
                detail: "A presentation rendered by the custom navigation library."
            ) {
                Button("Dismiss") { navigator.dismissPresentation() }
            }
            .padding(presentation.style == .sheet ? 32 : 0)
        }
    }
}
