/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import SwiftUI

@available(iOS 15.0, *)
public struct RUMConfigView: View {
    @StateObject private var viewModel: RUMConfigViewModel

    public init(viewModel: RUMConfigViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("Configuration")
                    .font(.headline)

                Spacer()

                Button(action: viewModel.isSDKEnabled ? viewModel.stopSdk : viewModel.startSdk) {
                    Text(viewModel.isSDKEnabled ? "Stop SDK" : "Start SDK")
                        .font(.subheadline)
                }
                .buttonStyle(.bordered)
            }

            Toggle("Logs", isOn: $viewModel.isLogsEnabled)
                .disabled(viewModel.isSDKEnabled)
                .frame(maxHeight: 25)
            Toggle("Traces", isOn: $viewModel.isTracesEnabled)
                .disabled(viewModel.isSDKEnabled)
                .frame(maxHeight: 25)
            Toggle("RUM", isOn: $viewModel.isRUMEnabled)
                .disabled(viewModel.isSDKEnabled)
                .frame(maxHeight: 25)
            Toggle("Session Replay", isOn: $viewModel.isSessionReplayEnabled)
                .disabled(viewModel.isSDKEnabled)
                .frame(maxHeight: 25)

            Spacer()
        }
        .tint(.purple)
        .padding(.horizontal)
    }
}

@available(iOS 15.0, *)
#Preview {
    RUMConfigView(viewModel: RUMConfigViewModel(configuration: .init(clientToken: "dummy", env: "dummy")))
}
