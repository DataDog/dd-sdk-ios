/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Combine
import Observation
import SwiftUI

/// Customer-owned navigation state for EXP-147.
///
/// This file is the uninstrumented baseline. It deliberately has no Datadog import
/// and no RUM calls. The fixture models three independent navigation containers,
/// heterogeneous routes, ordinary sheets, and ordinary full-screen covers.
enum EXP147Flow: String, CaseIterable, Hashable {
    case messages
    case notes
    case settings

    var title: String {
        rawValue.prefix(1).uppercased() + rawValue.dropFirst()
    }
}

enum EXP147Route: Hashable {
    case thread(Int)
    case channel(String)
    case mentions
    case savedItems
    case scheduledMessages
    case people
    case huddle(Int)
    case canvas(Int)
    case search(String)
    case searchResults(String)
    case note(Int)
    case folder(String)
    case tag(String)
    case recentNotes
    case sharedNotes
    case trash
    case documentScanner
    case profile
    case preferences
    case notifications
    case privacy
    case integrations
    case appearance
    case storage
    case about
}

enum EXP147PresentationStyle {
    case sheet
    case fullScreenCover
}

enum EXP147Presentation: Hashable, Identifiable {
    case compose
    case threadInfo(Int)
    case shareThread(Int)
    case quickSwitcher
    case attachment(Int)
    case onboarding
    case whatsNew

    var id: String {
        String(describing: self)
    }

    var style: EXP147PresentationStyle {
        switch self {
        case .compose, .threadInfo, .shareThread, .quickSwitcher:
            return .sheet
        case .attachment, .onboarding, .whatsNew:
            return .fullScreenCover
        }
    }
}

struct EXP147NavigationState: Equatable {
    let flow: EXP147Flow
    var path: [EXP147Route] = []
    var presentation: EXP147Presentation?
}

/// Representative existing application router.
///
/// Its methods express business navigation only. EXP-147 treats any RUM call in
/// this type as a migration-cost failure.
@MainActor
@Observable
final class EXP147NavigationRouter: @preconcurrency ObservableObject {
    @ObservationIgnored
    let objectWillChange = ObservableObjectPublisher()

    @ObservationIgnored
    private let stateSubject: CurrentValueSubject<EXP147NavigationState, Never>

    private(set) var state: EXP147NavigationState

    init(flow: EXP147Flow) {
        let state = EXP147NavigationState(flow: flow)
        self.state = state
        self.stateSubject = CurrentValueSubject(state)
    }

    var statePublisher: AnyPublisher<EXP147NavigationState, Never> {
        stateSubject.eraseToAnyPublisher()
    }

    var path: Binding<[EXP147Route]> {
        Binding(
            get: { self.state.path },
            set: { self.setPath($0) }
        )
    }

    var sheet: Binding<EXP147Presentation?> {
        presentationBinding(for: .sheet)
    }

    var fullScreenCover: Binding<EXP147Presentation?> {
        presentationBinding(for: .fullScreenCover)
    }

    func setPath(_ path: [EXP147Route]) {
        update { $0.path = path }
    }

    func push(_ route: EXP147Route) {
        update { $0.path.append(route) }
    }

    func pop() {
        update { _ = $0.path.popLast() }
    }

    func popToRoot() {
        update { $0.path.removeAll() }
    }

    func replaceTop(with route: EXP147Route) {
        update {
            _ = $0.path.popLast()
            $0.path.append(route)
        }
    }

    func present(_ presentation: EXP147Presentation) {
        update { $0.presentation = presentation }
    }

    func dismissPresentation() {
        update { $0.presentation = nil }
    }

    func openThread(_ id: Int) {
        push(.thread(id))
    }

    func openChannel(_ id: String) {
        push(.channel(id))
    }

    func openNote(_ id: Int) {
        push(.note(id))
    }

    func openPreferences() {
        push(.preferences)
    }

    func showSearch(query: String) {
        push(.searchResults(query))
    }

    private func presentationBinding(
        for style: EXP147PresentationStyle
    ) -> Binding<EXP147Presentation?> {
        Binding(
            get: {
                guard self.state.presentation?.style == style else {
                    return nil
                }
                return self.state.presentation
            },
            set: { presentation in
                if let presentation {
                    self.present(presentation)
                } else if self.state.presentation?.style == style {
                    self.dismissPresentation()
                }
            }
        )
    }

    private func update(_ mutation: (inout EXP147NavigationState) -> Void) {
        var next = state
        mutation(&next)
        guard next != state else {
            return
        }
        objectWillChange.send()
        state = next
        stateSubject.send(next)
    }
}
