//
//  RoundedBordersModifier.swift
//  SwiftUICatalog
//
//  Created by Barbara Rodeker on 01.08.21.
//

import SwiftUI

struct RoundedBordersModifier: ViewModifier {
    
    var radius: CGFloat
    var lineWidth: CGFloat
    var color: Color = Color.accentColor
    
    func body(content: Content) -> some View {
        content
            .cornerRadius(radius)
            .overlay(
                RoundedRectangle(cornerRadius: radius)
                    .stroke(color,
                            lineWidth: lineWidth)
            )
        
    }
}
