//
//  TagsCloudLayoutView.swift
//  Catalog
//
//  Created by Barbara Personal on 2024-11-30.
//

import SwiftUI

/// A basic example, which can be used to implement a tags cloud.
/// You can create a generic view, which has a weight/scale, and then give the views
/// to a TagsCloudLayout, as we show here.
struct TagsCloudLayoutView: View {
    /// used to access the color palette
    private let style = Style()
    /// simulating random view's weight
    private var scales: [CGFloat] = [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0, 1.2, 1.3, 1.4, 1.5]
    
    var body: some View {
        TagsCloudLayout {
            ForEach(0..<150) { index in
                VStack {
                    Text("\(index)")
                        .fontWeight(.heavy)
                        .font(.largeTitle)
                }
                .padding(8)
                .background(
                    style.colorPalette1.randomElement()
                )
                .cornerRadius(8)
                .scaleEffect(scales.randomElement() ?? 1.0)
                .shadow(color: .black,
                        radius: 10)
            }
        }
        .padding()
    }
}

#Preview {
    TagsCloudLayoutView()
}
