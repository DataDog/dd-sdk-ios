/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import SwiftUI

@available(iOS 15.0, *)
public struct RUMConfigView: View {
    @StateObject private var viewModel: RUMConfigViewModel

    public init(viewModel: RUMConfigViewModel = RUMConfigViewModel()) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        VStack(alignment: .leading) {
            Text("Configuration")
                .font(.subheadline)

            Text("Custom endpoint url")
                .font(.caption)
            TextField("Custom endpoint url", text: $viewModel.customEndpointUrl)
                .textFieldStyle(RoundedBorderTextFieldStyle())

            Text("Feature flags")
                .font(.caption)

            ForEach(Array(viewModel.featureFlags.keys), id: \.self) { flag in
                Toggle(isOn: Binding(
                    get: { viewModel.featureFlags[flag] ?? false },
                    set: { _ in viewModel.toggleFeatureFlag(flag) }
                )) {
                    Text(flag.rawValue)
                        .font(.footnote)
                }
            }

            Spacer()
        }
        .padding()
        .tint(.purple)
    }
}

@available(iOS 15.0, *)
#Preview {
    RUMConfigView()
}
