/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import SwiftUI

@available(iOS 15.0, *)
struct FloatingButtonView: View {

    static let size: CGSize = .init(width: 80, height: 80)

    @ObservedObject private var viewModel: FloatingButtonViewModel

    init(viewModel: FloatingButtonViewModel){
        self.viewModel = viewModel
    }

    var body: some View {
        Image("datadog", bundle: .module)
            .resizable()
            .scaledToFit()
            .padding(10)
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color("purple_top", bundle: .module),
                        Color("purple_bottom", bundle: .module)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: Self.size.width, height: Self.size.height)
            .clipShape(Circle())
            .overlay(Circle().stroke(.white, lineWidth: 4))
            .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
    }
}

@available(iOS 15.0, *)
#Preview {
    FloatingButtonView(viewModel: FloatingButtonViewModel())
}
