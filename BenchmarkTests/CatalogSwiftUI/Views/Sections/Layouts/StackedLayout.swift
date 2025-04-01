//
//  StackedLayout.swift
//  Catalog
//
//  Created by Barbara Personal on 2024-11-30.
//

import Foundation
import SwiftUI

/// it will position the views one on top of each other, top to bottom, leading to trailing
/// with an offset calculated depending on the amount of stacked views, and the available space
struct StackedLayout: Layout {
    
    /// for this layout, since the calculations are realtively complex, the preview were crashing
    /// so I needed to add a cache
    struct Cache {
        var sizes: [CGSize] = []
    }
    
    func makeCache(subviews: Subviews) -> Cache {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        return Cache(sizes: sizes)
    }
    
    func updateCache(_ cache: inout Cache, subviews: Subviews) {
        cache.sizes = subviews.map { $0.sizeThatFits(.unspecified) }
    }

    @available(iOS 16.0, tvOS 16.0, *)
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        // using the available space
        proposal.replacingUnspecifiedDimensions()
    }

    @available(iOS 16.0, tvOS 16.0, *)
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        // how much space do we have?
        let availableWidth = bounds.size.width
        let availableHeight = bounds.size.height
        // how many subviews?
        let totalElements: CGFloat = CGFloat(subviews.count)
        // which one is the longest?
        let biggestSubViewWidth = (cache.sizes.sorted { size1, size2 in
            size1.width > size2.width
        }).first?.width ?? 0
        // which one is the tallest?
        let biggestSubViewHeight =  (cache.sizes.sorted { size1, size2 in
            size1.height > size2.height
        }).first?.height ?? 0
        // how much we can offset them, in the available space? keeping all of them fully visible
        let possibleXOffset = (availableWidth - biggestSubViewWidth) / totalElements
        let possibleYOffset = (availableHeight - biggestSubViewHeight) / totalElements

        var x = bounds.minX
        var y = bounds.minY
        subviews.forEach { subview in
            // position the subview
            let point = CGPoint(x: x, y: y)
            subview.place(at: point, anchor: .topLeading, proposal: .unspecified)
            
            x += possibleXOffset
            y += possibleYOffset
        }
    }

}
