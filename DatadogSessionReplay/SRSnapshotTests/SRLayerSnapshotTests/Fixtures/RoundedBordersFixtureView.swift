/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import SwiftUI

@available(iOS 16.0, *)
internal struct RoundedBordersFixtureView: View {
    var body: some View {
        VStack(spacing: 32) {
            Image(systemName: "person.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.blue)
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 32))
                .overlay {
                    RoundedRectangle(cornerRadius: 32)
                        .stroke(.primary.opacity(0.25), lineWidth: 1)
                }

            RoundedRectangle(cornerRadius: 16)
                .stroke(.gray.opacity(0.35), lineWidth: 1)
                .frame(width: 280, height: 100)

            Text("Card content")
                .frame(width: 280, height: 100)
                .background(.blue.opacity(0.15), in: RoundedRectangle(cornerRadius: 16))
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(.gray.opacity(0.35), lineWidth: 1)
                }
        }
        .padding(24)
        .background(.yellow.opacity(0.15))
    }
}
