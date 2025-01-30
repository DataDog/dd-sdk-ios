//
//  ScrollViewsView.swift
//  SwiftUICatalog
//
// MIT License
//
// Copyright (c) 2021 Barbara Martina
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
/// Examples on how to use  SCROLLVIEWS  in SwiftUI
/// OFFICIAL DOCUMENTATION:     https://developer.apple.com/documentation/swiftui/scrollview
/// https://developer.apple.com/documentation/swiftui/scrollviewreader
/// https://developer.apple.com/documentation/swiftui/scrollviewproxy
///

struct ScrollViewsView: View, Comparable {
    
    
    let id: String = "ScrollViewsView"
    
    @State private var topButtonId: String = "top-button"
    @State private var bottomButtonId: String = "bottom-button"
    
    var body: some View {
        
        PageContainer(content:
                        
                        
                        ScrollViewReader { proxy in
            
            VStack(alignment: .leading) {
                
                DocumentationLinkView(link: "https://developer.apple.com/documentation/swiftui/scrollview", name: "SCROLL VIEWS")
                
                GroupBox {
                    introductionTexts
                    scrollToBottomButton(proxy: proxy)
                    VStack(spacing: 0) {
                        ForEach(0..<100) { i in
                            Text("Row \(i)")
                                .multilineTextAlignment(.leading)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    scrollToTopButton(proxy: proxy)
                }
            }
            
            ContributedByView(name: "Barbara Martina",
                              link: "https://github.com/barbaramartina")
            .padding(.top, 80)
            
        })
        // end of page container
        
    }
    
    private var introductionTexts: some View {
        Group {
            Text("Scrollviews in SwiftUI")
                .fontWeight(.heavy)
                .font(.title)
            Text("Examples on using ScrollViews and programatically manipulate them by assigning identifiers to its child views")
                .fontWeight(.light)
                .font(.title2)
        }
    }
    
    private func scrollToTopButton(proxy: ScrollViewProxy) -> some View {
        Button("Back to Top") {
            withAnimation {
                proxy.scrollTo(topButtonId)
            }
        }
        .id(bottomButtonId)
    }
    private func scrollToBottomButton(proxy: ScrollViewProxy) -> some View {
        Button("Scroll to Bottom") {
            withAnimation {
                proxy.scrollTo(bottomButtonId)
            }
        }
        .id(topButtonId)
        
    }
}

#Preview {
    
        ScrollViewsView()
    
}

// MARK: - HASHABLE

extension ScrollViewsView {
    
    static func == (lhs: ScrollViewsView, rhs: ScrollViewsView) -> Bool {
        return lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    
}


