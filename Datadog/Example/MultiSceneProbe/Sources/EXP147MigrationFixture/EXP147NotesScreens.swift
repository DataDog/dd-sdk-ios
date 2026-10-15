/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import SwiftUI

struct EXP147NotesRootScreen: View {
    @ObservedObject var router: EXP147NavigationRouter

    var body: some View {
        EXP147ScreenScaffold(
            title: "Notes",
            detail: "A second independent container with retained document routes."
        ) {
            Button("Open note 12") { router.openNote(12) }
            Button("Open projects folder") { router.push(.folder("Projects")) }
            Button("Recent notes") { router.push(.recentNotes) }
            Button("Shared notes") { router.push(.sharedNotes) }
            Button("Scan document") { router.push(.documentScanner) }
        }
    }
}

struct EXP147NotesDestinationScreen: View {
    let route: EXP147Route
    @ObservedObject var router: EXP147NavigationRouter

    var body: some View {
        EXP147ScreenScaffold(
            title: route.displayTitle,
            detail: "A notes destination that remains unaware of RUM."
        ) {
            Button("Tag release") { router.push(.tag("release")) }
            Button("Open note 99") { router.openNote(99) }
            Button("Present attachment") { router.present(.attachment(99)) }
            Button("Back") { router.pop() }
            Button("Home") { router.popToRoot() }
        }
    }
}
