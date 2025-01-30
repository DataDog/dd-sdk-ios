//
//  ToolbarsComponentView.swift
//  SwiftUICatalog
//
// MIT License
//
// Copyright (c) 2022 Barbara Martina
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.
//
//

import SwiftUI

///
/// Example on how to set and configure Tool Bars on SwiftUI
/// OFFICIAL DOCUMENTATION https://developer.apple.com/documentation/swiftui/view/toolbar(id:content:)
///
struct ToolbarsComponentView: View, Comparable {
    
    let id: String = "ToolbarsComponentView"
    
    @State private var bold = false
    @State private var italic = false
    @State private var fontSize = 12.0
    
    
    var body: some View {
        
        PageContainer(content:
                        
                        DocumentationLinkView(link: "https://developer.apple.com/documentation/swiftui/view/toolbar(id:content:)", name: "")
                      //.toolbar {
                      //                   The placement can have different meanings:
                      //                   - automatic:
                      //                   The system places the item automatically, depending on many factors including the platform, size class, or presence of other items.
                      //                   - principal
                      //                   The system places the item in the principal item section.
                      //                   status
                      //                   The item represents a change in status for the current context.
                      //                   - primaryAction: The item represents a primary action.
                      //                   - confirmationAction: The item represents a confirmation action for a modal interface.
                      //                   - cancellationAction: The item represents a cancellation action for a modal interface.
                      //                   - destructiveAction: The item represents a destructive action for a modal interface.
                      //                   - navigation: The item represents a navigation action.
                      //                   - navigationBarLeading: Places the item in the leading edge of the navigation bar.
                      //                   - navigationBarTrailing: Places the item in the trailing edge of the navigation bar.
                      //                   - keyboard: The item is placed in the keyboard section.
                      //                   - bottomBar: Places the item in the bottom toolbar.
                      //                    ToolbarItemGroup(placement: .bottomBar) {
                      //                        Button("bottom button 1", action: {})
                      //                    }
                      //}
                      // Another way of creating a tool bar is explicitly declaring each item. In the example below you can force the tool bar items to be shown in the navigation bar leading and trailing positions
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Button 1", action: {})
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Button 2", action: {})
                }
                
            }
        )
        
    }
}

#Preview {
    
        ToolbarsComponentView()
    
}

// MARK: - HASHABLE

extension ToolbarsComponentView {
    
    static func == (lhs: ToolbarsComponentView, rhs: ToolbarsComponentView) -> Bool {
        return lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    
}


