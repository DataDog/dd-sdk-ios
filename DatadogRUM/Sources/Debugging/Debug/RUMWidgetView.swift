/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import DatadogInternal
import SwiftUI

@available(iOS 15.0, *)
public struct RUMWidgetView: View {
    @StateObject var viewModel = RUMWidgetViewModel()
    private var floatingViewModel = FloatingButtonViewModel()

    var onExpandView: ((Bool) -> Void)?

    public var body: some View {
        ZStack {
            DDVitalsView(
                viewModel: DDVitalsViewModel(metricsManager: viewModel.metricsManager)
            )
            .frame(width: UIScreen.main.bounds.width)
            .opacity(viewModel.isExpanded ? 1 : 0)
            .onTapGesture {
                viewModel.isExpanded.toggle()
            }

            FloatingButtonView(viewModel: floatingViewModel)
                .frame(width: FloatingButtonView.size.width, height: FloatingButtonView.size.height)
                .opacity(viewModel.isExpanded ? 0 : 1)
                .onTapGesture {
                    viewModel.isExpanded.toggle()
                }
        }
        .onChange(of: viewModel.isExpanded) { isExpanded in
            onExpandView?(isExpanded)
        }
    }
}
