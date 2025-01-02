//
//  MyOwnButtonStyle.swift
//  SwiftUICatalog
//
//  Created by Barbara Rodeker on 2023-02-02.
//

import Foundation
import SwiftUI

/// My own button style
struct MyOwnButtonStyle : PrimitiveButtonStyle {
    
    /// Creates a view that represents the body of a button.
    /// When extending a style protocol like PrimitiveButtonStyle, you can go to the definition of this protocol
    /// and check which type of configuration it has associated. In this case there is a PrimitiveButtonStyleConfiguration
    /// Then you will see some public exposed variables, such as the original button label and a function to trigger the original action.
    /// You can simply use this variables and functions to create a completely new view around the original button
    ///
    /// - Parameter configuration : The properties of the button.
    public func makeBody(configuration: BorderedButtonStyle.Configuration) -> some View {
        return ZStack {
            Circle()
                .foregroundColor(Color.pink)
            Button {
                configuration.trigger()
            } label: {
                configuration.label
            }
            
        }
    }
    
}
