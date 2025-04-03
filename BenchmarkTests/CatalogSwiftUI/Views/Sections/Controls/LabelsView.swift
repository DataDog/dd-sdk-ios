//
//  LabelsView.swift
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
/// Examples on how to use LABELS in SwiftUI
/// OFFICIAL DOCUMENTATION https://developer.apple.com/documentation/swiftui/label
///
struct LabelsView: View, Comparable {
    
    let id: String = "LabelsView"
    
    // Label Style
    // https://developer.apple.com/documentation/swiftui/labelstyle
    // please note that: some of the label style is available from iOS version 14.5 or above.
    var titleOnly: TitleOnlyLabelStyle = TitleOnlyLabelStyle.init()
    
    // Custom label Style
    /// For more extensive customization or to create a completely new label style,
    /// you'll need to adopt the ``LabelStyle`` protocol and implement a
    /// ``LabelStyleConfiguration`` for the new style.
    var redBorderedLabelStyle: RedBorderedLabelStyle = RedBorderedLabelStyle.init()
    
    var body: some View {
        
        PageContainer(content:
                        ScrollView {
            
            DocumentationLinkView(link: "https://developer.apple.com/documentation/swiftui/label", name: nil)
            
            VStack(alignment: .leading) {
                labelTypes
                    .modifier(Divided())
                labelsGroups
                    .modifier(Divided())
                labelsCustomViews
                    .modifier(Divided())
                truncationAndMultilineLabels
            }
            
            ContributedByView(name: "Ali Ghayeni H",
                              link: "https://github.com/alighayeni")
            .padding(.top, 80)
            
        })
    }
    
    // MARK: - LABEL TYPE
    
    private var labelTypes: some View {
        GroupBox {
            VStack(alignment: .leading) {
                
                // Contextual information: a short intro to the elements we are showcasing
                Group {
                    Text("Label Types")
                        .fontWeight(.heavy)
                        .font(.title)
                    Text("You can create a label in SwiftUI by adding an icon to it, using only a text or conbining text and icons in one label")
                        .fontWeight(.light)
                        .font(.title2)
                }
                
                VStack {
                    Spacer()
                    HStack {
                        Text("Label with icon:")
                        Spacer()
                        Label("Lightning",
                              systemImage: "bolt.fill")
                    }
                    Spacer()
                    HStack{
                        Text("Only label:")
                        Spacer()
                        Label("Lightning",
                              systemImage: "bolt.fill")
                        .labelStyle(titleOnly)
                    }
                    /* available only on iOS version 14.5 or above */
                    /// Conversely, there's also an icon-only label style:
                    ///
                    ///     Label("Lightning", systemImage: "bolt.fill")
                    ///         .labelStyle(IconOnlyLabelStyle())
                    ///
                    /// Some containers might apply a different default label style, such as only
                    /// showing icons within toolbars on macOS and iOS. To opt in to showing both
                    /// the title and the icon, you can apply the ``TitleAndIconLabelStyle`` label
                    /// style:
                    ///
                    ///     Label("Lightning", systemImage: "bolt.fill")
                    ///         .labelStyle(TitleAndIconLabelStyle())
                    ///
                    /// You can also create a customized label style by modifying an existing
                    /// style; this example adds a red border to the default label style:
                    ///
                    ///     struct RedBorderedLabelStyle : LabelStyle {
                    ///         func makeBody(configuration: Configuration) -> some View {
                    ///             Label(configuration)
                    ///                 .border(Color.red)
                    ///         }
                    ///     }
                    ///
                    
                    Spacer()
                    HStack{
                        Text("Only icon:")
                        Spacer()
                        Label("", systemImage: "bolt.fill")
                    }
                    Spacer()
                    HStack {
                        Text("Label, icon and custom style:")
                        Spacer()
                        Label("Lightning",
                              systemImage: "bolt.fill")
                        .labelStyle(redBorderedLabelStyle)
                        
                    }
                    Spacer()
                    
                    /// you csn customise the label with Text views check the following example
                    HStack {
                        Text("Label, icon and font:")
                        Spacer()
                        Label("Lightning",
                              systemImage: "bolt.fill")
                        .font(.title)
                    }
                }
            }
        }
        
    }
    
