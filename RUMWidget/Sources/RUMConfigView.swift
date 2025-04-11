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
            Button(action: viewModel.isSDKEnabled ? viewModel.stopSdk : viewModel.startSdk) {
                Label(
                    viewModel.isSDKEnabled ? "Stop SDK" : "Start SDK",
                    systemImage: viewModel.isSDKEnabled ? "stop.fill" : "play.fill"
                )
                .font(.subheadline)
            }
            .buttonStyle(.borderedProminent)

            Toggle("Logs", isOn: $viewModel.isLogsEnabled)
                .disabled(viewModel.isSDKEnabled)
            Toggle("Traces", isOn: $viewModel.isTracesEnabled)
                .disabled(viewModel.isSDKEnabled)
            Toggle("RUM", isOn: $viewModel.isRUMEnabled)
                .disabled(viewModel.isSDKEnabled)
            Toggle("Session Replay", isOn: $viewModel.isSessionReplayEnabled)
                .disabled(viewModel.isSDKEnabled)

            Spacer()
        }
        .foregroundStyle(.white)
        .tint(Color("purple_top", bundle: .module))
    }
}

@available(iOS 15.0, *)
#Preview {
    RUMConfigView(viewModel: RUMConfigViewModel(configuration: .init(clientToken: "dummy", env: "dummy")))
}
