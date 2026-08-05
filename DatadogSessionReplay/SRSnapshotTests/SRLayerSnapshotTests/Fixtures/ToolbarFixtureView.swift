/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import SwiftUI

@available(iOS 16.0, *)
struct ToolbarFixtureView: View {
    private let text = """
        Lorem ipsum dolor sit amet, consectetur adipiscing elit. \
        Phasellus eu magna quis mauris bibendum pulvinar laoreet auctor lacus. \
        Curabitur non hendrerit quam. Suspendisse faucibus dolor vitae malesuada \
        iaculis. Aenean ut pulvinar ante, sit amet condimentum ligula. Ut \
        sagittis justo vel nunc aliquet, ac dapibus erat fermentum. Aliquam \
        blandit erat quis elit gravida suscipit. Phasellus non mi nec nulla \
        venenatis sodales. Proin faucibus luctus mauris, eu lacinia erat mattis \
        eget. Vestibulum vitae mi quis neque dictum laoreet. Mauris quis \
        pretium tellus.
        """

    @State private var didScrollToMiddle = false

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 17) {
                        Text(verbatim: text)
                            .id("top")
                        Text(verbatim: text)
                            .id("middle")
                        Text(verbatim: text)
                            .id("bottom")
                    }
                    .padding()
                }
                .onAppear {
                    guard !didScrollToMiddle else {
                        return
                    }
                    defer {
                        didScrollToMiddle = true
                    }
                    withAnimation(nil) {
                        proxy.scrollTo("middle", anchor: .center)
                    }
                }
            }
            .navigationTitle("Title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Profile", systemImage: "person.crop.circle", action: {})
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "gearshape", action: {})
                }

                ToolbarItemGroup(placement: .bottomBar) {
                    Button("Refresh", systemImage: "arrow.clockwise", action: {})
                    Spacer()
                    Group {
                        Button("Add", systemImage: "plus.circle.fill", action: {})
                        Button("Remove", systemImage: "minus.circle.fill", action: {})
                    }
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.indigo)
                }
            }
        }
    }
}
