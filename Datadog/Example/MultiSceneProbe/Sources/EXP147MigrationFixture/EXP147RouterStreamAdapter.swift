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

/// Dedicated existing-router adapter used to measure EXP-147 migration cost.
///
/// The SDK-owned host subscribes once to the router's already accepted state
/// stream. This application adapter only projects the three structural layers of
/// current navigation state; it has no per-route metadata or transition calls.
@available(iOS 27.0, *)
@MainActor
struct EXP147RUMRouterBoundary<Content: View>: View {
    @ObservedObject var router: EXP147NavigationRouter
    let metadata: RUMNavigationMetadata
    let attributesForState: (EXP147NavigationState) -> [String: Encodable]
    @ViewBuilder let content: Content

    init(
        router: EXP147NavigationRouter,
        metadata: RUMNavigationMetadata? = nil,
        attributesForState: @escaping (EXP147NavigationState) -> [String: Encodable]
            = { _ in [:] },
        @ViewBuilder content: () -> Content
    ) {
        self.router = router
        self.metadata = metadata ?? .automatic(in: router.state.flow.rawValue)
        self.attributesForState = attributesForState
        self.content = content()
    }

    var body: some View {
        RUMNavigationHost(
            observing: router.statePublisher,
            destination: destination(for:),
            metadata: metadata
        ) {
            content
        }
    }

    private func destination(
        for state: EXP147NavigationState
    ) -> RUMNavigationDestination {
        let attributes = attributesForState(state)
        if let presentation = state.presentation {
            return .presentation(presentation, attributes: attributes)
        }
        if let route = state.path.last {
            return .route(
                route,
                occurrence: state.path.count,
                attributes: attributes
            )
        }
        return .root(state.flow, attributes: attributes)
    }
}

/// Xcode 27 Observation candidate for EXP-151.
///
/// It observes the same already accepted router state synchronously at `.didSet`
/// instead of requiring a Combine publisher. The customer's NavigationStack,
/// sheets, covers, screens, and navigation methods remain unchanged.
@available(iOS 27.0, *)
@MainActor
struct EXP151RUMObservationBoundary<Content: View>: View {
    let router: EXP147NavigationRouter
    let metadata: RUMNavigationMetadata
    let attributesForState: (EXP147NavigationState) -> [String: Encodable]
    @ViewBuilder let content: Content

    init(
        router: EXP147NavigationRouter,
        metadata: RUMNavigationMetadata? = nil,
        attributesForState: @escaping (EXP147NavigationState) -> [String: Encodable]
            = { _ in [:] },
        @ViewBuilder content: () -> Content
    ) {
        self.router = router
        self.metadata = metadata ?? .automatic(in: router.state.flow.rawValue)
        self.attributesForState = attributesForState
        self.content = content()
    }

    var body: some View {
        RUMNavigationHost(
            observingCurrentDestination: { destination(for: router.state) },
            metadata: metadata
        ) {
            content
        }
    }

    private func destination(
        for state: EXP147NavigationState
    ) -> RUMNavigationDestination {
        let attributes = attributesForState(state)
        if let presentation = state.presentation {
            return .presentation(presentation, attributes: attributes)
        }
        if let route = state.path.last {
            return .route(
                route,
                occurrence: state.path.count,
                attributes: attributes
            )
        }
        return .root(state.flow, attributes: attributes)
    }
}

#endif
