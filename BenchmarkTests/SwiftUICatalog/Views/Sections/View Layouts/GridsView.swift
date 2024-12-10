//
//  GridsView.swift
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
/// Examples on how to use  GRIDS  in SwiftUI
/// OFFICIAL DOCUMENTATION:
/// https://developer.apple.com/documentation/swiftui/lazyhgrid
/// https://developer.apple.com/documentation/swiftui/lazyvgrid
/// https://developer.apple.com/documentation/swiftui/griditem
///

struct GridsView: View, Comparable {
    @Environment(\.openURL) var openURL
    
    let id: String = "GridsView"
    
    private let rows: [GridItem] = Array(repeating: .init(.fixed(20)), count: 2)
    private let columns: [GridItem] = Array(repeating: .init(.flexible()), count: 2)
    private let adaptiveColumns: [GridItem] = [GridItem(.adaptive(minimum: 50))]
    
    var body: some View {
        
        PageContainer(content: ScrollView {
            
            VStack(alignment: .leading) {
                DocumentationLinkView(link: "https://developer.apple.com/documentation/swiftui/lazyhgrid", name: "GRID VIEWS")
                // intro
                gridsIntroduction
                // lazy H grid example with text an emojies
                lazyAdaptiveGrid
                    .modifier(Divided())
                // vertical grid example with text and emojies
                lazyHGrid
                    .modifier(Divided())
                // vertical example with adaptive layout
                lazyVGrid
                
                ContributedByView(name: "Ali Ghayeni H",
                                  link: "https://github.com/alighayeni")
                .padding(.top, 80)
            }
        })
        
    }
    
    // MARK: - Lazy Vertical Grid
    
    private var lazyVGrid: some View {
        GroupBox {
            VStack(alignment: .leading) {
                Text("Lazy Vertical Grid")
                    .fontWeight(.heavy)
                    .font(.title)
                Text("In the following example, a ScrollView contains a LazyHGrid that consists of a horizontally-arranged grid of Text views, aligned to the top of the scroll view.")
                    .fontWeight(.light)
                    .font(.title2)
                ScrollView {
                    LazyVGrid(columns: columns) {
                        ForEach((0...79), id: \.self) {
                            emojieWith(index: $0)
                        }
                    }
                }
                .frame(width: 300, height: 150, alignment: .center)
            }
        }
    }
    
    private func emojieWith(index: Int) -> some View {
        VStack(spacing: 0) {
            let codepoint = index + 0x1f600
            let codepointString = String(format: "%02X", codepoint)
            Text("\(codepointString)")
            let emoji = String(Character(UnicodeScalar(codepoint)!))
            Text("\(emoji)")
        }
    }
    
    private var lazyAdaptiveGrid: some View {
        GroupBox {
            VStack(alignment: .leading) {
                Text("Adaptive Grid")
                    .fontWeight(.heavy)
                    .font(.title)
                Text("An adaptive grid will fill in the rows/columns according to the space available in the screen. You can try it out by rotating your phone.")
                    .fontWeight(.light)
                    .font(.title2)
                ScrollView {
                    LazyVGrid(columns: adaptiveColumns) {
                        ForEach((0...79), id: \.self) { index in
                            emojieWith(index: index)
                                .padding(4)
                                .background(Color.secondary)
                                .cornerRadius(8)
                                .frame(width: CGFloat.random(in: 60...90))
                        }
                    }
                }
                .frame(height: 250, alignment: .center)
            }
        }
    }
    
    // MARK: - Lazy Horizontal Grid
    
    private var lazyHGrid: some View {
        GroupBox {
            VStack(alignment: .leading) {
                DocumentationLinkView(link: "https://developer.apple.com/documentation/swiftui/lazyhgrid")
                Text("Lazy Horizontal Grid")
                    .fontWeight(.heavy)
                    .font(.title)
                Text("In the following example, a ScrollView contains a LazyHGrid that consists of a horizontally-arranged grid of Text views, aligned to the top of the scroll view.")
                    .fontWeight(.light)
                    .font(.title2)
                ScrollView(.horizontal) {
                    LazyHGrid(rows: rows, alignment: .top) {
                        ForEach((0...79), id: \.self) {
                            emojieWith(index: $0)
                        }
                    }
                    .frame(width: 100, height: 100, alignment: .center)
                }
            }
        }
    }
    
    private var gridsIntroduction: some View {
        VStack(alignment: .leading) {
            Text("Grid Item")
                .fontWeight(.heavy)
                .font(.title)
            Text("A description of a single grid item, such as a row or a column.")
                .fontWeight(.light)
                .font(.title2)
                .modifier(ViewAlignmentModifier(alignment: .leading))
            Text("You use GridItem instances to configure the layout of items in LazyHGrid and LazyVGrid views. Each grid item specifies layout properties like spacing and alignment, which the grid view uses to size and position all items in a given column or row.")
                .fontWeight(.light)
                .font(.title2)
            Text("The grid is “lazy,” in that the grid view does not create items until they are needed.")
                .fontWeight(.light)
                .font(.title2)
                .modifier(ViewAlignmentModifier(alignment: .leading))
        }
    }
}

#Preview {
    
        GridsView()
    
}

// MARK: - HASHABLE

extension GridsView {
    
    static func == (lhs: GridsView, rhs: GridsView) -> Bool {
        return lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    
}



