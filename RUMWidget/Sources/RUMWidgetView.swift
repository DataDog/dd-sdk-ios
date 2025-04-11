/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import DatadogCore
import DatadogInternal
import SwiftUI
import TipKit

@available(iOS 15.0, *)
public struct RUMWidgetView: View {
    @StateObject var viewModel: RUMWidgetViewModel
    private var floatingViewModel: FloatingButtonViewModel

    var onExpandView: ((Bool) -> Void)?

    init(viewModel: RUMWidgetViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
        floatingViewModel = FloatingButtonViewModel()
    }

    public var body: some View {
        ZStack {
            if viewModel.isExpanded {
                DDVitalsView(
                    viewModel: DDVitalsViewModel(configuration: viewModel.configuration),
                )
                .frame(width: UIScreen.main.bounds.width)
                .onTapGesture {
                    viewModel.isExpanded.toggle()
                }
            } else {
                FloatingButtonView(viewModel: floatingViewModel)
                    .frame(width: FloatingButtonView.size.width, height: FloatingButtonView.size.height)
                    .onTapGesture {
                        viewModel.isExpanded.toggle()
                    }
            }
        }
        .onChange(of: viewModel.isExpanded) { isExpanded in
            onExpandView?(isExpanded)

            if !isExpanded, #available(iOS 17.0, *) {
                try? Tips.resetDatastore()
            }
        }
    }
}
