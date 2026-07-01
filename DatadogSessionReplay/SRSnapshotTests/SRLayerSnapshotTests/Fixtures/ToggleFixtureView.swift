/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import SwiftUI

@available(iOS 16.0, *)
internal struct ToggleFixtureView: View {
    var body: some View {
        VStack(alignment: .leading) {
            Toggle("On", isOn: .constant(true))
            Toggle("Off", isOn: .constant(false))
            Toggle("Disabled", isOn: .constant(true))
                .disabled(true)
            Toggle("Tinted", isOn: .constant(true))
                .tint(.purple)
            Toggle("Button style", isOn: .constant(true))
                .toggleStyle(.button)
        }
        .padding()
    }
}
