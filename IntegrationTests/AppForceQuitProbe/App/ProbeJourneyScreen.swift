/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2026-Present Datadog, Inc.
 */

import SwiftUI

internal struct ProbeJourneyScreen: View {
    @ObservedObject var capture: ProbeCapture
    let journey: ProbeJourneyState

    var body: some View {
        VStack(spacing: 16) {
            Text(journey.kind.title).font(.headline)
            Text("Trial \(capture.trialID)").font(.caption)
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            Text("Probe controls").font(.caption)
            Text("Responsiveness checks: \(journey.responseChecks). Back attempts: \(journey.backAttempts).")
                .font(.caption)
                .accessibilityIdentifier("journeyCounts")
            Button("Check UI responds") { capture.checkJourneyResponse() }
                .accessibilityIdentifier("journeyResponse")
            Button("Return to probe controls") { capture.endJourney() }
                .accessibilityIdentifier("journeyEscape")
        }
        .padding()
        .accessibilityIdentifier("brokenJourney")
    }

    @ViewBuilder private var content: some View {
        switch journey.kind {
        case .infiniteLoader:
            ProgressView("Loading...")
                .accessibilityIdentifier("journeyLoader")
        case .ineffectiveBack:
            VStack(spacing: 16) {
                Text("Details")
                Text("The Back button responds, but leaves this page visible.")
                Button("Back") { capture.attemptJourneyBack() }
                    .accessibilityIdentifier("journeyBack")
            }
        case .emptyPage:
            Color.clear.accessibilityLabel("Empty content with no route forward")
                .accessibilityIdentifier("journeyEmptyPage")
        }
    }
}
