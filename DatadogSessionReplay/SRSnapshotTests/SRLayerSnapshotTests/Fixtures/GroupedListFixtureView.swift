/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import SwiftUI

@available(iOS 16.0, *)
internal struct GroupedListFixtureView: View {
    var body: some View {
        List {
            Section("General") {
                Label("Instance Information", systemImage: "externaldrive")
                Label("Display Settings", systemImage: "paintpalette")
                Label("Remote Local Timelines", systemImage: "dot.radiowaves.right")
                Label("Tag Groups", systemImage: "number")
                Label("Recently Used Tags", systemImage: "clock")
                Label("Content Settings", systemImage: "rectangle.stack")
                Label("Swipe Actions", systemImage: "hand.draw")
                Label("Tabs Customizations", systemImage: "iphone")
                Label("Translation Settings", systemImage: "text.bubble")
                Label("System Settings", systemImage: "gearshape")
            }

            Section("About") {
                Text("Version 1.0")
            }
        }
        .listStyle(.insetGrouped)
        .tint(.purple)
    }
}
