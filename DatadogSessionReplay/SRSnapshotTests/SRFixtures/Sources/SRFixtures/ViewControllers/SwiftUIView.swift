/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import SwiftUI

@available(iOS 15.0, *)
struct SwiftUIView: View {
    var body: some View {
        VStack(spacing: 10) {
            Text("Hello, SwiftUI!")
                .font(.headline)

            Label("Label with Icon", systemImage: "star.fill")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TextField("Enter text", text: .constant("Placeholder text"))
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding(8)

            Button(action: {}) {
                Text("SwiftUI Button")
                    .padding()
                    .foregroundStyle(.background)
                    .background(Color.blue)
                    .cornerRadius(8)
            }

            Divider()
                .frame(height: 2)
                .background(Color.purple)
                .padding(.horizontal, 20)
                .padding(.vertical, 6)

            // "Bundled" image
            Image("dd_logo", bundle: .module)
                .resizable()
                .scaledToFit()
                .background(Color.purple)
                .frame(width: 120, height: 120)
                .clipped()

            // "Content" image
            Image("Flowers_1", bundle: .module)
                .resizable()
                .scaledToFit()
                .background(Color.purple)
                .frame(width: 120, height: 120)
                .clipped()

            List {
                Text("Item 1")
                Text("Item 2")
            }.frame(height: 140)
        }
    }
}
