//
//  GeomtriesView.swift
//  SwiftUICatalog
//
// MIT License
//
// Copyright (c) 2022 Barbara Martina
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
/// Examples on how to use  GEOMETRIES  in SwiftUI
/// OFFICIAL DOCUMENTATION:
/// https://developer.apple.com/documentation/swiftui/geometryreader
/// https://developer.apple.com/documentation/swiftui/geometryproxy
/// https://developer.apple.com/documentation/swiftui/geometryeffect
/// https://developer.apple.com/documentation/swiftui/anchor
/// https://developer.apple.com/documentation/swiftui/unitpoint
/// https://developer.apple.com/documentation/swiftui/angle
/// https://developer.apple.com/documentation/swiftui/projectiontransform
/// https://developer.apple.com/documentation/swiftui/vectorarithmetic
///

struct GeometriesView: View, Comparable {
    
    let id: String = "GeometriesView"
    
    @State private var offset: CGFloat = 200
    @State private var textDirection: CGFloat = 1
    
    var body: some View {
        
        PageContainer(content:
                        
                        VStack(alignment: .leading) {
            
            DocumentationLinkView(link: "https://developer.apple.com/documentation/swiftui/geometryreader", name: "GEOMETRY")
            
            GroupBox {
                Text("Reading geometries")
                    .fontWeight(.heavy)
                    .font(.title)
                
                Text("Geometry readers can be use to provide a layout definition by assigned percentages of the available width to each view")
                    .fontWeight(.light)
                    .font(.title2)
                GeometryReader { geometry in
                    HStack(spacing: 0) {
                        Spacer()
                        Text("First item")
                            .font(.largeTitle)
                            .foregroundColor(Color("Medium", bundle: .module))
                            .frame(width: geometry.size.width * 0.30)
                            .background(.primary)
                            .minimumScaleFactor(0.5)
                        
                        Text("Second item")
                            .font(.largeTitle)
                            .foregroundColor(.primary)
                            .frame(width: geometry.size.width * 0.60)
                            .background(Color("Medium", bundle: .module))
                            .minimumScaleFactor(0.5)
                        Spacer()
                    }
                }
                .frame(height: 50)
            }
            .modifier(Divided())
            
            GroupBox {
                Text("A geometry reader reads the size of the view he's executed in and return a geometry proxy to access width and height of the view")
                    .fontWeight(.light)
                    .font(.title2)
                    .padding()
                
                Text("Effects on geometries")
                    .fontWeight(.heavy)
                    .font(.title)
                
                Text("Geometry effects on views can be used to produce transformations to the frames and in that way create new animations")
                    .fontWeight(.light)
                    .font(.title2)
                
                Text("Animated")
                    .modifier(PingPongEffect(offset: self.offset,
                                             direction: self.textDirection))
                    .onAppear {
                        withAnimation(Animation.easeInOut(duration: 2.0).repeatForever()) {
                            self.offset = (-1) * self.offset
                            self.textDirection = (-1) * self.textDirection
                        }
                    }
            }
        })
    }
    
}

#Preview {
    
        GeometriesView()
    
}

struct PingPongEffect: GeometryEffect {
    
    private var offset: CGFloat
    private var direction: CGFloat
    
    init(offset: CGFloat, direction: CGFloat) {
        self.offset = offset
        self.direction = direction
    }
    
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(offset, direction) }
        set {
            offset = newValue.first
            direction = newValue.second
        }
    }
    
    func effectValue(size: CGSize) -> ProjectionTransform {
        return ProjectionTransform(CGAffineTransform(a: 1,
                                                     b: 0,
                                                     c: self.direction,
                                                     d: 1,
                                                     tx: self.offset,
                                                     ty: 0))
    }
}

// MARK: - HASHABLE

extension GeometriesView {
    
    static func == (lhs: GeometriesView, rhs: GeometriesView) -> Bool {
        return lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    
}


