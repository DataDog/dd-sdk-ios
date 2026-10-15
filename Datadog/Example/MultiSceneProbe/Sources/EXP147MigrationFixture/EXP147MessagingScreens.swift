/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import SwiftUI

struct EXP147MessagesRootScreen: View {
    @ObservedObject var router: EXP147NavigationRouter

    var body: some View {
        EXP147ScreenScaffold(
            title: "Messages",
            detail: "A representative high-traffic root with several route families."
        ) {
            Button("Open thread 42") { router.openThread(42) }
            Button("Open engineering") { router.openChannel("engineering") }
            Button("Show mentions") { router.push(.mentions) }
            Button("Scheduled messages") { router.push(.scheduledMessages) }
            Button("Search deployment") { router.showSearch(query: "deployment") }
            Button("Compose") { router.present(.compose) }
            Button("Quick switcher") { router.present(.quickSwitcher) }
        }
    }
}

struct EXP147MessagesDestinationScreen: View {
    let route: EXP147Route
    @ObservedObject var router: EXP147NavigationRouter

    var body: some View {
        EXP147ScreenScaffold(
            title: route.displayTitle,
            detail: "A messages destination rendered by the customer's existing router."
        ) {
            Button("Thread info") { router.present(.threadInfo(42)) }
            Button("Share thread") { router.present(.shareThread(42)) }
            Button("Attachment") { router.present(.attachment(7)) }
            Button("Open canvas") { router.push(.canvas(3)) }
            Button("Back") { router.pop() }
            Button("Home") { router.popToRoot() }
        }
    }
}
