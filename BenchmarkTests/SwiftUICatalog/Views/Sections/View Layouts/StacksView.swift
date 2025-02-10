//
//  StacksView.swift
//  SwiftUICatalog
//
// MIT License
//
// Copyright (c) 2021 Ali Ghayeni H
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
/// Examples on how to use  STACK VIEWS  in SwiftUI
/// OFFICIAL DOCUMENTATION:
/// https://developer.apple.com/documentation/swiftui/hstack
/// https://developer.apple.com/documentation/swiftui/vstack
/// https://developer.apple.com/documentation/swiftui/zstack
/// https://developer.apple.com/documentation/swiftui/lazyhstack
/// https://developer.apple.com/documentation/swiftui/lazyvstack
///

struct StacksView: View, Comparable {
    
    
    let id: String = "StacksView"
    
    let colors: [Color] =
    [ Color("Medium", bundle: .module), .green, .blue, .purple]
    
    var body: some View {
        PageContainer(content: ScrollView () {
            
            VStack(alignment: .leading) {
                DocumentationLinkView(link: "https://developer.apple.com/documentation/swiftui/hstack", name: "STACK VIEWS")
                
                Text("Stacks – equivalent to UIStackView in UIKit – come in three forms: horizontal (HStack), vertical (VStack) and depth-based (ZStack), with the latter being used when you want to place child views so they overlap.")
                    .fontWeight(.light)
                    .font(.title2)
                
                hStack
                    .modifier(Divided())
                lazyHStack
                    .modifier(Divided())
                vStack
                    .modifier(Divided())
                lazyVStack
            }
            
            zStack1
            Spacer(minLength: 40)
            zStack2
            
            ContributedByView(name: "Ali Ghayeni H",
                              link: "https://github.com/alighayeni")
            .padding(.top, 80)
            
        })
        // end of page container
    }
    
    private var lazyVStack: some View {
        GroupBox {
            VStack(alignment: .leading)  {
                
                Text("An example of a lazyVstack with TextViews")
                    .fontWeight(.heavy)
                    .font(.title)
                Text("The stack is “lazy,” in that the stack view doesn’t create items until it needs to render them onscreen.")
                    .fontWeight(.light)
                    .font(.title2)
                ScrollView () {
                    LazyVStack {
                        ForEach(
                            1...100,
                            id: \.self
                        ) {
                            Text("Lazy Item \($0)")
                        }
                    }
                }
                .frame(maxHeight:150)
                
            }
        }
    }
    
    private var zStack1: some View {
        GroupBox {
            VStack(alignment: .leading)  {
                Text("An example of a ZStack with RectangleViews")
                    .fontWeight(.heavy)
                    .font(.title)
                Text("The ZStack assigns each successive child view a higher z-axis value than the one before it, meaning later children appear “on top” of earlier ones.")
                    .fontWeight(.light)
                    .font(.title2)
                ZStack {
                    ForEach(0..<colors.count, id: \.self) {
                        Rectangle()
                            .fill(colors[$0])
                            .frame(width: 100, height: 100)
                            .offset(x: CGFloat($0) * 10.0,
                                    y: CGFloat($0) * 10.0)
                    }
                }
                .padding(.bottom, 50)
            }
        }
    }
    
    private var zStack2: some View {
        GroupBox {
            VStack(alignment: .leading)  {
                Text("some text over a picture for example (with ZStack)")
                    .fontWeight(.light)
                    .font(.title2)
                ZStack() {
                    Image(systemName: "captions.bubble")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                    Text("Bubble with caption")
                        .font(.largeTitle)
                        .background(Color.black)
                        .foregroundColor(.white)
                }
                
            }
        }
    }
    
    private var lazyHStack: some View {
        GroupBox {
            VStack(alignment: .leading)  {
                
                Text("An example of a lazyHstack with TextViews")
                    .fontWeight(.heavy)
                    .font(.title)
                Text("The stack is “lazy,” in that the stack view doesn’t create items until it needs to render them onscreen.")
                    .fontWeight(.light)
                    .font(.title2)
                ScrollView (.horizontal) {
                    LazyHStack(
                        alignment: .top,
                        spacing: 8
                    ) {
                        ForEach(
                            1...100,
                            id: \.self
                        ) {
                            Text("Lazy Item \($0)")
                        }
                    }
                    .padding()
                }
                
            }
        }
    }
    
    private var vStack: some View {
        GroupBox {
            VStack(alignment: .leading)  {
                Text("An example of a Vstack with TextViews")
                    .fontWeight(.heavy)
                    .font(.title)
                Text("A view that arranges its children in a vertical line. VStack renders the views all at once, regardless of whether they are on- or offscreen. Use the regular VStack when you have a small number of child views or don’t want the delayed rendering behavior of the “lazy” version.")
                    .fontWeight(.light)
                    .font(.title2)
                // MARK: - Vstack
                ScrollView () {
                    VStack {
                        ForEach(
                            1...10,
                            id: \.self
                        ) {
                            Text("Item \($0)")
                        }
                    }
                }
                .frame(maxHeight:150)
                
            }
        }
    }
    
    private var hStack: some View {
        GroupBox {
            VStack(alignment: .leading) {
                Text("An example of a Hstack with TextViews")
                    .fontWeight(.heavy)
                    .font(.title)
                Text("A view that arranges its children in a horizontal line.")
                    .fontWeight(.light)
                    .font(.title2)
                ScrollView (.horizontal) {
                    HStack(
                        alignment: .top,
                        spacing: 8
                    ) {
                        ForEach(
                            1...10,
                            id: \.self
                        ) {
                            Text("Item \($0)")
                        }
                    }
                    .padding()
                }
            }
        }
        
    }
}

#Preview {
    
        StacksView()
    
}

// MARK: - HASHABLE

extension StacksView {
    
    static func == (lhs: StacksView, rhs: StacksView) -> Bool {
        return lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    
}



