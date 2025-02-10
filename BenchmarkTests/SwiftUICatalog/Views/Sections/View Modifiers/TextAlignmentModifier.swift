//
//  ViewAlignmentModifier.swift
//  SwiftUICatalog
//
//  Created by Barbara Rodeker on 2023-12-08.
//

import Foundation

import SwiftUI

/// Text alignment only aligns the content/text inside the portion of the screen that the text container occupies
/// but if there is only 1 container in the screen, then the container is centered and the text too
/// to simulate the container being aligned to the leading or trailing, spacers need to be added before or after the container
/// if the container remains in the middle, then spacers are added to both ends.
struct ViewAlignmentModifier: ViewModifier {
    
    var alignment: TextAlignment
    
    func body(content: Content) -> some View {
        HStack {
            if alignment == .trailing || alignment == .center {
                Spacer()
            }
            content
            if alignment == .leading || alignment == .center {
                Spacer()
            }
        }
    }
}

