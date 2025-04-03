/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import SwiftUI

struct RUMAutoContentView: View {
    var body: some View {
        TabView {
            CharactersView()
                .tabItem {
                    Label("Characters", systemImage: "person.3")
                }

            LocationsView()
                .tabItem {
                    Label("Locations", systemImage: "map")
                }

            EpisodesView()
                .tabItem {
                    Label("Episodes", systemImage: "tv")
                }

            DocsView()
                .tabItem {
                    Label("Docs", systemImage: "doc.text")
                }
        }
        .tint(.purple)
    }
}

#Preview {
    RUMAutoContentView()
}
