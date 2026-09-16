/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import SwiftUI
#if !EXP147_PROBE_TESTS
#if DEBUG
@_spi(Experimental)
@testable import DatadogRUM
#else
@_spi(Experimental)
import DatadogRUM
#endif

/// Instrumented composition used for the source-diff measurement.
///
/// The only customer call-site changes are the three boundary wrappers below.
/// Screen files, router methods, NavigationStack, sheet, and cover calls are the
/// exact baseline implementations.
@available(iOS 27.0, *)
struct EXP147InstrumentedApplication: View {
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
            EXP147RUMRouterBoundary(router: messagesRouter) {
                EXP147BaselineNavigationContainer(
                    flow: .messages,
                    router: messagesRouter
                )
            }
        case .notes:
            EXP147RUMRouterBoundary(router: notesRouter) {
                EXP147BaselineNavigationContainer(
                    flow: .notes,
                    router: notesRouter
                )
            }
        case .settings:
            EXP147RUMRouterBoundary(
                router: settingsRouter,
                metadata: RUMNavigationMetadata
                    .automatic(in: EXP147Flow.settings.rawValue)
                    .overriding(
                        EXP147Route.preferences,
                        name: "Account preferences"
                    )
            ) {
                EXP147BaselineNavigationContainer(
                    flow: .settings,
                    router: settingsRouter
                )
            }
        }
    }
}

/// Zero-refactor fallback arms. Without a trustworthy semantic stream the host
/// deliberately retains scene-aware automatic tracking instead of requiring
/// customer screens or third-party APIs to change.
@available(iOS 27.0, *)
struct EXP147FallbackInstrumentedApplication: View {
    var body: some View {
        TabView {
            RUMNavigationHost {
                EXP147NativeSwiftUIContainer()
            }
            .tabItem { Text("Native") }

            RUMNavigationHost {
                EXP147OpaqueThirdPartyContainer()
            }
            .tabItem { Text("Opaque") }
        }
    }
}
#endif
