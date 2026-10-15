/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import SwiftUI

struct EXP147SettingsRootScreen: View {
    @ObservedObject var router: EXP147NavigationRouter

    var body: some View {
        EXP147ScreenScaffold(
            title: "Settings",
            detail: "A third independent container with ordinary preference routes."
        ) {
            Button("Profile") { router.push(.profile) }
            Button("Preferences") { router.openPreferences() }
            Button("Notifications") { router.push(.notifications) }
            Button("Privacy") { router.push(.privacy) }
            Button("What's new") { router.present(.whatsNew) }
        }
    }
}

struct EXP147SettingsDestinationScreen: View {
    let route: EXP147Route
    @ObservedObject var router: EXP147NavigationRouter

    var body: some View {
        EXP147ScreenScaffold(
            title: route.displayTitle,
            detail: "A settings destination with no Datadog-specific metadata."
        ) {
            Button("Integrations") { router.push(.integrations) }
            Button("Appearance") { router.push(.appearance) }
            Button("Storage") { router.push(.storage) }
            Button("About") { router.push(.about) }
            Button("Back") { router.pop() }
            Button("Home") { router.popToRoot() }
        }
    }
}
