//
//  ButtonBorderModifier.swift
//  SwiftUICatalog
//
//  Created by Barbara Rodeker on 01.08.21.
//

import SwiftUI

struct ButtonBorderModifier: ViewModifier {
    
    func body(content: Content) -> some View {
        content
            .border(Color.accentColor, width: 5)
        
    }
}
