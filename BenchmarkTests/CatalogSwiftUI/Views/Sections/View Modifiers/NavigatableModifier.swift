//
//  NavigatableModifier.swift
//  SwiftUICatalog
//
//  Created by Barbara Rodeker on 2022-11-03.
//  Credits to: https://stackoverflow.com/questions/56437335/go-to-a-new-view-using-swiftui
//

import SwiftUI

extension View {
    
    /// Navigate to a new view. When the main view is not a navigation view, then embbeding a navigation view will make the navigation link
    /// open in the frame where the navigation view is, therefore this modifier helps to open links in a new view
    /// - Parameters:
    ///   - view: View to navigate to.
    ///   - binding: Only navigates when this condition is `true`.
    func navigate<NewView: View>(to view: NewView, when binding: Binding<Bool>) -> some View {
        NavigationView {
            ZStack {
                self
                    .navigationBarTitle("")
                    .navigationBarHidden(true)
                
                NavigationLink(
                    destination: view
                        .navigationBarTitle("")
                        .navigationBarHidden(true)
                ) {
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}
