//
//  DocumentationLinkView.swift
//  SwiftUICatalog
//
//  Created by Barbara Rodeker on 13.11.21.
//
// MIT License
//
// Copyright (c) 2024 Barbara Rodeker
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

import Foundation
import SwiftUI

/// A view with a link to Apple Docs
struct DocumentationLinkView: View, Identifiable {
    
    var id: String {
        return link
    }
    
    /// documentation link
    let link: String
    
    /// name of the component been documented
    let name: String
    
    /// used to present the web view with the documentation link
    @State private var isSheetPresented: Bool = false
    
    init(link: String, name: String? = nil) {
        self.link = link
        self.name = name ?? "Documentation"
    }
    
    var body: some View {
        Button(action: {
            isSheetPresented.toggle()
        }, label: {
            HStack {
                Image(systemName: "book.and.wrench")
                    .accessibilityLabel("Documentation")
                    .accessibilityHint("Touching this button will take you outside the application and into the browser, where you can access more information about the current example.")
            }
            .padding(12)
            .fontWeight(.bold)
            .foregroundColor(Color("Medium", bundle: .module))
            .background(.primary)
            .modifier(RoundedBordersModifier(radius: 8, lineWidth: 1))
        })
        .padding(.bottom, 16)
        .modifier(ViewAlignmentModifier(alignment: .trailing))
        .accessibilityAddTraits(.isButton)
        .sheet(isPresented: $isSheetPresented) {
            WebView(url: URL(string: link)!)
        }
    }
}

#Preview {
    
        DocumentationLinkView(link: "www.apple.com")
    
}
