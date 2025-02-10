//
//  CanvasView.swift
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
/// Examples on how to use  CANVAS  in SwiftUI
/// OFFICIAL DOCUMENTATION:
/// https://developer.apple.com/documentation/swiftui/canvas
///

struct CanvasView: View, Comparable {
    
    let id: String = "CanvasView"
    
    private let spaces: [CGRect] = [CGRect(x: 0,
                                           y: 0,
                                           width: 100,
                                           height: 100),
                                    CGRect(x: 10,
                                           y: 10,
                                           width: 10,
                                           height: 10),
                                    CGRect(x: 100,
                                           y: 0,
                                           width: 200,
                                           height: 200)]
    private let circle = Image(systemName: "circle")
    private let square = Image(systemName: "square")
    
    enum ViewId: Int {
        case circle
        case square
    }
    
    var body: some View {
        
        PageContainer(content: ScrollView {
            
            DocumentationLinkView(link: "https://developer.apple.com/documentation/swiftui/canvas")
            
            VStack(alignment: .leading) {
                GroupBox {
                    intro1
                    canvas1
                }
                
                .modifier(Divided())
                GroupBox {
                    intro2
                    canvas2
                }
                .modifier(Divided())
                GroupBox {
                    Text("A canvas can be a great ally when trying to draw custom graphs, like the one at continuation, where random images are plot on a graph")
                        .fontWeight(.light)
                        .font(.title2)
                    canvas3
                }
                
                .modifier(Divided())
                Text("Accessibility and interaction for specific elements—such as views that you pass in as symbols—are not provided by a canvas. However, a canvas perform better in the case of a complex drawing. To enhance performance for a drawing that doesn't primarily require interactive features or text you can use a canvas.")
                    .fontWeight(.light)
                    .font(.title2)
            }
            
            ContributedByView(name: "Barbara Martina",
                              link: "https://github.com/barbaramartina")
            .padding(.top, 80)
            
            
        })
        
    }
    
    private var intro1: some View {
        Group {
            Text("Canvas views")
                .fontWeight(.heavy)
                .font(.title)
            Text("A canvas can be used to render 2D drawings You can use a graphic context and draw on it to create vibrant, dynamic 2D images inside of a SwiftUI display. \nTo conduct immediate mode drawing operations, you use the closure that receives a GraphicsContext from the canvas. You can also modify what you draw by using the CGSize value that the canvas passes. ")
                .fontWeight(.light)
                .font(.title2)
        }
        
    }
    
    private var canvas1: some View {
        Canvas { context, size in
            context.stroke(
                Path(ellipseIn: CGRect(origin: .zero, size: size)),
                with: .color(.purple),
                lineWidth: 4)
            
            let halfSize = size.applying(CGAffineTransform(scaleX: 0.5, y: 0.5))
            context.clip(to: Path(CGRect(origin: .zero, size: halfSize)))
            context.fill(
                Path(ellipseIn: CGRect(origin: .zero, size: size)),
                with: .color(Color("Medium", bundle: .module)))
        }
        .frame(width: 300, height: 200)
        .border(Color.blue)
        
    }
    
    private var intro2: some View {
        Text("Or you can use a canvas and fill it with renderable SwiftUI views.")
            .fontWeight(.light)
            .font(.title2)
        
    }
    
    private var canvas2: some View {
        Canvas { context, size in
            if let circle = context.resolveSymbol(id: ViewId.circle) {
                for rect in spaces {
                    context.draw(circle, in: rect)
                }
            }
            if let square = context.resolveSymbol(id: ViewId.square) {
                for rect in spaces {
                    context.draw(square, in: rect)
                }
            }
        } symbols: {
            circle.tag(ViewId.circle)
            square.tag(ViewId.square)
        }
        .frame(width: 300, height: 200)
        .border(Color.blue)
        
    }
    
    private var randomRects: [CGRect] {
        var result = [CGRect]()
        for _ in 0...60 {
            result.append(CGRect(x: CGFloat.random(in: 0...300),
                                 y: CGFloat.random(in: 0...200),
                                 width: CGFloat.random(in: 10...30),
                                 height: CGFloat.random(in: 10...30)))
        }
        return result
    }
    private var canvas3: some View {
        PlotView(rects: randomRects, mark: Image(systemName: "hands.and.sparkles.fill"))
    }
}

#Preview {
        CanvasView()
}

// MARK: - HASHABLE

extension CanvasView {
    
    static func == (lhs: CanvasView, rhs: CanvasView) -> Bool {
        return lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    
}


struct PlotView<Mark: View>: View {
    let rects: [CGRect]
    let mark: Mark
    
    
    enum SymbolID: Int {
        case mark
    }
    
    var body: some View {
        Canvas { context, size in
            if let mark = context.resolveSymbol(id: SymbolID.mark) {
                for rect in rects {
                    context.draw(mark, in: rect)
                }
            }
        } symbols: {
            mark.tag(SymbolID.mark)
        }
        .frame(width: 300, height: 200)
        .border(Color.blue)
    }
}

