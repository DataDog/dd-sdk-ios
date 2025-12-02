//
//  ColumnsLayout.swift
//  Catalog
//
//  Created by Barbara Personal on 2024-11-30.
//

import Foundation
import SwiftUI

/// in this layout we distribute the views in columns
/// each column can have different boxes
struct Column {
    /// this will be the structural definition of the rows
    let boxes: [Box]
    
    
    /// total height of the column, depending on the boxes definitions
    /// - Parameters:
    ///   - width: the width to fill
    ///   - elementsCount: how many elements there will be in the columns
    /// - Returns:
    func height(for width: CGFloat, elementsCount: Int) -> CGFloat {
        var boxIndex = 0
        var height: CGFloat = 0
        for _ in 0..<elementsCount {
            let box = boxes[boxIndex]
            height += box.height(for: width)
            boxIndex += 1
            boxIndex = boxIndex % boxes.count
        }
        return height
    }
    
    
    /// the height of the column at an specific element index
    /// - Parameters:
    ///   - width: width of the column
    ///   - elementIndex:
    /// - Returns:
    func height(for width: CGFloat, elementIndex: Int) -> CGFloat {
        let boxIndex = elementIndex % boxes.count
        return boxes[boxIndex].height(for: width)
    }
}

/// definition for "rows" in each column
enum Box {
    /// it will take the width as the height
    case squared
    /// it will occupied double width
    case rectangle
    
    func height(for width: CGFloat) -> CGFloat {
        switch self {
        case .squared: width
        case .rectangle: width * 2
        }
    }
}


/// Distributes the views in a set of columns, with squares / rectangles of different sizes
struct ColumnsLayout: Layout {
    
    private let columns: [Column]
    
    init(columns: [Column]) {
        self.columns = columns
    }
    
    /// calculating the height based on the longest column
    @available(iOS 16.0, tvOS 16.0, *)
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let totalViews = subviews.count
        let proposedSize = proposal.replacingUnspecifiedDimensions()
        let width = proposedSize.width
        let height = proposedSize.height
        let columnWidth = width / CGFloat(columns.count)
        let viewsPerColumn = totalViews / columns.count
        let longestColumn = (columns.map { $0.height(for: columnWidth, elementsCount: viewsPerColumn) }).sorted().first ?? height
        
        return CGSize(width: width, height: longestColumn)
        
    }

    @available(iOS 16.0, tvOS 16.0, *)
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let columnWidth = bounds.width / CGFloat(columns.count)
        var columnIndex = 0
        var x = bounds.minX

        // iterates through the elements and columns, in each column it iterates through the boxes
        for (index, subview) in subviews.enumerated() {
            
            let elementIndexForColumn = index / columns.count
            let initialY = columns[columnIndex].height(for: columnWidth, elementsCount: elementIndexForColumn)
            let height = columns[columnIndex].height(for: columnWidth, elementIndex: elementIndexForColumn)

            // position the subview
            let point = CGPoint(x: x, y: bounds.minY + initialY)
            subview.place(at: point, anchor: .topLeading, proposal: .init(width: columnWidth, height: height))
            
            // we increment the column index and then check that we are not going out of bounds
            columnIndex += 1
            columnIndex = columnIndex % columns.count
            if columnIndex == 0 {
                x = bounds.minX
            } else {
                x = x + columnWidth
            }
        }
    }
    
    
    
}
