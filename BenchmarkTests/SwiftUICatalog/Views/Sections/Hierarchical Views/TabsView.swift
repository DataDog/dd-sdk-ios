//
//  TabsView.swift
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
/// Examples on how to use  TAB VIEWS  in SwiftUI
/// OFFICIAL DOCUMENTATION:
/// https://developer.apple.com/documentation/swiftui/tabview
///

struct TabsView: View, Comparable {
    
    let id: String = "TabsView"
    /// allowed for selecting a tab
    @State private var currentTab = 0

    @Environment(\.openURL) var openURL
    
    var body: some View {
        example1
            .onAppear {
                // this simulate a selection of a given tab
                currentTab = 2
            }
    }
    
    private var example1: some View {
        TabView {
            Text("The First Tab")
                .tabItem {
                    Image(systemName: "1.square.fill")
                    Text("First")
                }
            Text("Another Tab")
                .tabItem {
                    Image(systemName: "2.square.fill")
                    Text("Second")
                }
                .badge(10)
            Text("The Last Tab")
                .tabItem {
                    Image(systemName: "3.square.fill")
                    Text("Third")
                }
                .badge("!")
        }
        .font(.headline)
    }
}

#Preview {
    
        TabsView()
    
}

// MARK: - HASHABLE

extension TabsView {
    
    static func == (lhs: TabsView, rhs: TabsView) -> Bool {
        return lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    
}


