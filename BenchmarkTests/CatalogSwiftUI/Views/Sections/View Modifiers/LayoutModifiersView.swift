//
//  LayoutModifiersView.swift
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

///
/// Examples on how to use  Layout Modifiers  in SwiftUI
/// OFFICIAL DOCUMENTATION:
/// Open the "Add modifier" panels in XCode and inspect all possible "Layout Modifiers" to provide examples here
///

struct LayoutModifiersView: View, Comparable {
    
    let id: String = "LayoutModifiersView"
    
    /// current stack view alignment
    @State var verticalAlignment: VerticalAlignment = .center
    
    /// some offset to exemplify individual item's alignment
    let offsets: [CGFloat] = [-15, -50, 15, 50]
    /// current selected offset index
    private var offsetIndex: Int = 0
    
    /// current aspect ratio
    @State var aspectRatio: CGFloat = 0.8
    /// the currently selected content mode
    @State var mode: AspectRatioModePicker.Mode = .fill
    
    var body: some View {
        
        ScrollView {
            anchorPreferences
            alignmentExamples
        }
        
    }
    
    private var anchorPreferences: some View {
        Group {
            VStack(alignment: .leading) {
                DocumentationLinkView(link: "https://developer.apple.com/documentation/swiftui/view/alignmentguide(_:computevalue:)-6y3u2", name: "ASPECT RATIO")
                    .padding(.vertical, Style.VerticalPadding.medium.rawValue)
                Text("A view can be modified in its aspect ratio and content mode")
                    .fontWeight(.light)
                    .font(.title2)
                Image(systemName: "paperplane")
                    .resizable()
                    .aspectRatio(aspectRatio, contentMode: mode.contentMode)
                    .frame(width: 100, height: 100)
                    .modifier(ViewAlignmentModifier(alignment: .center))
                    .padding()
                AspectRatioModePicker(selection: $aspectRatio,
                                      mode: $mode)
                .pickerStyle(.palette)
            }
            .padding(.horizontal, Style.HorizontalPadding.medium.rawValue)
        }
    }
    
    
    private var alignmentExamples: some View {
        VStack {
            
            VStack {
                DocumentationLinkView(link: "https://developer.apple.com/documentation/swiftui/view/alignmentguide(_:computevalue:)-6y3u2", name: "LAYOUT MODIFIER")
                    .padding()
                
                Text("Views can be vertically aligned in respect to each other using precise offsets for each view, or using the view dimensions to calculate offsets")
                    .fontWeight(.light)
                    .font(.title2)
                    .padding()
                VStack {
                    ForEach(0..<offsets.count, id: \.self) { index in
                        HStack{
                            Text("Offset \(offsets[index])")
                            Image(systemName: "lasso")
                                .alignmentGuide(VerticalAlignment.center, computeValue: { dimension in
                                    offsets[index]
                                })
                        }
                        Divider()
                            .padding(.horizontal, Style.HorizontalPadding.medium.rawValue * 2)
                    }
                }
            }
            VStack {
                Text("Horizontal stack views can have different alignments in each of their views, which could make the overall layout look nicer or achieve a particular design requirement")
                    .fontWeight(.light)
                    .font(.title2)
                    .padding()
                HStack(alignment: verticalAlignment) {
                    Image(systemName: "eraser")
                    Text("Delete")
                        .font(.caption)
                    Text("Note")
                        .font(.title)
                }
                .padding()
                .border(Color("Medium", bundle: .module), width: 1)
                VerticalAlignmentPicker(selection: $verticalAlignment)
                    .pickerStyle(.wheel)
            }
            Divider()
            VStack(alignment: .leading) {
                Text("Views typically have a default priority of 0 which causes space to be apportioned evenly to all sibling views. Raising a view’s layout priority encourages the higher priority view to shrink later when the group is shrunk and stretch sooner when the group is stretched.")
                    .fontWeight(.light)
                    .font(.title2)
                    .padding()
                HStack {
                    VStack(alignment: .leading) {
                        Text("Life is too short to wait! Start now.")
                        Text("layoutPriority(1)")
                    }
                    .background(Color.secondary.opacity(0.5))
                    .layoutPriority(1)
                    
                    Text("Only in the darkness you can see stars.")
                        .background(Color.secondary.opacity(0.5))
                }
                .padding(.horizontal)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }
}

#Preview {
    
        LayoutModifiersView()
    
}


// MARK: - HASHABLE

extension LayoutModifiersView {
    
    static func == (lhs: LayoutModifiersView, rhs: LayoutModifiersView) -> Bool {
        return lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    
}

extension VerticalAlignment: Hashable {
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(self.description)
    }
    
}

extension VerticalAlignment {
    
    var description: String {
        switch self {
        case .bottom: "bottom"
        case .top: "top"
        case .center: "center"
        case .firstTextBaseline: "first base line"
        case .lastTextBaseline: "last base line"
        default:
            ""
        }
    }
    
}
