//
//  UIFontTextStylePicker.swift
//  SwiftUICatalog
//
//  Created by Barbara Personal on 2024-04-13.
//

import Foundation
import SwiftUI

struct UIFontTextStylePicker: View {
    
    @Binding var selection: UIFont.TextStyle
    
    /// font styles options
    private let options: [UIFont.TextStyle] = [.body, .callout, .caption1, .footnote, .caption2, .extraLargeTitle, .extraLargeTitle2, .headline, .subheadline, .largeTitle, .title1, .title2, .title3]
    
    var body: some View {
        Picker(selection: $selection, label: Text("Font Style")) {
            ForEach(options, id: \.self) {
                Text($0.description)
            }
        }
    }
}

extension UIFont.TextStyle {
    var description: String {
        switch self {
        case .body: return "body"
        case .callout: return "callout"
        case .caption1: return "caption1"
        case .caption2: return "caption2"
        case .footnote: return "footnote"
        case .extraLargeTitle: return "extraLargeTitle"
        case .extraLargeTitle2: return "extraLargeTitle2"
        case .headline: return "headline"
        case .subheadline: return "subheadline"
        case .largeTitle: return "largeTitle"
        case .title1: return "title1"
        case .title2: return "title2"
        case .title3: return "title3"
        default: return ""
        }
    }
}
