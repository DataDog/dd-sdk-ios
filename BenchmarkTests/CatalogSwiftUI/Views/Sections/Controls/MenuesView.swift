//
//  MenusComponentView.swift
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

import SwiftUI

///
/// Samples on how to create menus in SwiftUI
/// OFFICIAL DOCUMENTATION https://developer.apple.com/documentation/swiftui/menu
///
struct MenusComponentView: View, Comparable {
    
    let id: String = "MenusComponentView"
    
    
    //Custom Menu item Style
    private let redBorderMenuStyle: RedBorderMenuStyle = RedBorderMenuStyle.init()
    
    var body: some View {
        
        PageContainer(content:
                        
                        ScrollView{
            
            DocumentationLinkView(link: "https://developer.apple.com/documentation/swiftui/menu", name: "MENUES")
            
            example1
                .modifier(Divided())
            example2
                .modifier(Divided())
            example3
                .modifier(Divided())
            example4
            
            ContributedByView(name: "Ali Ghayeni H",
                              link: "https://github.com/alighayeni")
            .padding(.top, 80)
            
            
            
            
        })
    }
    
    func duplicate() { action() }
    func rename() { action() }
    func delete() { action() }
    func copy() { action() }
    func copyFormatted() { action() }
    func copyPath() { action() }
    func setInPoint() { action() }
    func setOutPoint() { action() }
    func addCurrentTabToReadingList() { action() }
    func bookmarkAll() { action() }
    func show() { action() }
    func addBookmark() { action() }
    
    func action() {
#if DEBUG
        print("The Action function called")
#endif
    }
    
    func primaryAction() {
#if DEBUG
        print("The primary action function called")
#endif
    }
    
    private var example1: some View {
        GroupBox {
            VStack(alignment: .leading) {
                
                // Contextual information: a short intro to the elements we are showcasing
                Group {
                    Text( "Menus")
                        .fontWeight(.heavy)
                        .font(.title)
                    Text("A control for presenting a menu of actions.")
                        .fontWeight(.light)
                        .font(.title2)
                }
                
                HStack {
                    Text("Menu + Sub-Menu").fontWeight(.light)
                        .font(.title2)
                    Spacer()
                    Menu("Menu") {
                        Button("Duplicate", action: duplicate)
                        Button("Rename", action: rename)
                        Button("Delete…", action: delete)
                        Menu("+ Copy") {
                            Button("Copy", action: copy)
                            Button("Copy Formatted", action: copyFormatted)
                            Button("Copy Library Path", action: copyPath)
                        }
                    }
                }
                
            }
        }
        
    }
    
    private var example2: some View {
        GroupBox {
            VStack(alignment: .leading) {
                HStack{
                    Text("Menu + image").fontWeight(.light)
                        .font(.title2)
                    Spacer()
                    Menu {
                        Button("Open in Preview", action: action)
                        Button("Save as PDF", action: action)
                    } label: {
                        Label("PDF", systemImage: "doc.fill")
                    }
                }
            }
        }
        
    }
    
    private var example3: some View {
        /*
         Styling Menus
         Use the menuStyle(_:) modifier to change the style of all menus in a view.
         */
        GroupBox {
            VStack(alignment: .leading) {
                HStack {
                    Text("Styling Menus + action").fontWeight(.light)
                        .font(.title2)
                    Spacer()
                    Menu("Editing") {
                        Button("Set In Point", action: setInPoint)
                        Button("Set Out Point", action: setOutPoint)
                    }
                    .menuStyle(redBorderMenuStyle)
                }
                
            }
        }
        
    }
    
    private var example4: some View {
        GroupBox {
            VStack(alignment: .leading) {
                Text("Primary Action")
                    .fontWeight(.heavy)
                    .font(.title)
                Text("Menus can be created with a custom primary action. The primary action will be performed when the user taps or clicks on the body of the control, and the menu presentation will happen on a Medium gesture, such as on long press or on click of the menu indicator. The following example creates a menu that adds bookmarks, with advanced options that are presented in a menu.").fontWeight(.light)
                    .font(.title2)
                HStack {
                    Text("Menu + primary action").fontWeight(.light)
                        .font(.title2)
                    Spacer()
                    Menu {
                        Button(action: addCurrentTabToReadingList) {
                            Label("Add to Reading List", systemImage: "eyeglasses")
                        }
                        Button(action: bookmarkAll) {
                            Label("Add Bookmarks for All Tabs", systemImage: "book")
                        }
                        Button(action: show) {
                            Label("Show All Bookmarks", systemImage: "books.vertical")
                        }
                    } label: {
                        Label("Add Bookmark", systemImage: "book")
                    } primaryAction: {
                        primaryAction()
                    }
                }
            }
        }
        
    }
}

/*
 https://developer.apple.com/documentation/swiftui/menustyleconfiguration
 Overview
 Use the init(_:) initializer of Menu to create an instance using the current menu style, which you can modify to create a custom style.
 For example, the following code creates a new, custom style that adds a red border to the current menu style:
 */
struct RedBorderMenuStyle: MenuStyle {
    func makeBody(configuration: Configuration) -> some View {
        Menu(configuration)
            .border(Color.red)
    }
}

#Preview {
    
        MenusComponentView()
}

// MARK: - HASHABLE

extension MenusComponentView {
    
    static func == (lhs: MenusComponentView, rhs: MenusComponentView) -> Bool {
        return lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    
}


