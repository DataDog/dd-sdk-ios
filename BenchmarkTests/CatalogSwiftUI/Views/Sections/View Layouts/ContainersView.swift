//
//  ContainersView.swift
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
/// Examples on how to use  CONTAINERS  in SwiftUI
/// OFFICIAL DOCUMENTATION:     https://developer.apple.com/documentation/swiftui/controlgroup
/// https://developer.apple.com/documentation/swiftui/groupbox
/// https://developer.apple.com/documentation/swiftui/group
/// https://developer.apple.com/documentation/swiftui/form
///

struct ContainersView: View, Comparable {
    
    let id: String = "ContainersView"
    
    @State var toggleOn: Bool = true
    
    var body: some View {
        
        PageContainer(content:
                        
                        VStack(alignment: .leading) {
            
            DocumentationLinkView(link: "https://developer.apple.com/documentation/swiftui/controlgroup", name: "CONTAINERS")
            
            containersIntro
                .modifier(Divided())
            formExample
                .modifier(Divided())
            groupBoxExample
            
            ContributedByView(name: "Barbara Martina",
                              link: "https://github.com/barbaramartina")
            .padding(.top, 80)
            
        }
        )
        // end of page container
        
    }
    
    private var groupBoxExample: some View {
        Group {
            Text("Similarly, GroupBox is used for distinguishing a set of views in the screen (in an alert type box)")
                .fontWeight(.light)
                .font(.title2)
            
            GroupBox(label:
                        Label("Terms and conditions", systemImage: "building.columns"),
                     content: {
                Text("Lorem ipsum dolor sit amet, consectetur adipiscing elit. Vestibulum vitae tempor erat, non semper lorem. Suspendisse ac dui posuere, egestas elit ac, viverra mauris. Class aptent taciti sociosqu ad litora torquent per conubia nostra, per inceptos himenaeos. Etiam bibendum mattis libero, ac porta magna blandit et. Vivamus vel elementum sapien. Proin ut orci vitae eros lobortis facilisis nec id leo. Ut vestibulum mauris nulla, eget efficitur risus facilisis euismod. Fusce arcu libero, mollis non volutpat vitae, interdum vitae odio. Suspendisse in quam egestas, rutrum massa vitae, consectetur enim.")
                HStack {
                    Spacer()
                    Button(action: {},
                           label: {
                        Text("Accept")
                    })
                    .foregroundColor(.accentColor)
                }
            }
            )
            
        }
    }
    
    private var containersIntro: some View {
        Group {
            Text("View containers")
                .fontWeight(.heavy)
                .font(.title)
            Text("Some controls in SwiftUI allows grouping of other views, for example the Form component allows to group other views together and platform specific styling is then applied to all the contained views")
                .fontWeight(.light)
                .font(.title2)
            
        }
        
    }
    
    private var formExample: some View {
        Form {
            Section(header: Text("Section 1")) {
                Toggle(
                    isOn: $toggleOn,
                    label: {
                        Text("Option 1")
                    }
                    
                )
                Toggle(
                    isOn: $toggleOn,
                    label: {
                        Text("Option 2")
                    }
                )
            }
            Section(header: Text("Section 2")) {
                Button("Action 1") {}
            }
        }
        .frame(height: 250)
        
    }
}

#Preview {
    
        ContainersView()
    
}

// MARK: - HASHABLE

extension ContainersView {
    
    static func == (lhs: ContainersView, rhs: ContainersView) -> Bool {
        return lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    
}



