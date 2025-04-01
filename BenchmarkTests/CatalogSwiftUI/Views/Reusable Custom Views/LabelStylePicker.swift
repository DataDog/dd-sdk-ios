//
//  LabelStylePicker.swift
//  SwiftUICatalog
//
//  Created by Barbara Personal on 2024-04-13.
//

import Foundation
import SwiftUI

struct LabelStylePicker: View {
    
    @Binding var selection: LabelStyleWrapper
    
    /// font styles options
    private let options: [LabelStyleWrapper] = [.iconOnly, .automatic, .labelOnly, .iconAndLabel]
    
    var body: some View {
        Picker(selection: $selection, label: Text("Label Style")) {
            ForEach(options, id: \.self) {
                Text($0.description)
            }
        }
    }
}

enum LabelStyleWrapper: Hashable {
    case iconOnly
    case labelOnly
    case iconAndLabel
    case automatic
    
    var labelStyle: any LabelStyle {
        switch self {
        case .iconOnly: return IconOnlyLabelStyle.iconOnly
        case .labelOnly: return TitleOnlyLabelStyle.titleOnly
        case .iconAndLabel: return TitleAndIconLabelStyle.titleAndIcon
        case .automatic: return DefaultLabelStyle.automatic
        }
    }
    
    var description: String {
        switch self {
        case .iconOnly: return "IconOnlyLabelStyle.iconOnly"
        case .labelOnly: return "TitleOnlyLabelStyle.titleOnly"
        case .iconAndLabel: return "TitleAndIconLabelStyle.titleAndIcon"
        case .automatic: return "DefaultLabelStyle.automatic"
        }
    }
}
