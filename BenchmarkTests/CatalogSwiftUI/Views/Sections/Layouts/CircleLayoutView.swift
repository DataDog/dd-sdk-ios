//
//  CircleLayoutView.swift
//  Catalog
//
//  Created by Barbara Personal on 2024-11-30.
//

import SwiftUI

/// Example displaying some numbers around a circle
struct CircleLayoutView: View {
    
    /// will toggle the animation from 360 to 0 degrees
    @State
    private var isSpinning: Bool = false
    
    var body: some View {
        spinButton
        CircleLayout {
            ForEach(1..<12) { index in
                VStack {
                    Text("\(index)")
                        .fontWeight(.heavy)
                        .font(.largeTitle)
                }
                .padding(8)
                .background(
                    .medium
                )
                .cornerRadius(8)
            }
            .padding()
        }
        .rotationEffect(.degrees(isSpinning ? 360 : 0))
        .animation(.easeInOut(duration: 1), value: isSpinning)
    }
    
    // MARK: - private
    
    private var spinButton: some View {
        Button {
            isSpinning.toggle()
        } label: {
            Text("SPIN")
                .fontWeight(.heavy)
                .font(.largeTitle)
                .padding()
        }

    }
}

#Preview {
    CircleLayoutView()
}
