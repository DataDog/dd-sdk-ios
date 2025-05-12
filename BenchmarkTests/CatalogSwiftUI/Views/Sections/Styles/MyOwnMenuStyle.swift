//
//  MyOwnMenuStyle.swift
//  SwiftUICatalog
//
//  Created by Barbara Rodeker on 2023-02-04.
//

import Foundation
import SwiftUI

/// Defining a custom menu style
struct MyOwnMenuStyle: MenuStyle {
    
    /// - Parameter configuration : The properties of the menu .
    public func makeBody(configuration: MenuStyle.Configuration) -> some View {
        Menu(configuration)
            .font(.largeTitle)
            .border(Color.pink)
        // This type of custom configuration does not seem too flexible.
        // You can only add modifier to a newly created Meny with the same original configuration.
        //        return VStack {
        //            Image(systemName: "build")
        //            Menu(configuration)
        //        }
    }
    
}
