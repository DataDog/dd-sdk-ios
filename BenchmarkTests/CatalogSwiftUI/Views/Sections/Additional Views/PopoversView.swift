//
//  PopoversComponentView.swift
//  SwiftUICatalog
//
// MIT License
//
// Copyright (c) 2021 { YOUR NAME HERE 🏆 }
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

struct PopoversComponentView: View, Comparable {
    
    let id: String = "PopoversComponentView"
    
    @State private var showingPopover = false
    private let documentationURLString = "https://developer.apple.com/documentation/swiftui/button/popover(ispresented:attachmentanchor:arrowedge:content:)"
    
    var body: some View {
        
        PageContainer(content:
                        
                        ScrollView {
            DocumentationLinkView(link: documentationURLString, name: "POPOVERS")
            
            WebView(url: URL(string: documentationURLString)!)
                .frame(height: 400)
            
            Button(action: {
                showingPopover = true
            },
                   label: {
                Text("Show menu")
                    .modifier(ButtonFontModifier())
                    .overlay(
                        RoundedCorners(tl: 10,
                                       tr: 0,
                                       bl: 0,
                                       br: 10)
                        .stroke(Color.accentColor, lineWidth: 5)
                    )
            })
            .popover(isPresented: $showingPopover,
                     arrowEdge: .bottom) {
                VStack {
                    Text("Here you can insert any other type of view for your popover")
                        .modifier(Divided())
                    Button("Click to dismiss") {
                        showingPopover = false
                    }
                }
                .padding()
            }
            
        })
        //end of page container
        
    }
}

#Preview {
    
        PopoversComponentView()
}

// MARK: - HASHABLE

extension PopoversComponentView {
    
    static func == (lhs: PopoversComponentView, rhs: PopoversComponentView) -> Bool {
        return lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    
}


