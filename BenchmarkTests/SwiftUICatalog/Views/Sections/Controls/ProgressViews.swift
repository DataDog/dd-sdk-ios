//
//  ProgressViews.swift
//  SwiftUICatalog
//
// MIT License
//
// Copyright (c) 2021 Barbara Martina Rodeker
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
/// Examples on how to use  PROGRESS VIEW  in SwiftUI
/// OFFICIAL DOCUMENTATION:     https://developer.apple.com/documentation/swiftui/progressview
///

struct ProgressViews: View, Comparable {
    
    let id: String = "ProgressViews"
    
    @State private var progress = 0.0
    private let timer = Timer.publish(every: 0.5,
                                      on: .main,
                                      in: .common).autoconnect()
    
    
    var body: some View {
        
        PageContainer(content: ScrollView {
            
            DocumentationLinkView(link: "https://developer.apple.com/documentation/swiftui/progressview", name: "PROGRESS VIEW")
            
            plainProgressViews
                .modifier(Divided())
            tintedProgressView
                .modifier(Divided())
            subviewsInProgressView
            
            ContributedByView(name: "Barbara Martina",
                              link: "https://github.com/barbaramartina")
            .padding(.top, 80)
            
        }
            .onReceive(timer) { _ in
                if progress < 100 {
                    progress += 2
                }
            }
        )
        
    }
    
    private var plainProgressViews: some View {
        Group {
            Text("Progress views are used to indicate steps in a task, or to show feedback while waiting for results. \nExample 1: The first example is a linear progress view with a title shown at the top of the progress bar.")
                .fontWeight(.light)
                .font(.title2)
                .padding(.bottom)
                .modifier(ViewAlignmentModifier(alignment: .leading))
            Text("Example 2: Simple progress views can also be used, and the progress bar won't have an associated title.")
                .fontWeight(.light)
                .font(.title2)
                .padding(.vertical, Style.VerticalPadding.medium.rawValue)
                .modifier(ViewAlignmentModifier(alignment: .leading))
            Text("Example 3: A spinner can also be shown with a text associated.")
                .fontWeight(.light)
                .font(.title2)
                .padding(.vertical, Style.VerticalPadding.medium.rawValue)
                .modifier(ViewAlignmentModifier(alignment: .leading))
            
            
            GroupBox {
                VStack(alignment: .center) {
                    ProgressView("Downloading…",
                                 value: progress,
                                 total: 100)
                    .padding(.vertical)
                    .modifier(Divided())
                    
                    ProgressView()
                        .padding(.vertical)
                        .modifier(Divided())
                    
                    ProgressView("Downloading")
                        .padding(.vertical)
                        .modifier(Divided())
                    
                    ProgressView("Please wait...")
                        .progressViewStyle(CircularProgressViewStyle(tint: .accentColor))
                        .padding(.bottom)
                    
                }
            }
        }
    }
    
    private var subviewsInProgressView: some View {
        Group {
            Text("Also any view can be included inside the progress view, such as in this case, a button.")
                .fontWeight(.light)
                .font(.title2)
                .padding(.vertical, Style.VerticalPadding.medium.rawValue)
                .modifier(ViewAlignmentModifier(alignment: .leading))
            
            GroupBox {
                VStack(alignment: .leading) {
                    ProgressView {
                        Button(action: {
                            // to do: your cancellation logic
                        }) {
                            Text("Cancel download")
                                .fontWeight(.heavy)
                                .font(.title)
                                .foregroundColor(.accentColor)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color("Medium", bundle: .module))
                        .cornerRadius(5)
                        .padding()
                    }
                    
                }
            }
        }
    }
    
    private var tintedProgressView: some View {
        Group {
            Text("The color of the spinner can be changed with a tint color of your choice.")
                .fontWeight(.light)
                .font(.title2)
                .padding(.vertical, Style.VerticalPadding.medium.rawValue)
                .modifier(ViewAlignmentModifier(alignment: .leading))
            
            GroupBox {
                VStack(alignment: .leading) {
                    
                    ProgressView("Please wait...", value: progress,
                                 
                                 total: 100)
                    .progressViewStyle(LinearProgressViewStyle(tint: .accentColor))
                    .foregroundColor(Color("Medium", bundle: .module))
                    .padding(.vertical)
                    
                }
            }
        }
    }
}

#Preview {
    
        ProgressViews()
    
}

// MARK: - HASHABLE

extension ProgressViews {
    
    static func == (lhs: ProgressViews, rhs: ProgressViews) -> Bool {
        return lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    
}



