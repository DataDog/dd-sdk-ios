/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import SwiftUI

@available(iOS 13.0, *)
public struct TestSwiftUIView: View {
    @State private var txt: String = "SwiftUI"

    public var body: some View {
        VStack {
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundColor(.accentColor)
            Image("dd_logo", bundle: .module)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 88)
                .clipped()
                .clipShape(.rect(cornerRadius: 44))
                .foregroundColor(.purple)

            Text("Hello, SwiftUI!")
            TextField("Your name", text: $txt)
                .disableAutocorrection(true)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            Button("Validate") { }
                .padding()
                .foregroundColor(.white)
                .background(Color(.purple))
                .cornerRadius(8)
        }
        .padding()
    }
}

@available(iOS 13.0, *)
struct SwiftUIView_Previews: PreviewProvider {
    static var previews: some View {
        TestSwiftUIView()
    }
}
