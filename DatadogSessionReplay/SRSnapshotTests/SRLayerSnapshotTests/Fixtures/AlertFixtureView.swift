/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import SwiftUI

@available(iOS 26.0, *)
internal struct AlertFixtureView: View {
    var body: some View {
        Text("Showing alert")
            .alert("Important message", isPresented: .constant(true)) {
                Button(role: .destructive, action: {})
                Button(role: .cancel, action: {})
            } message: {
                Text("This is a simple alert message.")
            }
    }
}
