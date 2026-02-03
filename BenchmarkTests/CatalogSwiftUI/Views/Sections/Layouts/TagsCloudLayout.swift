//
//  TagsCloudLayout.swift
//  Catalog
//
//  Created by Barbara Personal on 2024-11-30.
//

import Foundation
import SwiftUI

/// Take the subviews and distributes them randomly in the available space
/// it can be used to implement a tags cloud, just make sure to give the subviews a scale, depending on the weight they have
struct TagsCloudLayout: Layout {
    
    /// use the default sizing
    @available(iOS 16.0, tvOS 16.0, *)
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }
    
    /// we create a cloud, overlapping the views.
    @available(iOS 16.0, tvOS 16.0, *)
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {

        subviews.forEach { subview in
            let viewSize = subview.sizeThatFits(.unspecified)
            
            // safe bounds were the subview can fit without going out of bounds
            let viewWidth = viewSize.width / 2
            let viewHeight = viewSize.height / 2
            let safeBound = CGRect(x: bounds.minX + viewWidth,
                                   y: bounds.minY + viewHeight,
                                   width: bounds.width - viewWidth,
                                   height: bounds.height - viewHeight)

            // calculate the X and Y position randomly, inside the safe bounds
            let x = CGFloat.random(in: safeBound.minX..<safeBound.maxX)
            let y = CGFloat.random(in: safeBound.minY..<safeBound.maxY)

            // position the subview
            let point = CGPoint(x: x, y: y)
            subview.place(at: point, anchor: .center, proposal: ProposedViewSize(viewSize))
        }
    }

}
