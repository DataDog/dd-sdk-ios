/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import SwiftUI

struct EXP147PresentationScreen: View {
    let presentation: EXP147Presentation
    @ObservedObject var router: EXP147NavigationRouter

    var body: some View {
        NavigationStack {
            EXP147ScreenScaffold(
                title: presentation.displayTitle,
                detail: presentation.style == .sheet
                    ? "Presented with the application's unchanged sheet API."
                    : "Presented with the application's unchanged full-screen cover API."
            ) {
                Button("Dismiss") { router.dismissPresentation() }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { router.dismissPresentation() }
                }
            }
        }
        .accessibilityIdentifier("exp147.presentation.\(presentation.id)")
    }
}
