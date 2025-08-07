/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import SwiftUI

@available(iOS 15.0, *)
struct SymbolsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label {
                Text("Monochrome drawing")
            } icon: {
                Image(systemName: "timer")
            }
            Label {
                Text("Hierarchical drawing")
            } icon: {
                Image(systemName: "timer")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.purple)
            }
            Label {
                Text("Palette drawing")
            } icon: {
                Image(systemName: "timer")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.indigo, .purple)
            }
            Label {
                Text("Multicolor drawing")
            } icon: {
                Image(systemName: "timer")
                    .renderingMode(.original)
            }
        }
    }
}

@available(iOS 15.0, *)
#Preview {
    SymbolsView()
}
