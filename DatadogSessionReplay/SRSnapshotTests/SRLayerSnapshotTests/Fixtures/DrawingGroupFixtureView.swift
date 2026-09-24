/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import SwiftUI

@available(iOS 16.0, *)
internal struct DrawingGroupFixtureView: View {
    var body: some View {
        VStack(spacing: 24) {
            Text("Outside drawing group")

            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .fill(.blue)

                Circle()
                    .fill(.orange.opacity(0.8))
                    .frame(width: 120, height: 120)
                    .offset(x: 60)

                Text("Drawing group")
                    .font(.title2)
                    .foregroundStyle(.white)
            }
            .frame(width: 320, height: 180)
            .drawingGroup()
        }
        .padding()
    }
}
