//
//  StackedLayoutView.swift
//  Catalog
//
//  Created by Barbara Personal on 2024-11-30.
//

import SwiftUI

struct StackedLayoutView: View {
    
    /// just to distinguish one view from the other / color palette access
    private let style = Style()

    var body: some View {
        StackedLayout {
            ForEach(0..<10) { index in
                VStack {
                    Text("\(index)")
                        .fontWeight(.heavy)
                        .font(.largeTitle)
                }
                .padding(8)
                .frame(minWidth: 150, minHeight: 240)
                .background(
                    style.colorPalette1.randomElement()
                )
                .cornerRadius(8)
                .shadow(radius: 10)
            }
        }
        .padding()
    }
}

#Preview {
    StackedLayoutView()
}
