/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import SwiftUI

@available(iOS 16.0, *)
internal struct CanvasFixtureView: View {
    var body: some View {
        VStack(spacing: 24) {
            Text("Outside Canvas")

            Canvas { context, size in
                let bounds = CGRect(origin: .zero, size: size)
                context.fill(
                    RoundedRectangle(cornerRadius: 24).path(in: bounds),
                    with: .color(.blue)
                )

                let circle = CGRect(
                    x: size.width / 2,
                    y: size.height / 2 - 60,
                    width: 120,
                    height: 120
                )
                context.fill(
                    Path(ellipseIn: circle),
                    with: .color(.orange.opacity(0.8))
                )

                var text = context.resolve(Text("Canvas").font(.title2))
                text.shading = .color(.white)
                context.draw(text, at: CGPoint(x: size.width / 2, y: size.height / 2))
            }
            .frame(width: 320, height: 180)
        }
        .padding()
    }
}
