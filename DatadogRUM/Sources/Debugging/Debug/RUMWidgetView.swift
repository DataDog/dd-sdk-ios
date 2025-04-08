/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import SwiftUI
import DatadogInternal

@available(iOS 15.0, *)
public struct RUMWidgetView: View {

    @StateObject var viewModel = RUMWidgetViewModel()
    private var floatingViewModel = FloatingButtonViewModel()

    var onExpandView: ((Bool) -> Void)?

    public var body: some View {
        ZStack {
            DDVitalsView(viewModel: DDVitalsViewModel(metricsManager: self.viewModel.metricsManager))
                .frame(width: UIScreen.main.bounds.width)
                .opacity(self.viewModel.isExpanded ? 1 : 0)

            FloatingButtonView(viewModel: floatingViewModel)
                .frame(width: FloatingButtonView.size.width, height: FloatingButtonView.size.height)
                .opacity(self.viewModel.isExpanded ? 0 : 1)
        }
        .onTapGesture {
            self.viewModel.isExpanded.toggle()
        }
        .onChange(of: self.viewModel.isExpanded) { isExpanded in
            self.onExpandView?(isExpanded)
        }
    }
}
