//
//  ColumnsLayoutView.swift
//  Catalog
//
//  Created by Barbara Personal on 2024-11-30.
//

import SwiftUI

struct ColumnsLayoutView: View {

    /// just to distinguish one view from the other / color palette access
    private let style = Style()
    /// columns for the layout
    private let columns = [
        Column(boxes: [.rectangle, .squared, .rectangle]),
        Column(boxes: [.squared, .squared, .rectangle, .squared, .squared]),
        Column(boxes: [.rectangle, .squared, .rectangle]),
        Column(boxes: [.squared, .squared, .rectangle, .squared, .squared])
    ]

    var body: some View {
        ScrollView {
            ColumnsLayout(columns: columns) {
                ForEach(0..<30) { index in
                    style.colorPalette1.randomElement()!
                        .border(.black, width: 3)
                }
            }
            .padding()
        }
    }
}

#Preview {
    ColumnsLayoutView()
}