    // MARK: - LABEL GROUPS
    
    private var labelsGroups: some View {
        GroupBox {
            VStack(alignment: .leading) {
                VStack(alignment: .leading) {
                    Group {
                        Text( "Label groups")
                            .fontWeight(.heavy)
                            .font(.title)
                        Text("Labels can be grouped in other containers to layout them as a group")
                            .fontWeight(.light)
                            .font(.title2)
                        
                    }
                    HStack {
                        VStack {
                            Label("Rain", systemImage: "cloud.rain")
                            Label("Snow", systemImage: "snow")
                            Label("Sun", systemImage: "sun.max")
                        }
                        .foregroundColor(.accentColor)
                        .modifier(Divided())
                        
                        /// To apply a common label style to a group of labels, apply the style
                        /// to the view hierarchy that contains the labels:
                        VStack {
                            Label("Rain", systemImage: "cloud.rain")
                            Label("Snow", systemImage: "snow")
                            Label("Sun", systemImage: "sun.max")
                        }
                        .labelStyle(titleOnly)
                        .modifier(Divided())
                        
                        VStack {
                            Label("", systemImage: "cloud.rain")
                            Label("", systemImage: "snow")
                            Label("", systemImage: "sun.max")
                        }
                        .foregroundColor(.accentColor)
                        
                    }
                    .modifier(ViewAlignmentModifier(alignment: .center))
                    
                }
            }
        }
        
    }
    
    // MARK: - TRUNCATION AND MULTILINE
    
    private var truncationAndMultilineLabels: some View {
        GroupBox {
            VStack(alignment: .leading) {
                Group {
                    Text("Truncations and multiline")
                        .fontWeight(.heavy)
                        .font(.title)
                    Text("Similar configuration as there were in UIKit can be applied in SwiftUI to manage truncation and multiline text in a label")
                        .fontWeight(.light)
                        .font(.title2)
                }
                
                Label(
                    title: { Text("Very long text truncated")
                            .multilineTextAlignment(.center)
                    },
                    icon: {}
                )
                .frame(width: 150, height: 100, alignment: .center)
                .lineLimit(1)
                .allowsTightening(false)
                .truncationMode(.middle)
                
                Label(
                    title: { Text("Multiline text arranged in how many lines as it is needed")
                            .multilineTextAlignment(.center)
                    },
                    icon: {}
                )
                .lineLimit(2)
                .minimumScaleFactor(0.6)
                .allowsTightening(true)
                .truncationMode(.middle)
            }
        }
        
    }
    
    // MARK: - LABEL WITH CUSTOM VIEWS
    
    private var labelsCustomViews: some View {
        GroupBox {
            VStack(alignment: .leading) {
                Text( "Label With Custom Views")
                    .fontWeight(.heavy)
                    .font(.title)
                Text("It's also possible to make labels using views to compose the label's icon")
                    .fontWeight(.light)
                    .font(.title2)
                
                /// It's also possible to make labels using views to compose the label's icon
                /// programmatically, rather than using a pre-made image. In this example, the
                /// icon portion of the label uses a filled ``Circle`` overlaid
                /// with the user's initials:
                Label {
                    Text("Lightning Body")
                        .font(.body)
                        .foregroundColor(.primary)
                    Text("Lightning SubHeadline")
                        .font(.subheadline)
                        .foregroundColor(Color("Medium", bundle: .module))
                } icon: {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 44, height: 44, alignment: .center)
                        .overlay(Text("A+").foregroundColor(.white))
                }
            }
        }
        
    }
}

/// You can also create a customized label style by modifying an existing
/// style; this example adds a red border to the default label style:
struct RedBorderedLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        Label(configuration)
            .border(/*@START_MENU_TOKEN@*/Color.black/*@END_MENU_TOKEN@*/, width: 2)
    }
}

#Preview {
    
        LabelsView()
}

// MARK: - HASHABLE

extension LabelsView: Hashable {
    
    static func == (lhs: LabelsView, rhs: LabelsView) -> Bool {
        return lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    
}


