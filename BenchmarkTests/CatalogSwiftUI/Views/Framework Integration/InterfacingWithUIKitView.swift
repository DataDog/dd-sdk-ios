//
//  InterfacingWithUIKitView.swift
//  SwiftUICatalog
//
// MIT License
//
// Copyright (c) 2023 Ali Ghayeni H
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

import SwiftUI

///
/// Examples on how to use Interfacing with UIkit  in SwiftUI
/// OFFICIAL DOCUMENTATION https://developer.apple.com/tutorials/swiftui/interfacing-with-uikit
///
struct InterfacingWithUIKitView<Page: View>: View {
    var pages: [Page]
    @State private var currentPage = 0
    
    
    var body: some View {
        ScrollView {
            VStack {
                Group(){
                    HStack(){
                        Text("Framework Integration")
                            .fontWeight(.light)
                            .font(.title2)
                    }
                    HStack{
                        Text("Framework Integration Interfacing with UIKit")
                            .fontWeight(.heavy)
                            .font(.title)
                        
                            .multilineTextAlignment(.center)
                    }
                    Text("SwiftUI works seamlessly with the existing UI frameworks on all Apple platforms. For example, you can place UIKit views and view controllers inside SwiftUI views, and vice versa.")
                        .fontWeight(.ultraLight)
                        .font(.title3)
                }
                .padding(5)
                Group(){
                    ZStack(alignment: .bottomTrailing) {
                        PageViewController(pages: pages, currentPage: $currentPage)
                        PageControl(numberOfPages: pages.count, currentPage: $currentPage)
                            .frame(width: CGFloat(pages.count * 18))
                            .padding(.trailing)
                    }
                    .frame(width: UIScreen.main.bounds.width, height: 250)
                }
                .padding(5)
                ContributedByView(name: "Ali Ghayeni H",
                                  link: "https://github.com/alighayeni")
                .padding(.top, 80)
            }
        }
        .frame(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height)
        .padding(.top, 150)
    }
    
    
}

#Preview {
    
        InterfacingWithUIKitView(pages: ModelData().features.map { FeatureCardView(landmark: $0) })
        .aspectRatio(3 / 2, contentMode: .fit)
}
