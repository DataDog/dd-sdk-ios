/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import SwiftUI
import UIKit

@available(iOS 16.0, *)
internal struct TextFixtureView: View {
    @State private var editableField = "Lorem ipsum dolor sit amet"
    @State private var editableText = """
        Lorem ipsum dolor sit amet, consectetur adipiscing elit. \
        Mauris vestibulum consectetur dolor at vulputate. Sed eu \
        libero et metus scelerisque porta. Cras eu lorem orci.
        """

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Heading")
                .font(.title)

            Text(
                """
                **Lorem ipsum dolor** sit amet, consectetur adipiscing elit. \
                Mauris vestibulum consectetur dolor at vulputate. Sed eu \
                libero et metus scelerisque porta. Cras eu lorem orci.
                """
            )

            Label("Some **text** label", systemImage: "text.alignleft")

            Button("_Click me!_") {
            }
            .buttonStyle(.borderedProminent)

            TextField("Placeholder", text: .constant(""))
                .textFieldStyle(.roundedBorder)

            TextField("Text field placeholder", text: $editableField)
                .textFieldStyle(.roundedBorder)

            SecureField("Secure field placeholder", text: $editableField)
                .textFieldStyle(.roundedBorder)

            TextEditor(text: $editableText)
                .frame(height: 124)
                .padding(8)
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(8)
        }
        .scrollContentBackground(.hidden)
        .padding()
    }
}
