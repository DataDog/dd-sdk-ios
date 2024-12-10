//
//  RadialLayout.swift
//  Catalog
//
//  Created by Barbara Personal on 2024-11-30.
//

import Foundation
import SwiftUI

/// A custom layout to position views around a circle
/// you can use it for making a clock for example
struct CircleLayout: Layout {

    @available(iOS 16.0, tvOS 16.0, *)
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    @available(iOS 16.0, tvOS 16.0, *)
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        // calculate the radius
        let radius = min(bounds.size.width, bounds.size.height) / 2
        
        // sparce angle - the amount of space divided by the total count of subviews
        let sparceAngle = Angle.degrees(360 / Double(subviews.count)).radians
        
        for (index, subview) in subviews.enumerated() {
            let viewSize = subview.sizeThatFits(.unspecified)
            
            // calculate the X and Y position so this view lies inside our circle's edge
            let x = cos(sparceAngle * Double(index) - .pi / 2) * (radius - viewSize.width / 2)
            let y = sin(sparceAngle * Double(index) - .pi / 2) * (radius - viewSize.height / 2)
            
            // position the subview
            let point = CGPoint(x: bounds.midX + x, y: bounds.midY + y)
            subview.place(at: point, anchor: .center, proposal: .unspecified)
        }
    }
}
