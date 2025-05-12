//
//  OutlinesGroupsView.swift
//  SwiftUICatalog
//
// MIT License
//
// Copyright (c) 2021 Ali Ghayeni h
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
/// Examples on how to use  OUTLINE GROUPs  in SwiftUI
/// OFFICIAL DOCUMENTATION:     https://developer.apple.com/documentation/swiftui/outlinegroup
///

struct OutlinesGroupsView: View, Comparable {
    
    let id: String = "OutlinesGroupsView"
    
    @Environment(\.openURL) var openURL
    
    struct FileItem: Hashable, Identifiable, CustomStringConvertible {
        var id: Self { self }
        var name: String
        var children: [FileItem]? = nil
        var description: String {
            switch children {
            case nil:
                return "📄 \(name)"
            case .some(let children):
                return children.isEmpty ? "📂 \(name)" : "📁 \(name)"
            }
        }
    }
    
    let data =
    FileItem(name: "Users", children:
                [FileItem(name: " user1234", children:
                            [FileItem(name: "   Photos", children:
                                        [FileItem(name: "photo001.jpg"),
                                         FileItem(name: "photo002.jpg")]),
                             FileItem(name: "   Movies", children:
                                        [FileItem(name: "movie001.mp4")]),
                             FileItem(name: "   Documents", children: [])
                            ]),
                 FileItem(name: " newuser", children:
                            [FileItem(name: "   Documents", children: [])
                            ])
                ])
    
    
    var body: some View {
        
        PageContainer(content:
                        
                        VStack(alignment: .leading) {
            
            DocumentationLinkView(link: "https://developer.apple.com/documentation/swiftui/outlinegroup")
                .padding()
            
            GroupBox {
                Text("A structure that computes views and disclosure groups on demand from an underlying collection of tree-structured, identified data.")
                    .fontWeight(.light)
                    .font(.title2)
                
                Text("Use an outline group when you need a view that can represent a hierarchy of data by using disclosure views. \nThis allows the user to navigate the tree structure by using the disclosure views to expand and collapse branches.\nTry it out by clicking on the > below:")
                    .fontWeight(.light)
                    .font(.title2)
                
                Group {
                    OutlineGroup(data, children: \.children) { item in
                        Text("\(item.description)")}
                }
            }
            Spacer()
            ContributedByView(name: "Ali Ghayeni H",
                              link: "https://github.com/alighayeni")
            .padding(.top, 80)
            
        })
    }
}

#Preview {
    
        OutlinesGroupsView()
    
}

// MARK: - HASHABLE

extension OutlinesGroupsView {
    
    static func == (lhs: OutlinesGroupsView, rhs: OutlinesGroupsView) -> Bool {
        return lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    
}


